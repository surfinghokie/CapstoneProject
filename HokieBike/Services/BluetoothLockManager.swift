import Foundation
import CoreBluetooth
import Combine

@MainActor
final class BluetoothLockManager: NSObject, ObservableObject {
    @Published var statusMessage: String = ""
    @Published var isBusy = false
    @Published var isScanning = false
    @Published var discoveredDevices: [DiscoveredDevice] = []

    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let isCandidate: Bool
        let advertisedUUIDs: [String]
    }

    // Firmware docs mention all dev boards can share name, so this is only a fallback hint.
    private let expectedNamePrefix = "VT-LOCK"

    private enum LockUUID {
        static let service = CBUUID(string: "8F2A1C00-5B7E-4D19-9A3F-6C2E81D4B70A")
        static let command = CBUUID(string: "8F2A1C01-5B7E-4D19-9A3F-6C2E81D4B70A")
        static let status = CBUUID(string: "8F2A1C02-5B7E-4D19-9A3F-6C2E81D4B70A")
        static let info = CBUUID(string: "8F2A1C03-5B7E-4D19-9A3F-6C2E81D4B70A")
    }

    private enum CommandResult {
        case ok
        case noChange
        case busy
        case unknown

        init(_ raw: UInt8) {
            switch raw {
            case 0: self = .ok
            case 1: self = .noChange
            case 2: self = .busy
            default: self = .unknown
            }
        }
    }

    private enum LockState: Equatable {
        case locked
        case unlocking
        case unlocked
        case locking
        case unknown

        init(_ raw: UInt8) {
            switch raw {
            case 0: self = .locked
            case 1: self = .unlocking
            case 2: self = .unlocked
            case 3: self = .locking
            default: self = .unknown
            }
        }

        var isSettled: Bool {
            self == .locked || self == .unlocked
        }
    }

    private struct LockStatus {
        let state: LockState
        let lastResult: CommandResult
        let resultSeq: UInt8

        init?(_ data: Data) {
            let bytes = Array(data)
            guard bytes.count >= 4 else { return nil }
            state = LockState(bytes[0])
            lastResult = CommandResult(bytes[2])
            resultSeq = bytes[3]
        }
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    private var expectedResultSeq: UInt8?
    private var waitingForSettle = false
    private var sawInitialStatus = false
    private var hasConnectedPeripheral = false
    private var attemptedBroadScan = false
    private var isBroadScanMode = false
    private var shouldResumeBroadScanAfterDisconnect = false
    private var attemptedPeripheralIDs: Set<UUID> = []

    private func resetDiscoveryUI() {
        discoveredDevices = []
        isScanning = false
    }

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func unlockDemoBike() async -> Bool {
        guard !isBusy else {
            statusMessage = "Unlock already in progress."
            return false
        }

        #if targetEnvironment(simulator)
        statusMessage = "Simulator mode: unlock simulated as success."
        return true
        #else
        if #available(iOS 13.0, *) {
            let auth = CBManager.authorization
            if auth == .denied || auth == .restricted {
                statusMessage = "Bluetooth permission denied. Enable HokieBike in Settings > Privacy & Security > Bluetooth."
                return false
            }
        }

        isBusy = true
        statusMessage = "Scanning for lock..."
        resetDiscoveryUI()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.sawInitialStatus = false
            self.waitingForSettle = false
            self.expectedResultSeq = nil
            self.characteristics = [:]
            self.hasConnectedPeripheral = false
            self.attemptedBroadScan = false
            self.isBroadScanMode = false
            self.shouldResumeBroadScanAfterDisconnect = false
            self.attemptedPeripheralIDs = []

            guard let central else {
                finish(success: false, message: "Bluetooth unavailable on this device.")
                return
            }

            if central.state == .poweredOn {
                startScan(filtered: true)
            } else {
                scheduleTimeout(seconds: 5, message: "Waiting for Bluetooth to become ready...")
            }
        }
        #endif
    }

    private func startScan(filtered: Bool) {
        guard let central else { return }
        isBroadScanMode = !filtered
        isScanning = true
        statusMessage = filtered ? "Scanning for lock..." : "Expanded scan running..."
        central.stopScan()
        central.scanForPeripherals(withServices: filtered ? [LockUUID.service] : nil)

        if filtered {
            scheduleBroadScanFallback()
        }
        scheduleTimeout(seconds: 12, message: "Lock not found. Ensure lock is powered on and not connected to another phone.")
    }

    private func scheduleBroadScanFallback() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.continuation != nil, !self.hasConnectedPeripheral, !self.attemptedBroadScan else { return }
            self.attemptedBroadScan = true
            self.startScan(filtered: false)
        }
    }

    private func isCandidateLock(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           serviceUUIDs.contains(LockUUID.service) {
            return true
        }

        if let overflowUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID],
           overflowUUIDs.contains(LockUUID.service) {
            return true
        }

        if let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?.uppercased(),
           localName.contains(expectedNamePrefix) {
            return true
        }

        if let name = peripheral.name?.uppercased(), name.contains(expectedNamePrefix) {
            return true
        }

        return false
    }

    private func advertisedUUIDList(from advertisementData: [String: Any]) -> [String] {
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let overflowUUIDs = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        let all = serviceUUIDs + overflowUUIDs
        return Array(Set(all.map(\.uuidString))).sorted()
    }

    private func resumeBroadScanAfterReject(_ message: String) {
        statusMessage = message
        shouldResumeBroadScanAfterDisconnect = true
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScan(filtered: false)
        }
    }

    private func scheduleTimeout(seconds: Double, message: String) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.continuation != nil else { return }
            self.finish(success: false, message: message)
        }
    }

    private func finish(success: Bool, message: String) {
        statusMessage = message
        timeoutTask?.cancel()
        timeoutTask = nil
        shouldResumeBroadScanAfterDisconnect = false
        isScanning = false

        central?.stopScan()

        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }

        if let continuation {
            self.continuation = nil
            self.isBusy = false
            continuation.resume(returning: success)
        } else {
            isBusy = false
        }
    }
}

extension BluetoothLockManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard continuation != nil else { return }

        switch central.state {
        case .poweredOn:
            startScan(filtered: true)
        case .poweredOff:
            finish(success: false, message: "Bluetooth is off. Turn it on and try again.")
        case .unauthorized:
            finish(success: false, message: "Bluetooth permission denied. Enable it in Settings > Privacy & Security > Bluetooth.")
        case .unsupported:
            finish(success: false, message: "Bluetooth is unsupported on this device.")
        case .resetting:
            scheduleTimeout(seconds: 5, message: "Bluetooth is resetting. Try again in a moment.")
        case .unknown:
            scheduleTimeout(seconds: 5, message: "Bluetooth state unknown. Waiting...")
        @unknown default:
            finish(success: false, message: "Unknown Bluetooth state.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let discoveredAsCandidate = isCandidateLock(peripheral, advertisementData: advertisementData)
        let displayName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        let advertisedUUIDs = advertisedUUIDList(from: advertisementData)

        if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[idx] = DiscoveredDevice(
                id: peripheral.identifier,
                name: displayName,
                rssi: RSSI.intValue,
                isCandidate: discoveredAsCandidate,
                advertisedUUIDs: advertisedUUIDs
            )
        } else {
            discoveredDevices.append(
                DiscoveredDevice(
                    id: peripheral.identifier,
                    name: displayName,
                    rssi: RSSI.intValue,
                    isCandidate: discoveredAsCandidate,
                    advertisedUUIDs: advertisedUUIDs
                )
            )
        }

        discoveredDevices.sort { $0.rssi > $1.rssi }
        if discoveredDevices.count > 10 {
            discoveredDevices = Array(discoveredDevices.prefix(10))
        }

        guard !attemptedPeripheralIDs.contains(peripheral.identifier) else { return }
        if !discoveredAsCandidate {
            // In broad scan fallback, probe plausible nearby peripherals even if names are unexpected.
            guard isBroadScanMode, RSSI.intValue > -90 else { return }
        }

        central.stopScan()
        isScanning = false
        attemptedPeripheralIDs.insert(peripheral.identifier)
        hasConnectedPeripheral = true
        self.peripheral = peripheral
        peripheral.delegate = self
        statusMessage = "Connecting to \(displayName)..."
        central.connect(peripheral)
        scheduleTimeout(seconds: 10, message: "Could not connect to lock.")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusMessage = "Preparing lock..."
        peripheral.discoverServices([LockUUID.service])
        scheduleTimeout(seconds: 5, message: "Lock service discovery timed out.")
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(success: false, message: "Failed to connect to lock.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        self.characteristics = [:]

        guard continuation != nil else { return }
        if shouldResumeBroadScanAfterDisconnect {
            shouldResumeBroadScanAfterDisconnect = false
            startScan(filtered: false)
            return
        }
        if isBusy {
            finish(success: false, message: "Disconnected before unlock completed.")
        }
    }
}

extension BluetoothLockManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == LockUUID.service }) else {
            if isBroadScanMode {
                resumeBroadScanAfterReject("Found non-lock BLE device. Continuing scan...")
            } else {
                finish(success: false, message: "Lock service unavailable.")
            }
            return
        }

        peripheral.discoverCharacteristics([LockUUID.command, LockUUID.status, LockUUID.info], for: service)
        scheduleTimeout(seconds: 5, message: "Lock characteristics timed out.")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            if isBroadScanMode {
                resumeBroadScanAfterReject("Non-lock characteristics detected. Continuing scan...")
            } else {
                finish(success: false, message: "Could not read lock characteristics.")
            }
            return
        }

        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
        }

        guard let info = characteristics[LockUUID.info], characteristics[LockUUID.command] != nil, characteristics[LockUUID.status] != nil else {
            if isBroadScanMode {
                resumeBroadScanAfterReject("Incomplete lock profile. Continuing scan...")
            } else {
                finish(success: false, message: "Lock firmware is missing required characteristics.")
            }
            return
        }

        peripheral.readValue(for: info)
        scheduleTimeout(seconds: 5, message: "Lock info check timed out.")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else {
            finish(success: false, message: "Lock communication failed.")
            return
        }

        switch characteristic.uuid {
        case LockUUID.info:
            let bytes = Array(value)
            guard bytes.count >= 5, bytes[0] == 1 else {
                finish(success: false, message: "Incompatible lock protocol version.")
                return
            }

            guard let status = characteristics[LockUUID.status] else {
                finish(success: false, message: "Status characteristic missing.")
                return
            }

            peripheral.setNotifyValue(true, for: status)
            scheduleTimeout(seconds: 5, message: "Could not subscribe to lock status.")

        case LockUUID.status:
            guard let lockStatus = LockStatus(value) else {
                finish(success: false, message: "Malformed lock status response.")
                return
            }

            if !sawInitialStatus {
                sawInitialStatus = true
                expectedResultSeq = lockStatus.resultSeq &+ 1
                guard let command = characteristics[LockUUID.command] else {
                    finish(success: false, message: "Command characteristic missing.")
                    return
                }

                statusMessage = "Sending unlock command..."
                peripheral.writeValue(Data([0x01]), for: command, type: .withResponse)
                scheduleTimeout(seconds: 5, message: "Unlock command timed out.")
                return
            }

            if let expectedResultSeq, lockStatus.resultSeq == expectedResultSeq {
                switch lockStatus.lastResult {
                case .ok:
                    waitingForSettle = true
                    self.expectedResultSeq = nil
                    statusMessage = "Unlocking..."
                    scheduleTimeout(seconds: 10, message: "Lock did not settle in time.")
                case .noChange:
                    finish(success: true, message: "Lock already unlocked.")
                case .busy:
                    finish(success: false, message: "Lock is busy. Please try again.")
                case .unknown:
                    finish(success: false, message: "Unlock failed with unknown result.")
                }
            }

            if waitingForSettle && lockStatus.state.isSettled {
                waitingForSettle = false
                if lockStatus.state == .unlocked {
                    finish(success: true, message: "Bike unlocked.")
                } else {
                    finish(success: false, message: "Lock settled but remained locked.")
                }
            }

        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            finish(success: false, message: "Status notification failed.")
            return
        }

        // Required by firmware contract: explicitly read status after subscribe.
        peripheral.readValue(for: characteristic)
        scheduleTimeout(seconds: 5, message: "Could not read initial lock status.")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            finish(success: false, message: "Lock rejected unlock write.")
        }
    }
}

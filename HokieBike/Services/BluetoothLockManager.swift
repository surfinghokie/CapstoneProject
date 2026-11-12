import Foundation
import CoreBluetooth
import Combine

@MainActor
final class BluetoothLockManager: NSObject, ObservableObject {
    @Published var statusMessage: String = ""
    @Published var isBusy = false
    @Published var isScanning = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var sessionStep: String = "Idle"
    @Published var lastKnownStateText: String = "Unknown"
    @Published var lastCheckedAt: Date?

    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let isCandidate: Bool
        let advertisedUUIDs: [String]
    }

    private enum Timeout {
        static let scan: Double = 10
        static let connect: Double = 10
        static let discover: Double = 5
        static let infoRead: Double = 5
        static let subscribe: Double = 5
        static let initialStatusRead: Double = 5
        static let writeResult: Double = 5
        static let settle: Double = 10
    }

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

    private enum LockCommand {
        case unlock
        case lock

        var opcode: UInt8 {
            switch self {
            case .unlock: return 0x01
            case .lock: return 0x00
            }
        }

        var verb: String {
            switch self {
            case .unlock: return "unlock"
            case .lock: return "lock"
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
    private var queuedCommand: LockCommand?
    private var currentCommand: LockCommand = .unlock
    private var hasSentCommand = false

    private enum SessionMode {
        case refreshOnly
        case command(LockCommand)
    }

    private var sessionMode: SessionMode = .command(.unlock)

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
        await run(command: .unlock)
    }

    func lockDemoBike() async -> Bool {
        await run(command: .lock)
    }

    func refreshLockStatus() async -> Bool {
        await run(mode: .refreshOnly)
    }

    private func run(command: LockCommand) async -> Bool {
        await run(mode: .command(command))
    }

    private func run(mode: SessionMode) async -> Bool {
        guard !isBusy else {
            statusMessage = "Lock command already in progress."
            return false
        }

        #if targetEnvironment(simulator)
        statusMessage = "Simulator mode: lock session simulated as success."
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
        sessionMode = mode
        if case .command(let command) = mode {
            currentCommand = command
            queuedCommand = command
        } else {
            queuedCommand = nil
        }
        statusMessage = "Scanning for lock..."
        resetDiscoveryUI()
        sessionStep = "Scanning"

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.sawInitialStatus = false
            self.waitingForSettle = false
            self.expectedResultSeq = nil
            self.characteristics = [:]
            if case .command(let command) = mode {
                self.queuedCommand = command
                self.currentCommand = command
            } else {
                self.queuedCommand = nil
            }
            self.hasSentCommand = false

            guard let central else {
                finish(success: false, message: "Bluetooth unavailable on this device.")
                return
            }

            if central.state == .poweredOn {
                startScan()
            } else {
                scheduleTimeout(seconds: 5, message: "Waiting for Bluetooth to become ready...")
            }
        }
        #endif
    }

    private func startScan() {
        guard let central else { return }
        isScanning = true
        sessionStep = "Scanning for service"
        statusMessage = "Scanning for lock..."
        central.stopScan()
        central.scanForPeripherals(withServices: [LockUUID.service])
        scheduleTimeout(seconds: Timeout.scan, message: "Lock not found. It may be connected to another phone.")
    }

    private func advertisedUUIDList(from advertisementData: [String: Any]) -> [String] {
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let overflowUUIDs = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        let all = serviceUUIDs + overflowUUIDs
        return Array(Set(all.map(\.uuidString))).sorted()
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
        isScanning = false
        sessionStep = success ? "Completed" : "Failed"
        queuedCommand = nil
        hasSentCommand = false

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
            startScan()
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
        let displayName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        let advertisedUUIDs = advertisedUUIDList(from: advertisementData)

        if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[idx] = DiscoveredDevice(
                id: peripheral.identifier,
                name: displayName,
                rssi: RSSI.intValue,
                isCandidate: true,
                advertisedUUIDs: advertisedUUIDs
            )
        } else {
            discoveredDevices.append(
                DiscoveredDevice(
                    id: peripheral.identifier,
                    name: displayName,
                    rssi: RSSI.intValue,
                    isCandidate: true,
                    advertisedUUIDs: advertisedUUIDs
                )
            )
        }

        discoveredDevices.sort { $0.rssi > $1.rssi }
        if discoveredDevices.count > 10 {
            discoveredDevices = Array(discoveredDevices.prefix(10))
        }

        central.stopScan()
        isScanning = false
        sessionStep = "Connecting"
        self.peripheral = peripheral
        peripheral.delegate = self
        statusMessage = "Connecting to \(displayName)..."
        central.connect(peripheral)
        scheduleTimeout(seconds: Timeout.connect, message: "Could not connect to lock.")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        sessionStep = "Discovering services"
        statusMessage = "Preparing lock..."
        peripheral.discoverServices([LockUUID.service])
        scheduleTimeout(seconds: Timeout.discover, message: "Lock service discovery timed out.")
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(success: false, message: "Failed to connect to lock.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        self.characteristics = [:]

        guard continuation != nil else { return }
        if isBusy {
            let unknownOutcome = hasSentCommand
            finish(success: false, message: unknownOutcome ? "Disconnected before result arrived. Re-run to confirm lock state." : "Disconnected before command was sent.")
        }
    }
}

extension BluetoothLockManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        sessionStep = "Discovering characteristics"
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == LockUUID.service }) else {
            finish(success: false, message: "Lock service unavailable.")
            return
        }

        peripheral.discoverCharacteristics([LockUUID.command, LockUUID.status, LockUUID.info], for: service)
        scheduleTimeout(seconds: Timeout.discover, message: "Lock characteristics timed out.")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            finish(success: false, message: "Could not read lock characteristics.")
            return
        }

        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
        }

        guard let info = characteristics[LockUUID.info], characteristics[LockUUID.command] != nil, characteristics[LockUUID.status] != nil else {
            finish(success: false, message: "Lock firmware is missing required characteristics.")
            return
        }

        peripheral.readValue(for: info)
        sessionStep = "Reading info"
        scheduleTimeout(seconds: Timeout.infoRead, message: "Lock info check timed out.")
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
            sessionStep = "Subscribing to status"
            scheduleTimeout(seconds: Timeout.subscribe, message: "Could not subscribe to lock status.")

        case LockUUID.status:
            guard let lockStatus = LockStatus(value) else {
                finish(success: false, message: "Malformed lock status response.")
                return
            }

            lastKnownStateText = stateLabel(for: lockStatus.state)
            lastCheckedAt = Date()

            if !sawInitialStatus {
                sawInitialStatus = true
                guard let command = characteristics[LockUUID.command] else {
                    finish(success: false, message: "Command characteristic missing.")
                    return
                }

                if queuedCommand == nil {
                    finish(success: true, message: "Status read complete.")
                    return
                }

                expectedResultSeq = lockStatus.resultSeq &+ 1

                statusMessage = "Sending \(currentCommand.verb) command..."
                sessionStep = "Writing command"
                hasSentCommand = true
                peripheral.writeValue(Data([currentCommand.opcode]), for: command, type: .withResponse)
                scheduleTimeout(seconds: Timeout.writeResult, message: "\(currentCommand.verb.capitalized) command timed out.")
                return
            }

            if let expectedResultSeq, lockStatus.resultSeq == expectedResultSeq {
                switch lockStatus.lastResult {
                case .ok:
                    waitingForSettle = true
                    self.expectedResultSeq = nil
                    statusMessage = currentCommand == .unlock ? "Unlocking..." : "Locking..."
                    sessionStep = "Waiting for settle"
                    scheduleTimeout(seconds: Timeout.settle, message: "Lock did not settle in time.")
                case .noChange:
                    finish(success: true, message: currentCommand == .unlock ? "Lock already unlocked." : "Lock already locked.")
                case .busy:
                    finish(success: false, message: "Lock is busy. Please try again.")
                case .unknown:
                    finish(success: false, message: "\(currentCommand.verb.capitalized) failed with unknown result.")
                }
            }

            if waitingForSettle && lockStatus.state.isSettled {
                waitingForSettle = false
                let expectedState: LockState = (currentCommand == .unlock) ? .unlocked : .locked
                if lockStatus.state == expectedState {
                    finish(success: true, message: currentCommand == .unlock ? "Bike unlocked." : "Bike locked.")
                } else {
                    finish(success: false, message: currentCommand == .unlock ? "Lock settled but remained locked." : "Lock settled but remained unlocked.")
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
        sessionStep = "Reading initial status"
        peripheral.readValue(for: characteristic)
        scheduleTimeout(seconds: Timeout.initialStatusRead, message: "Could not read initial lock status.")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            finish(success: false, message: "Lock rejected \(currentCommand.verb) write.")
        } else {
            statusMessage = "\(currentCommand.verb.capitalized) command acknowledged. Waiting for lock status..."
            sessionStep = "Awaiting result"
        }
    }

    private func stateLabel(for state: LockState) -> String {
        switch state {
        case .locked: return "Locked"
        case .unlocking: return "Unlocking"
        case .unlocked: return "Unlocked"
        case .locking: return "Locking"
        case .unknown: return "Unknown"
        }
    }
}

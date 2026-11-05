import Foundation
import CoreBluetooth
import Combine

@MainActor
final class BluetoothLockManager: NSObject, ObservableObject {
    @Published var statusMessage: String = ""
    @Published var isBusy = false

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

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
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
        isBusy = true
        statusMessage = "Scanning for lock..."

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.sawInitialStatus = false
            self.waitingForSettle = false
            self.expectedResultSeq = nil
            self.characteristics = [:]

            guard let central else {
                finish(success: false, message: "Bluetooth unavailable on this device.")
                return
            }

            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: [LockUUID.service])
                scheduleTimeout(seconds: 10, message: "Lock not found. It may be in use by another phone.")
            } else {
                scheduleTimeout(seconds: 5, message: "Bluetooth is off. Turn it on and try again.")
            }
        }
        #endif
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

        if central.state == .poweredOn {
            statusMessage = "Scanning for lock..."
            central.scanForPeripherals(withServices: [LockUUID.service])
            scheduleTimeout(seconds: 10, message: "Lock not found. It may be connected to another phone.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        statusMessage = "Connecting to lock..."
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
        if isBusy {
            finish(success: false, message: "Disconnected before unlock completed.")
        }
    }
}

extension BluetoothLockManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == LockUUID.service }) else {
            finish(success: false, message: "Lock service unavailable.")
            return
        }

        peripheral.discoverCharacteristics([LockUUID.command, LockUUID.status, LockUUID.info], for: service)
        scheduleTimeout(seconds: 5, message: "Lock characteristics timed out.")
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

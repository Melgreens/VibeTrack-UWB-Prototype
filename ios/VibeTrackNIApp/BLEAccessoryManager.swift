import Combine
import CoreBluetooth
import Foundation

/*
 Test on a physical iPhone. The iOS simulator cannot fully test Bluetooth LE
 scanning, connecting, notifications, writes, or Nearby Interaction hardware.

 BLE is only the data channel for Apple's Nearby Interaction accessory flow.
 This manager never treats BLE telemetry as UWB distance or direction.
 */
final class BLEAccessoryManager: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case scanning
        case found
        case connecting
        case connected
        case disconnected
        case bluetoothUnavailable(String)
        case error(String)

        var label: String {
            switch self {
            case .idle:
                return "Idle"
            case .scanning:
                return "Scanning"
            case .found:
                return "Found"
            case .connecting:
                return "Connecting"
            case .connected:
                return "Connected"
            case .disconnected:
                return "Disconnected"
            case .bluetoothUnavailable:
                return "Bluetooth unavailable"
            case .error:
                return "Error"
            }
        }

        var detail: String? {
            switch self {
            case .bluetoothUnavailable(let message), .error(let message):
                return message
            default:
                return nil
            }
        }
    }

    struct Accessory: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
        fileprivate let peripheral: CBPeripheral

        static func == (lhs: Accessory, rhs: Accessory) -> Bool {
            lhs.id == rhs.id
        }
    }

    enum UUIDs {
        static let service = CBUUID(string: "7E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        static let accessoryConfiguration = CBUUID(string: "7E400011-B5A3-F393-E0A9-E50E24DCCA9E")
        static let phoneConfiguration = CBUUID(string: "7E400012-B5A3-F393-E0A9-E50E24DCCA9E")
        static let statusDebug = CBUUID(string: "7E400013-B5A3-F393-E0A9-E50E24DCCA9E")
    }

    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var discoveredAccessories: [Accessory] = []
    @Published private(set) var selectedAccessoryID: UUID?
    @Published private(set) var accessoryConfigurationData: Data?
    @Published private(set) var statusMessage = "Accessory disconnected"
    @Published private(set) var logs: [String] = []
    @Published private(set) var lastAccessoryPacketDate: Date?

    private let targetDeviceName = "VibeTrack-UWB"

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var accessoryConfigurationCharacteristic: CBCharacteristic?
    private var phoneConfigurationCharacteristic: CBCharacteristic?
    private var statusDebugCharacteristic: CBCharacteristic?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        appendLog("BLE manager created")
    }

    var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    var connectedPeripheralIdentifier: UUID? {
        connectedPeripheral?.identifier
    }

    var canStartNearbyInteraction: Bool {
        isConnected && accessoryConfigurationData != nil
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            let message = "Bluetooth is not powered on. Current state: \(centralManager.state.rawValue)."
            connectionState = .bluetoothUnavailable(message)
            statusMessage = message
            appendLog(message)
            return
        }

        accessoryConfigurationData = nil
        discoveredAccessories.removeAll()
        selectedAccessoryID = nil
        connectionState = .scanning
        statusMessage = "Scanning for \(targetDeviceName)"
        appendLog(statusMessage)

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionState {
            connectionState = discoveredAccessories.isEmpty ? .disconnected : .found
        }
        appendLog("Stopped scanning")
    }

    func connect(to accessory: Accessory) {
        stopScanning()
        selectedAccessoryID = accessory.id
        accessoryConfigurationData = nil
        accessoryConfigurationCharacteristic = nil
        phoneConfigurationCharacteristic = nil
        statusDebugCharacteristic = nil
        connectedPeripheral = accessory.peripheral
        connectedPeripheral?.delegate = self
        connectionState = .connecting
        statusMessage = "Connecting to \(accessory.name)"
        appendLog(statusMessage)
        centralManager.connect(accessory.peripheral, options: nil)
    }

    func disconnect() {
        guard let connectedPeripheral else {
            connectionState = .disconnected
            statusMessage = "Accessory disconnected"
            return
        }

        appendLog("Disconnecting from \(connectedPeripheral.name ?? targetDeviceName)")
        centralManager.cancelPeripheralConnection(connectedPeripheral)
    }

    func requestAccessoryConfiguration() {
        guard isConnected else {
            let message = "Accessory disconnected. Connect over BLE before starting Nearby Interaction."
            statusMessage = message
            appendLog(message)
            return
        }

        guard let connectedPeripheral, let statusDebugCharacteristic else {
            let message = "Status/debug characteristic missing; cannot request accessory configuration."
            statusMessage = message
            appendLog(message)
            return
        }

        writeUTF8("REQUEST_ACCESSORY_CONFIG", to: statusDebugCharacteristic, on: connectedPeripheral)
    }

    func requestStatus() {
        guard let connectedPeripheral, let statusDebugCharacteristic else {
            appendLog("Cannot request status; status/debug characteristic unavailable")
            return
        }

        writeUTF8("STATUS", to: statusDebugCharacteristic, on: connectedPeripheral)
    }

    func writePhoneConfigurationData(_ data: Data) {
        guard let connectedPeripheral, let phoneConfigurationCharacteristic else {
            let message = "iPhone configuration characteristic missing; cannot send NI shareable config."
            statusMessage = message
            appendLog(message)
            return
        }

        connectedPeripheral.writeValue(data, for: phoneConfigurationCharacteristic, type: .withResponse)
        appendLog("Sent iPhone NI shareable configuration data (\(data.count) bytes)")
    }

    private func writeUTF8(_ text: String, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        guard let data = text.data(using: .utf8) else {
            appendLog("Unable to encode BLE command: \(text)")
            return
        }

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        appendLog("Sent BLE command: \(text)")
    }

    private func handleAccessoryConfiguration(_ data: Data) {
        guard !data.isEmpty else {
            let message = "Accessory configuration missing. Real NI requires Qorvo/Apple-compatible config bytes."
            statusMessage = message
            appendLog(message)
            return
        }

        accessoryConfigurationData = data
        lastAccessoryPacketDate = Date()
        statusMessage = "Accessory configuration received"
        appendLog("Received accessory NI configuration data (\(data.count) bytes)")
    }

    private func handleStatusData(_ data: Data) {
        lastAccessoryPacketDate = Date()
        let text = String(data: data, encoding: .utf8) ?? "<\(data.count) binary bytes>"
        statusMessage = text
        appendLog("Accessory status: \(text)")
    }

    private func resetConnectedState(message: String) {
        accessoryConfigurationData = nil
        accessoryConfigurationCharacteristic = nil
        phoneConfigurationCharacteristic = nil
        statusDebugCharacteristic = nil
        connectedPeripheral = nil
        connectionState = .disconnected
        statusMessage = message
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.logFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 250 {
            logs.removeFirst(logs.count - 250)
        }
    }

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension BLEAccessoryManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionState = .disconnected
            statusMessage = "Bluetooth ready"
            appendLog(statusMessage)
        case .poweredOff:
            let message = "Bluetooth unavailable: powered off."
            connectionState = .bluetoothUnavailable(message)
            statusMessage = message
            appendLog(message)
        case .unauthorized:
            let message = "Bluetooth unavailable: permission not authorized."
            connectionState = .bluetoothUnavailable(message)
            statusMessage = message
            appendLog(message)
        case .unsupported:
            let message = "Bluetooth unavailable: this device does not support BLE."
            connectionState = .bluetoothUnavailable(message)
            statusMessage = message
            appendLog(message)
        case .resetting:
            appendLog("Bluetooth resetting")
        case .unknown:
            appendLog("Bluetooth state unknown")
        @unknown default:
            appendLog("Bluetooth state unknown default")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unnamed BLE Device"
        guard name == targetDeviceName else { return }

        let accessory = Accessory(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )

        if let index = discoveredAccessories.firstIndex(where: { $0.id == accessory.id }) {
            discoveredAccessories[index] = accessory
        } else {
            discoveredAccessories.append(accessory)
            appendLog("Found \(name), RSSI \(RSSI)")
        }

        if case .scanning = connectionState {
            connectionState = .found
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("Connected to \(peripheral.name ?? targetDeviceName); discovering NI service")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([UUIDs.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let message = error?.localizedDescription ?? "Failed to connect to accessory."
        connectionState = .error(message)
        statusMessage = message
        appendLog(message)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let message = "Accessory disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")"
        resetConnectedState(message: message)
        appendLog(message)
    }
}

extension BLEAccessoryManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let message = "Service discovery failed: \(error.localizedDescription)"
            connectionState = .error(message)
            statusMessage = message
            appendLog(message)
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == UUIDs.service }) else {
            let message = "Nearby Interaction BLE service was not found."
            connectionState = .error(message)
            statusMessage = message
            appendLog(message)
            return
        }

        appendLog("Discovered NI BLE service")
        peripheral.discoverCharacteristics(
            [UUIDs.accessoryConfiguration, UUIDs.phoneConfiguration, UUIDs.statusDebug],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            let message = "Characteristic discovery failed: \(error.localizedDescription)"
            connectionState = .error(message)
            statusMessage = message
            appendLog(message)
            return
        }

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case UUIDs.accessoryConfiguration:
                accessoryConfigurationCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
                appendLog("Accessory configuration characteristic ready")
            case UUIDs.phoneConfiguration:
                phoneConfigurationCharacteristic = characteristic
                appendLog("iPhone configuration write characteristic ready")
            case UUIDs.statusDebug:
                statusDebugCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
                appendLog("Status/debug characteristic ready")
            default:
                break
            }
        }

        guard accessoryConfigurationCharacteristic != nil,
              phoneConfigurationCharacteristic != nil,
              statusDebugCharacteristic != nil else {
            let message = "Required NI BLE characteristics were not found."
            connectionState = .error(message)
            statusMessage = message
            appendLog(message)
            return
        }

        connectionState = .connected
        statusMessage = "BLE connected. Waiting for accessory NI configuration."
        appendLog(statusMessage)
        requestStatus()
        requestAccessoryConfiguration()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let message = "BLE value update failed: \(error.localizedDescription)"
            statusMessage = message
            appendLog(message)
            return
        }

        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case UUIDs.accessoryConfiguration:
            handleAccessoryConfiguration(data)
        case UUIDs.statusDebug:
            handleStatusData(data)
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let message = "BLE write failed: \(error.localizedDescription)"
            statusMessage = message
            appendLog(message)
        } else {
            appendLog("BLE write acknowledged for \(characteristic.uuid.uuidString)")
        }
    }
}

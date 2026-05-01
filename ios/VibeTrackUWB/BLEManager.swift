import Combine
import CoreBluetooth
import Foundation

/*
 Test on a real iPhone. The iOS simulator cannot fully test Bluetooth hardware
 scanning, connection, notifications, or writes to the ESP32 peripheral.

 This manager implements the practical prototype layer only:
 ESP32/DWM3000 -> BLE GATT telemetry -> SwiftUI UI.
 It does not use the iPhone UWB chip and does not implement Apple Nearby Interaction.
 */
final class BLEManager: NSObject, ObservableObject {
    enum ConnectionState: String {
        case scanning
        case found
        case connecting
        case connected
        case disconnected
        case error
        case bluetoothUnavailable

        var displayText: String {
            switch self {
            case .scanning:
                return "scanning"
            case .found:
                return "found"
            case .connecting:
                return "connecting"
            case .connected:
                return "connected"
            case .disconnected:
                return "disconnected"
            case .error:
                return "error"
            case .bluetoothUnavailable:
                return "bluetooth unavailable"
            }
        }
    }

    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        fileprivate let peripheral: CBPeripheral
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var telemetry: UWBTelemetry?
    @Published private(set) var rawJSON: String = ""
    @Published private(set) var logs: [String] = []
    @Published private(set) var lastPacketDate: Date?
    @Published private(set) var errorMessage: String?

    private let targetDeviceName = "VibeTrack-UWB"
    private let serviceUUID = CBUUID(string: "7E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let telemetryUUID = CBUUID(string: "7E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let commandUUID = CBUUID(string: "7E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var telemetryCharacteristic: CBCharacteristic?
    private var commandCharacteristic: CBCharacteristic?
    private var notificationBuffer = Data()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        appendLog("BLE manager created")
    }

    var canSendCommands: Bool {
        connectionState == .connected && commandCharacteristic != nil && connectedPeripheral != nil
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionState = .bluetoothUnavailable
            errorMessage = "Bluetooth is not powered on."
            appendLog("Cannot scan: Bluetooth state is \(centralManager.state.rawValue)")
            return
        }

        errorMessage = nil
        discoveredDevices.removeAll()
        connectionState = .scanning
        appendLog("Scanning for \(targetDeviceName)")

        // Scanning without a service filter lets the app find ESP32 advertisements
        // even if a board/core version does not include the custom service UUID in
        // the primary advertising packet.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = discoveredDevices.isEmpty ? .disconnected : .found
        }
        appendLog("Stopped scanning")
    }

    func connect(to device: DiscoveredDevice) {
        stopScanning()
        connectionState = .connecting
        errorMessage = nil
        connectedPeripheral = device.peripheral
        connectedPeripheral?.delegate = self
        appendLog("Connecting to \(device.name)")
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else {
            connectionState = .disconnected
            return
        }

        appendLog("Disconnecting from \(peripheral.name ?? targetDeviceName)")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func sendCommand(_ command: VibeTrackCommand) {
        guard let peripheral = connectedPeripheral,
              let commandCharacteristic else {
            appendLog("Cannot send \(command.rawValue): command characteristic unavailable")
            errorMessage = "Command characteristic is unavailable."
            return
        }

        guard let data = command.rawValue.data(using: .utf8) else {
            appendLog("Cannot encode command \(command.rawValue)")
            return
        }

        let writeType: CBCharacteristicWriteType = commandCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: commandCharacteristic, type: writeType)
        appendLog("Sent command \(command.rawValue)")
    }

    private func handleNotificationData(_ data: Data) {
        notificationBuffer.append(data)

        while let newlineRange = notificationBuffer.firstRange(of: Data([0x0A])) {
            let packet = notificationBuffer.subdata(in: 0..<newlineRange.lowerBound)
            notificationBuffer.removeSubrange(0..<newlineRange.upperBound)
            parseTelemetryPacket(packet)
        }

        if notificationBuffer.count > 4096 {
            notificationBuffer.removeAll()
            appendLog("Cleared oversized telemetry buffer")
        }
    }

    private func parseTelemetryPacket(_ packet: Data) {
        guard !packet.isEmpty else { return }

        guard let json = String(data: packet, encoding: .utf8) else {
            appendLog("Received telemetry packet that was not UTF-8")
            return
        }

        rawJSON = json
        lastPacketDate = Date()

        do {
            telemetry = try JSONDecoder().decode(UWBTelemetry.self, from: packet)
            appendLog("Telemetry update received")
        } catch {
            errorMessage = "Telemetry decode failed: \(error.localizedDescription)"
            appendLog(errorMessage ?? "Telemetry decode failed")
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.logFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionState = .disconnected
            appendLog("Bluetooth powered on")
        case .poweredOff:
            connectionState = .bluetoothUnavailable
            errorMessage = "Bluetooth is powered off."
            appendLog("Bluetooth powered off")
        case .unauthorized:
            connectionState = .error
            errorMessage = "Bluetooth permission is not authorized."
            appendLog("Bluetooth unauthorized")
        case .unsupported:
            connectionState = .bluetoothUnavailable
            errorMessage = "This device does not support Bluetooth LE."
            appendLog("Bluetooth unsupported")
        case .resetting:
            appendLog("Bluetooth resetting")
        case .unknown:
            appendLog("Bluetooth state unknown")
        @unknown default:
            appendLog("Unknown Bluetooth state")
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

        guard name == targetDeviceName else {
            return
        }

        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )

        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
            appendLog("Found \(name) RSSI \(RSSI)")
        }

        if connectionState == .scanning {
            connectionState = .found
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("Connected to \(peripheral.name ?? targetDeviceName); discovering service")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .error
        errorMessage = error?.localizedDescription ?? "Failed to connect."
        appendLog("Failed to connect: \(errorMessage ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        telemetryCharacteristic = nil
        commandCharacteristic = nil
        connectedPeripheral = nil
        appendLog("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionState = .error
            errorMessage = error.localizedDescription
            appendLog("Service discovery failed: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            connectionState = .error
            errorMessage = "VibeTrack service was not found."
            appendLog("No services found")
            return
        }

        for service in services where service.uuid == serviceUUID {
            appendLog("Discovered VibeTrack service")
            peripheral.discoverCharacteristics([telemetryUUID, commandUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionState = .error
            errorMessage = error.localizedDescription
            appendLog("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            connectionState = .error
            errorMessage = "No characteristics found on VibeTrack service."
            appendLog("No characteristics found")
            return
        }

        for characteristic in characteristics {
            if characteristic.uuid == telemetryUUID {
                telemetryCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                appendLog("Subscribed to telemetry characteristic")
            }

            if characteristic.uuid == commandUUID {
                commandCharacteristic = characteristic
                appendLog("Command characteristic ready")
            }
        }

        if telemetryCharacteristic == nil || commandCharacteristic == nil {
            connectionState = .error
            errorMessage = "Required BLE characteristics were not found."
            appendLog("Required characteristics missing")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            connectionState = .error
            errorMessage = error.localizedDescription
            appendLog("Notification subscription failed: \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == telemetryUUID, characteristic.isNotifying else {
            return
        }

        connectionState = .connected
        appendLog("Telemetry notifications active")
        sendCommand(.requestStatus)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            errorMessage = error.localizedDescription
            appendLog("Telemetry read failed: \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == telemetryUUID,
              let data = characteristic.value else {
            return
        }

        handleNotificationData(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            errorMessage = error.localizedDescription
            appendLog("Command write failed: \(error.localizedDescription)")
        } else {
            appendLog("Command write acknowledged")
        }
    }
}

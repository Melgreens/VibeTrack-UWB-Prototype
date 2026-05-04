import Combine
import Foundation
import NearbyInteraction
import simd

/*
 Nearby Interaction is the only source of UWB distance and direction in this app.
 The app must receive real accessory configuration data over BLE before this
 manager can create NINearbyAccessoryConfiguration and run NISession.
 */
final class NearbyInteractionManager: NSObject, ObservableObject {
    enum SessionState: Equatable {
        case idle
        case unsupported(String)
        case waitingForAccessoryConfiguration
        case ready
        case running
        case distanceOnly
        case directionUnavailable
        case invalidated(String)
        case error(String)

        var label: String {
            switch self {
            case .idle:
                return "Idle"
            case .unsupported:
                return "Unsupported"
            case .waitingForAccessoryConfiguration:
                return "Waiting for accessory config"
            case .ready:
                return "Ready"
            case .running:
                return "Running"
            case .distanceOnly:
                return "Distance only"
            case .directionUnavailable:
                return "Direction unavailable"
            case .invalidated:
                return "Invalidated"
            case .error:
                return "Error"
            }
        }

        var detail: String? {
            switch self {
            case .unsupported(let message), .invalidated(let message), .error(let message):
                return message
            case .waitingForAccessoryConfiguration:
                return "Accessory configuration missing"
            case .distanceOnly:
                return "Direction unavailable, distance only."
            case .directionUnavailable:
                return "Move iPhone around or improve line of sight."
            default:
                return nil
            }
        }
    }

    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var distanceMeters: Float?
    @Published private(set) var direction: simd_float3?
    @Published private(set) var arrowDegrees: Double?
    @Published private(set) var lastUpdateDate: Date?
    @Published private(set) var logs: [String] = []

    private var session: NISession?
    private var accessoryDiscoveryToken: NIDiscoveryToken?
    private var sendShareableConfiguration: ((Data) -> Void)?

    override init() {
        super.init()
        appendLog("Nearby Interaction manager created")
        if !Self.supportsNearbyInteraction {
            sessionState = .unsupported("Nearby Interaction precise distance is not supported on this device.")
        }
    }

    static var supportsNearbyInteraction: Bool {
        if #available(iOS 16.0, *) {
            return NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
        }
        return NISession.isSupported
    }

    static var supportsDirection: Bool {
        if #available(iOS 16.0, *) {
            return NISession.deviceCapabilities.supportsDirectionMeasurement
        }
        return NISession.isSupported
    }

    func start(
        accessoryConfigurationData: Data?,
        sendShareableConfiguration: @escaping (Data) -> Void
    ) {
        guard Self.supportsNearbyInteraction else {
            let message = "Nearby Interaction unsupported on this device."
            sessionState = .unsupported(message)
            appendLog(message)
            return
        }

        guard let accessoryConfigurationData, !accessoryConfigurationData.isEmpty else {
            let message = "Accessory configuration missing. The ESP32 must provide real Qorvo/Apple NI config bytes over BLE."
            sessionState = .waitingForAccessoryConfiguration
            appendLog(message)
            return
        }

        do {
            let configuration = try NINearbyAccessoryConfiguration(data: accessoryConfigurationData)
            let session = NISession()
            session.delegate = self
            self.session = session
            self.accessoryDiscoveryToken = configuration.accessoryDiscoveryToken
            self.sendShareableConfiguration = sendShareableConfiguration

            sessionState = .ready
            appendLog("Running NISession with accessory configuration")
            session.run(configuration)
            sessionState = .running
        } catch {
            let message = "Failed to create NINearbyAccessoryConfiguration: \(error.localizedDescription)"
            sessionState = .error(message)
            appendLog(message)
        }
    }

    func stop() {
        session?.invalidate()
        session = nil
        accessoryDiscoveryToken = nil
        sendShareableConfiguration = nil
        distanceMeters = nil
        direction = nil
        arrowDegrees = nil
        lastUpdateDate = nil
        sessionState = .idle
        appendLog("Nearby Interaction session stopped")
    }

    private func update(from nearbyObject: NINearbyObject) {
        distanceMeters = nearbyObject.distance
        direction = nearbyObject.direction
        lastUpdateDate = Date()

        if let direction = nearbyObject.direction {
            let radians = atan2(Double(direction.x), Double(-direction.z))
            arrowDegrees = radians * 180.0 / Double.pi
            sessionState = .running
            appendLog("NI update: distance=\(format(nearbyObject.distance)) m, direction vector available")
        } else if nearbyObject.distance != nil {
            arrowDegrees = nil
            sessionState = .distanceOnly
            appendLog("NI update: distance=\(format(nearbyObject.distance)) m, direction unavailable")
        } else {
            arrowDegrees = nil
            sessionState = .directionUnavailable
            appendLog("NI update: no UWB lock")
        }
    }

    private func format(_ value: Float?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.2f", value)
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

extension NearbyInteractionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let matchingObject: NINearbyObject?
        if let accessoryDiscoveryToken {
            matchingObject = nearbyObjects.first(where: { $0.discoveryToken == accessoryDiscoveryToken })
        } else {
            matchingObject = nearbyObjects.first
        }

        guard let matchingObject else {
            appendLog("NI update did not include the connected accessory token")
            return
        }

        update(from: matchingObject)
    }

    func session(
        _ session: NISession,
        didGenerateShareableConfigurationData shareableConfigurationData: Data,
        for object: NINearbyObject
    ) {
        appendLog("Generated iPhone shareable NI configuration data (\(shareableConfigurationData.count) bytes)")
        sendShareableConfiguration?(shareableConfigurationData)
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        distanceMeters = nil
        direction = nil
        arrowDegrees = nil
        let message = "Nearby object removed: \(String(describing: reason))"
        sessionState = .directionUnavailable
        appendLog(message)
    }

    func sessionWasSuspended(_ session: NISession) {
        appendLog("NISession suspended")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        appendLog("NISession suspension ended")
        if let configuration = session.configuration {
            appendLog("Restarting NISession after suspension")
            session.run(configuration)
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        let message = "NISession invalidated: \(error.localizedDescription)"
        self.session = nil
        accessoryDiscoveryToken = nil
        sendShareableConfiguration = nil
        distanceMeters = nil
        direction = nil
        arrowDegrees = nil
        sessionState = .invalidated(message)
        appendLog(message)
    }
}

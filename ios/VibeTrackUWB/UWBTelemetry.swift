import Foundation

struct UWBTelemetry: Codable, Equatable {
    let deviceName: String
    let uwbDetected: Bool
    let deviceId: String
    let mode: String
    let distanceMeters: Double
    let distanceFeet: Double
    let bearingDegrees: Double
    let signalQuality: String
    let lastUpdateMs: UInt64
    let error: String?

    static let placeholder = UWBTelemetry(
        deviceName: "VibeTech 3 UWB",
        uwbDetected: false,
        deviceId: "0x00000000",
        mode: "waiting",
        distanceMeters: 0,
        distanceFeet: 0,
        bearingDegrees: 0,
        signalQuality: "searching",
        lastUpdateMs: 0,
        error: nil
    )
}

enum VibeTrackCommand: String, CaseIterable {
    case startSimulation = "START_SIM"
    case stopSimulation = "STOP_SIM"
    case resetUWB = "RESET_UWB"
    case requestStatus = "STATUS"

    var title: String {
        switch self {
        case .startSimulation:
            return "Start Simulation"
        case .stopSimulation:
            return "Stop Simulation"
        case .resetUWB:
            return "Reset UWB"
        case .requestStatus:
            return "Request Status"
        }
    }

    var systemImage: String {
        switch self {
        case .startSimulation:
            return "play.fill"
        case .stopSimulation:
            return "stop.fill"
        case .resetUWB:
            return "arrow.clockwise"
        case .requestStatus:
            return "waveform.path.ecg"
        }
    }
}

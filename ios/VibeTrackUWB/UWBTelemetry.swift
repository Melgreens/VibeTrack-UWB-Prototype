import Foundation

struct UWBTelemetry: Codable, Equatable {
    let deviceName: String
    let uwbDetected: Bool
    let deviceId: String
    let mode: String
    let distanceMeters: Double?
    let distanceFeet: Double?
    let bearingDegrees: Double?
    let signalQuality: String
    let lastUpdateMs: UInt64
    let error: String?

    static let placeholder = UWBTelemetry(
        deviceName: "VibeTech 3 UWB",
        uwbDetected: false,
        deviceId: "0x00000000",
        mode: "waiting",
        distanceMeters: nil,
        distanceFeet: nil,
        bearingDegrees: nil,
        signalQuality: "searching",
        lastUpdateMs: 0,
        error: nil
    )
}

enum VibeTrackCommand: String, CaseIterable {
    case resetUWB = "RESET_UWB"
    case requestStatus = "STATUS"

    var title: String {
        switch self {
        case .resetUWB:
            return "Reset UWB"
        case .requestStatus:
            return "Request Status"
        }
    }

    var systemImage: String {
        switch self {
        case .resetUWB:
            return "arrow.clockwise"
        case .requestStatus:
            return "waveform.path.ecg"
        }
    }
}

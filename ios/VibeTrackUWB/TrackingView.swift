import Foundation
import SwiftUI

struct TrackingView: View {
    @EnvironmentObject private var bleManager: BLEManager

    private var telemetry: UWBTelemetry {
        bleManager.telemetry ?? .placeholder
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    distancePanel
                    directionPanel
                    statusPanel
                    commandGrid
                }
                .padding()
            }
            .navigationTitle("Tracking")
            .background(Color(.systemBackground))
        }
    }

    private var distancePanel: some View {
        VStack(spacing: 8) {
            Text(distanceFeetText)
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(distanceMetersText)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: telemetry.distanceFeet ?? -1)
    }

    private var directionPanel: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 2)
                    .frame(width: 220, height: 220)

                ForEach(0..<12) { tick in
                    Capsule()
                        .fill(tick % 3 == 0 ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.35))
                        .frame(width: 3, height: tick % 3 == 0 ? 18 : 10)
                        .offset(y: -101)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }

                Image(systemName: "location.north.fill")
                    .font(.system(size: 86, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .shadow(color: .cyan.opacity(0.4), radius: 12)
                    .rotationEffect(.degrees(telemetry.bearingDegrees ?? 0))
                    .opacity(telemetry.bearingDegrees == nil ? 0.45 : 1.0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.76), value: telemetry.bearingDegrees ?? 0)
            }
            .frame(maxWidth: .infinity)

            Text(bearingText)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(statusMessage)
                    .font(.headline)

                Text("Mode: \(telemetry.mode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = telemetry.error, !error.isEmpty {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var commandGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(VibeTrackCommand.allCases, id: \.rawValue) { command in
                Button {
                    bleManager.sendCommand(command)
                } label: {
                    Label(command.title, systemImage: command.systemImage)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.bordered)
                .disabled(!bleManager.canSendCommands)
            }
        }
    }

    private var distanceFeetText: String {
        guard let distanceFeet = telemetry.distanceFeet else {
            return "-- ft"
        }

        return String(format: "%.2f ft", distanceFeet)
    }

    private var distanceMetersText: String {
        guard let distanceMeters = telemetry.distanceMeters else {
            return "-- meters"
        }

        return String(format: "%.2f meters", distanceMeters)
    }

    private var bearingText: String {
        guard let bearingDegrees = telemetry.bearingDegrees else {
            return "No iPhone UWB bearing"
        }

        return String(format: "%.0f degrees", bearingDegrees)
    }

    private var statusMessage: String {
        if telemetry.mode == "uwb_error" {
            if let error = telemetry.error, !error.isEmpty {
                return error
            }

            return "UWB ranging error"
        }

        if !telemetry.uwbDetected {
            return "DWM3000 not detected"
        }

        if let distanceFeet = telemetry.distanceFeet, distanceFeet > 0, distanceFeet < 2 {
            return "Very close"
        }

        if telemetry.signalQuality.lowercased().contains("poor") {
            return "Move around to improve signal"
        }

        if telemetry.signalQuality.lowercased().contains("search") || telemetry.mode == "waiting" {
            return "Searching for UWB device"
        }

        return "Signal found"
    }

    private var statusIcon: String {
        if !telemetry.uwbDetected || telemetry.mode == "uwb_error" {
            return "exclamationmark.triangle"
        }

        if let distanceFeet = telemetry.distanceFeet, distanceFeet > 0, distanceFeet < 2 {
            return "scope"
        }

        return "dot.radiowaves.left.and.right"
    }

    private var statusColor: Color {
        if !telemetry.uwbDetected || telemetry.mode == "uwb_error" {
            return .red
        }

        if let distanceFeet = telemetry.distanceFeet, distanceFeet > 0, distanceFeet < 2 {
            return .green
        }

        return .cyan
    }
}

struct TrackingView_Previews: PreviewProvider {
    static var previews: some View {
        TrackingView()
            .environmentObject(BLEManager())
    }
}

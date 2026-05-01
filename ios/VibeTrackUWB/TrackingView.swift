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
            Text("\(telemetry.distanceFeet, specifier: "%.2f") ft")
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("\(telemetry.distanceMeters, specifier: "%.2f") meters")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: telemetry.distanceFeet)
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
                    .rotationEffect(.degrees(telemetry.bearingDegrees))
                    .animation(.spring(response: 0.45, dampingFraction: 0.76), value: telemetry.bearingDegrees)
            }
            .frame(maxWidth: .infinity)

            Text("\(telemetry.bearingDegrees, specifier: "%.0f") degrees")
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

    private var statusMessage: String {
        if !telemetry.uwbDetected {
            return "DWM3000 not detected"
        }

        if telemetry.signalQuality.lowercased().contains("simulated") {
            return "Using simulated UWB telemetry"
        }

        if telemetry.distanceFeet > 0, telemetry.distanceFeet < 2 {
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
        if !telemetry.uwbDetected {
            return "exclamationmark.triangle"
        }

        if telemetry.signalQuality.lowercased().contains("simulated") {
            return "sparkles"
        }

        if telemetry.distanceFeet > 0, telemetry.distanceFeet < 2 {
            return "scope"
        }

        return "dot.radiowaves.left.and.right"
    }

    private var statusColor: Color {
        if !telemetry.uwbDetected {
            return .red
        }

        if telemetry.signalQuality.lowercased().contains("simulated") {
            return .cyan
        }

        if telemetry.distanceFeet > 0, telemetry.distanceFeet < 2 {
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

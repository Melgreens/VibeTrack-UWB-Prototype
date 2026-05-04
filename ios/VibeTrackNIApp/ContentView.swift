import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLEAccessoryManager()
    @StateObject private var nearbyManager = NearbyInteractionManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    trackerPanel
                    statePanel
                    controlsPanel
                    discoveredAccessoriesPanel
                    debugPanel
                }
                .padding()
            }
            .navigationTitle("VibeTrack NI")
            .background(Color(.systemBackground))
            .onChange(of: bleManager.connectionState) { state in
                if case .disconnected = state {
                    nearbyManager.stop()
                }
            }
        }
        .tint(.cyan)
    }

    private var trackerPanel: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(Color.cyan.opacity(0.28), lineWidth: 2)
                    .frame(width: 248, height: 248)

                ForEach(0..<24) { index in
                    Capsule()
                        .fill(index % 6 == 0 ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.25))
                        .frame(width: 3, height: index % 6 == 0 ? 18 : 9)
                        .offset(y: -116)
                        .rotationEffect(.degrees(Double(index) * 15.0))
                }

                Image(systemName: "location.north.fill")
                    .font(.system(size: 104, weight: .semibold))
                    .foregroundStyle(nearbyManager.arrowDegrees == nil ? Color.gray : Color.cyan)
                    .shadow(color: nearbyManager.arrowDegrees == nil ? .clear : .cyan.opacity(0.35), radius: 18)
                    .rotationEffect(.degrees(nearbyManager.arrowDegrees ?? 0))
                    .opacity(nearbyManager.arrowDegrees == nil ? 0.38 : 1)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: nearbyManager.arrowDegrees ?? 0)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text(distanceFeetText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)

                Text(distanceMetersText)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(trackingStatusText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(statusColor)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: trackingStatusText)
        }
        .panelStyle()
    }

    private var statePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State")
                .font(.headline)

            stateRow("BLE", bleManager.connectionState.label, bleManager.connectionState.detail)
            stateRow("Nearby Interaction", nearbyManager.sessionState.label, nearbyManager.sessionState.detail)
            stateRow("Accessory", bleManager.statusMessage, nil)
        }
        .panelStyle()
    }

    private var controlsPanel: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button {
                bleManager.startScanning()
            } label: {
                Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                    .controlLabel()
            }

            Button {
                if bleManager.isConnected {
                    bleManager.disconnect()
                } else if let accessory = bleManager.discoveredAccessories.first {
                    bleManager.connect(to: accessory)
                }
            } label: {
                Label(bleManager.isConnected ? "Disconnect" : "Connect", systemImage: bleManager.isConnected ? "xmark.circle" : "link")
                    .controlLabel()
            }
            .disabled(!bleManager.isConnected && bleManager.discoveredAccessories.isEmpty)

            Button {
                bleManager.requestAccessoryConfiguration()
                nearbyManager.start(
                    accessoryConfigurationData: bleManager.accessoryConfigurationData,
                    sendShareableConfiguration: bleManager.writePhoneConfigurationData
                )
            } label: {
                Label("Start Nearby Interaction", systemImage: "location.viewfinder")
                    .controlLabel()
            }
            .disabled(!bleManager.isConnected)

            Button {
                nearbyManager.stop()
            } label: {
                Label("Stop Session", systemImage: "stop.circle")
                    .controlLabel()
            }
        }
        .buttonStyle(.bordered)
    }

    private var discoveredAccessoriesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accessories")
                    .font(.headline)
                Spacer()
                Text("\(bleManager.discoveredAccessories.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if bleManager.discoveredAccessories.isEmpty {
                Text("No VibeTrack-UWB accessories found.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bleManager.discoveredAccessories) { accessory in
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title3)
                            .foregroundStyle(.cyan)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(accessory.name)
                                .font(.body.weight(.semibold))
                            Text("RSSI \(accessory.rssi)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Connect") {
                            bleManager.connect(to: accessory)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(bleManager.isConnected)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .panelStyle()
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Debug Log")
                .font(.headline)

            debugSection("BLE", logs: bleManager.logs)
            debugSection("Nearby Interaction", logs: nearbyManager.logs)
        }
        .panelStyle()
    }

    private func debugSection(_ title: String, logs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if logs.isEmpty {
                Text("No logs yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(logs.suffix(16).enumerated()), id: \.offset) { _, log in
                    Text(log)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func stateRow(_ title: String, _ value: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var distanceMetersText: String {
        guard let meters = nearbyManager.distanceMeters else {
            return "No UWB lock"
        }
        return String(format: "%.2f meters", meters)
    }

    private var distanceFeetText: String {
        guard let meters = nearbyManager.distanceMeters else {
            return "-- ft"
        }
        return String(format: "%.2f ft", meters * 3.28084)
    }

    private var trackingStatusText: String {
        switch nearbyManager.sessionState {
        case .unsupported(let message):
            return message
        case .waitingForAccessoryConfiguration:
            return "Accessory configuration missing"
        case .distanceOnly:
            return "Direction unavailable, distance only."
        case .directionUnavailable:
            return "Move iPhone around"
        case .running:
            if nearbyManager.arrowDegrees != nil {
                return "Signal found"
            }
            return "Move iPhone around"
        case .invalidated(let message), .error(let message):
            return message
        case .ready:
            return "Starting Nearby Interaction"
        case .idle:
            if !bleManager.isConnected {
                return "Accessory disconnected"
            }
            return "Ready for Nearby Interaction"
        }
    }

    private var statusColor: Color {
        switch nearbyManager.sessionState {
        case .running, .distanceOnly:
            return .green
        case .waitingForAccessoryConfiguration, .directionUnavailable, .ready:
            return .orange
        case .unsupported, .invalidated, .error:
            return .red
        case .idle:
            return bleManager.isConnected ? .secondary : .red
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func controlLabel() -> some View {
        font(.callout.weight(.semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, minHeight: 50)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

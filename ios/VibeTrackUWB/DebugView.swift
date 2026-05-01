import SwiftUI

struct DebugView: View {
    @EnvironmentObject private var bleManager: BLEManager

    private var telemetry: UWBTelemetry? {
        bleManager.telemetry
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    packetSummary
                    rawJSONPanel
                    parsedFieldsPanel
                    logsPanel
                }
                .padding()
            }
            .navigationTitle("Debug")
            .background(Color(.systemBackground))
        }
    }

    private var packetSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Packet")
                .font(.headline)

            Text(lastPacketText)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var rawJSONPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw JSON")
                .font(.headline)

            Text(bleManager.rawJSON.isEmpty ? "No telemetry received yet" : bleManager.rawJSON)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelStyle()
    }

    private var parsedFieldsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parsed Telemetry")
                .font(.headline)

            debugRow("deviceName", telemetry?.deviceName ?? "-")
            debugRow("uwbDetected", telemetry.map { String($0.uwbDetected) } ?? "-")
            debugRow("deviceId", telemetry?.deviceId ?? "-")
            debugRow("mode", telemetry?.mode ?? "-")
            debugRow("distanceMeters", telemetry.map { String(format: "%.2f", $0.distanceMeters) } ?? "-")
            debugRow("distanceFeet", telemetry.map { String(format: "%.2f", $0.distanceFeet) } ?? "-")
            debugRow("bearingDegrees", telemetry.map { String(format: "%.1f", $0.bearingDegrees) } ?? "-")
            debugRow("signalQuality", telemetry?.signalQuality ?? "-")
            debugRow("lastUpdateMs", telemetry.map { String($0.lastUpdateMs) } ?? "-")
            debugRow("error", telemetry?.error ?? "null")
        }
        .panelStyle()
    }

    private var logsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BLE Logs")
                .font(.headline)

            if bleManager.logs.isEmpty {
                Text("No logs yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(bleManager.logs.enumerated()), id: \.offset) { _, log in
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .panelStyle()
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .leading)

            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lastPacketText: String {
        guard let lastPacketDate = bleManager.lastPacketDate else {
            return "No packets received"
        }

        return lastPacketDate.formatted(date: .omitted, time: .standard)
    }
}

private extension View {
    func panelStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DebugView_Previews: PreviewProvider {
    static var previews: some View {
        DebugView()
            .environmentObject(BLEManager())
    }
}

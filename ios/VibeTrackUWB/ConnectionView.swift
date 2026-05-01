import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var bleManager: BLEManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusPanel
                    scanControls
                    deviceList
                }
                .padding()
            }
            .navigationTitle("VibeTrack UWB")
            .background(Color(.systemBackground))
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection")
                        .font(.headline)

                    Text(bleManager.connectionState.displayText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                Spacer()
            }

            if let errorMessage = bleManager.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var scanControls: some View {
        HStack(spacing: 12) {
            Button {
                bleManager.startScanning()
            } label: {
                Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                bleManager.stopScanning()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Devices")
                .font(.headline)

            if bleManager.discoveredDevices.isEmpty {
                Text("No VibeTrack-UWB devices found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(bleManager.discoveredDevices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "wave.3.right")
                            .foregroundStyle(.cyan)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.headline)

                            Text("RSSI \(device.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            bleManager.connect(to: device)
                        } label: {
                            Label("Connect", systemImage: "link")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var statusIcon: String {
        switch bleManager.connectionState {
        case .scanning:
            return "dot.radiowaves.left.and.right"
        case .found:
            return "checkmark.circle"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "link.circle.fill"
        case .disconnected:
            return "xmark.circle"
        case .error, .bluetoothUnavailable:
            return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch bleManager.connectionState {
        case .connected:
            return .green
        case .found, .connecting, .scanning:
            return .cyan
        case .error, .bluetoothUnavailable:
            return .red
        case .disconnected:
            return .secondary
        }
    }
}

struct ConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionView()
            .environmentObject(BLEManager())
    }
}

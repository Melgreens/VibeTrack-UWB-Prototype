import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()

    var body: some View {
        TabView {
            ConnectionView()
                .environmentObject(bleManager)
                .tabItem {
                    Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
                }

            TrackingView()
                .environmentObject(bleManager)
                .tabItem {
                    Label("Tracking", systemImage: "location.north.line")
                }

            DebugView()
                .environmentObject(bleManager)
                .tabItem {
                    Label("Debug", systemImage: "terminal")
                }
        }
        .tint(.cyan)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

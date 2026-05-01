import Foundation

#if canImport(NearbyInteraction)
import NearbyInteraction
#endif

/*
 Nearby Interaction placeholder

 Real iPhone UWB distance and direction require an Apple-compatible Nearby
 Interaction accessory implementation. A generic DWM3000 module does not
 automatically interoperate with the iPhone UWB chip, and this prototype does
 not fake that support.

 The practical prototype uses BLE telemetry from the ESP32 instead:
 ESP32 reads/owns DWM3000 state, then sends JSON to the app over GATT.
 Keep the app on BLE telemetry unless the accessory later implements the
 Apple Nearby Interaction accessory protocol and can provide valid accessory
 configuration data to iOS.
 */

#if canImport(NearbyInteraction)
@available(iOS 14.0, *)
final class NearbyInteractionPlaceholder: NSObject {
    private var session: NISession?

    func prepareSessionOnlyAfterAccessoryProtocolExists() {
        // This is where NISession setup would live later:
        // session = NISession()
        // session?.delegate = self
        //
        // Do not run a session here today. The ESP32/DWM3000 firmware in this
        // prototype does not produce Apple-compatible NI accessory configuration
        // data or implement the required accessory protocol.
    }

    func runWhenValidAccessoryConfigurationDataExists(_ configurationData: Data) {
        // Future-only sketch, intentionally left inactive:
        //
        // do {
        //     let configuration = try NINearbyAccessoryConfiguration(data: configurationData)
        //     session?.run(configuration)
        // } catch {
        //     // Keep using BLE telemetry if configuration data is unavailable
        //     // or if the accessory protocol is not implemented/certified.
        // }
    }
}

@available(iOS 14.0, *)
extension NearbyInteractionPlaceholder: NISessionDelegate {
    func session(_ session: NISession, didInvalidateWith error: Error) {
        // Future NI error handling would go here.
    }
}
#else
final class NearbyInteractionPlaceholder {
    func prepareSessionOnlyAfterAccessoryProtocolExists() {
        // NearbyInteraction is not available on this build target.
    }

    func runWhenValidAccessoryConfigurationDataExists(_ configurationData: Data) {
        // Keep using BLE telemetry on targets without NearbyInteraction.
    }
}
#endif

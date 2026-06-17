import SwiftUI

@main
struct TimerApp: App {
    init() {
        // Register the notification delegate before the scene connects so
        // alarm notifications are handled even on a cold launch from a tap.
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

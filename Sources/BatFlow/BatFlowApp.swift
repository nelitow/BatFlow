import SwiftUI

@main
struct BatFlowApp: App {
    var body: some Scene {
        MenuBarExtra("BatFlow", systemImage: "bolt.batteryblock") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

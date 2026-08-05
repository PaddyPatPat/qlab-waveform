import AppKit
import SwiftUI

@main
struct QLabWaveformApp: App {
    @StateObject private var monitor = QLabMonitor()

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("QLab Waveform") {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 440, idealWidth: 1100, minHeight: 220, idealHeight: 420)
                .onAppear { monitor.start() }
        }
    }
}

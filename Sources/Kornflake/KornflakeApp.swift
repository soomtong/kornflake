import AppKit
import SwiftUI

@main
struct KornflakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Kornflake") {
            ContentView(model: model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("재생") {
                Button(model.isPlaying ? "정지" : "재생") {
                    model.togglePlay()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Panic (All Sound Off)") {
                    model.panic()
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

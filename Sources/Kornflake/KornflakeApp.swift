import SwiftUI

@main
struct KornflakeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    if model.libraries.isEmpty {
                        model.bootstrap()
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Kontakt Folder…") {
                    model.chooseRoot()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Rescan") {
                    model.scan()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Audition") {
                Button("Play") {
                    model.play()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Stop") {
                    model.stop()
                }
                .keyboardShortcut(".", modifiers: [.command])

                Divider()

                Button("Play C4") {
                    model.testTone()
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
    }
}

import SwiftUI

enum AppInfo {
    /// CFBundleShortVersionString from the bundle's Info.plist; "dev" when running without a
    /// bundle (swift run).
    static let versionString: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}

@main
struct KornflakeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.dark)
                .onAppear {
                    model.installKeyMonitor()
                    if model.rootURL == nil {
                        model.bootstrap()
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button(model.tr("Choose Instrument Folder…", "악기 폴더 선택…")) {
                    model.chooseRoot()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button(model.tr("Rescan", "다시 검색")) {
                    model.scan()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            // ⌘H and ⌥⌘H are used for navigation, so the app-hiding items are removed.
            CommandGroup(replacing: .appVisibility) {}

            CommandGroup(after: .help) {
                Button(model.tr("Switch to \(model.language == .ko ? "English" : "Korean")", "\(model.language == .ko ? "영어" : "한국어")로 전환")) {
                    model.toggleLanguage()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                // Shown disabled so the version is always visible without opening the About panel.
                Button(model.tr("Version \(AppInfo.versionString)", "버전 \(AppInfo.versionString)")) {}
                    .disabled(true)
            }

            CommandMenu(model.tr("Audition", "오디션")) {
                Button(model.tr("Play / Stop", "재생 / 정지")) {
                    model.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.isSearchFocused)

                Button(model.tr("Stop", "정지")) {
                    model.stop()
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button(model.tr("Play C4", "C4 재생")) {
                    model.testTone()
                }
                .keyboardShortcut("t", modifiers: [.command])
            }

            CommandMenu(model.tr("Patch", "패치")) {
                Button(model.tr("Search Patches", "패치 검색")) {
                    model.requestSearchFocus()
                }
                .keyboardShortcut("f", modifiers: [.command])

                Divider()

                Button(model.tr("Next Patch", "다음 패치")) { model.selectAdjacentPatch(1) }
                    .keyboardShortcut("j", modifiers: [.command])
                Button(model.tr("Previous Patch", "이전 패치")) { model.selectAdjacentPatch(-1) }
                    .keyboardShortcut("k", modifiers: [.command])
                Button(model.tr("Next Category", "다음 카테고리")) { model.selectAdjacentCategory(1) }
                    .keyboardShortcut("j", modifiers: [.command, .option])
                Button(model.tr("Previous Category", "이전 카테고리")) { model.selectAdjacentCategory(-1) }
                    .keyboardShortcut("k", modifiers: [.command, .option])

                Divider()

                Button(model.tr("Next Layer", "다음 레이어")) { model.cycleLayer(1) }
                    .keyboardShortcut("]", modifiers: [.command, .option])
                Button(model.tr("Previous Layer", "이전 레이어")) { model.cycleLayer(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .option])
            }

            CommandMenu(model.tr("Notes", "음")) {
                Button(model.tr("Scale Mode", "스케일 모드")) { model.mode = .scale }
                    .keyboardShortcut("1", modifiers: [.command])
                Button(model.tr("Chord Mode", "코드 모드")) { model.mode = .chord }
                    .keyboardShortcut("2", modifiers: [.command])
                Button(model.tr("Next Scale / Chord", "다음 스케일 / 코드")) { model.cycleScaleOrChord(1) }
                    .keyboardShortcut("]", modifiers: [.command])
                Button(model.tr("Previous Scale / Chord", "이전 스케일 / 코드")) { model.cycleScaleOrChord(-1) }
                    .keyboardShortcut("[", modifiers: [.command])

                Divider()

                Button(model.tr("Root Up", "근음 올리기")) { model.shiftRoot(1) }
                    .keyboardShortcut("l", modifiers: [.command])
                Button(model.tr("Root Down", "근음 내리기")) { model.shiftRoot(-1) }
                    .keyboardShortcut("h", modifiers: [.command])
                Button(model.tr("Extend Chord Up", "코드 위로 확장")) { model.adjustExtendUp(1) }
                    .keyboardShortcut("u", modifiers: [.command])
                Button(model.tr("Shrink Chord Up", "코드 위 확장 줄이기")) { model.adjustExtendUp(-1) }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button(model.tr("Extend Chord Down", "코드 아래로 확장")) { model.adjustExtendDown(1) }
                    .keyboardShortcut("b", modifiers: [.command])
                Button(model.tr("Shrink Chord Down", "코드 아래 확장 줄이기")) { model.adjustExtendDown(-1) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                Button(model.tr("Octave Up", "옥타브 올리기")) { model.shiftOctave(1) }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button(model.tr("Octave Down", "옥타브 내리기")) { model.shiftOctave(-1) }
                    .keyboardShortcut("h", modifiers: [.command, .option])
            }

            CommandMenu(model.tr("Playback", "재생 설정")) {
                Button(model.tr("Sequential / Together", "순차 / 동시")) { model.sequential.toggle() }
                    .keyboardShortcut("3", modifiers: [.command])
                Button(model.tr("Descending", "내림차순")) { model.descending.toggle() }
                    .keyboardShortcut("d", modifiers: [.command])
                Button(model.tr("Up & Down", "오르내리기")) { model.upDown.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(model.tr("Two Octaves", "2옥타브")) { model.twoOctaves.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Button(model.tr("Loop", "반복")) { model.loop.toggle() }
                    .keyboardShortcut("l", modifiers: [.option])
                Button(model.tr("MIDI Out", "MIDI 출력")) { model.midiEnabled.toggle() }
                    .keyboardShortcut("m", modifiers: [.option])
                Button(model.tr("Built-in Sound with MIDI", "MIDI와 함께 내장 음색")) { model.internalSound.toggle() }
                    .keyboardShortcut("i", modifiers: [.option])
                Button(model.tr("Auto Replay on Change", "변경 시 자동 재생")) { model.autoPlayback.toggle() }
                    .keyboardShortcut("a", modifiers: [.option])
                Button(model.tr("Pedal Hold", "페달 홀드")) { model.pedalHold.toggle() }
                    .keyboardShortcut("p", modifiers: [.option])
                Button(model.tr("Legato", "레가토")) { model.legato.toggle() }
                    .keyboardShortcut("g", modifiers: [.option])

                Divider()

                Button(model.tr("Longer Note", "음 길게")) { model.cycleNoteLength(1) }
                    .keyboardShortcut("=", modifiers: [.command])
                Button(model.tr("Shorter Note", "음 짧게")) { model.cycleNoteLength(-1) }
                    .keyboardShortcut("-", modifiers: [.command])
                Button(model.tr("Faster Tempo", "템포 빠르게")) { model.adjustTempo(5) }
                    .keyboardShortcut("=", modifiers: [.command, .option])
                Button(model.tr("Slower Tempo", "템포 느리게")) { model.adjustTempo(-5) }
                    .keyboardShortcut("-", modifiers: [.command, .option])
            }
        }
    }
}

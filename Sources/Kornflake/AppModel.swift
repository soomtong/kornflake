import AppKit
import Combine
import Foundation
import KornflakeCore

@MainActor
final class AppModel: ObservableObject {
    static let defaultLibraryRoot = URL(
        fileURLWithPath: "/Volumes/Ultra Touch/Play Series - Stacks"
    )

    private static let pitchClassNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]

    private let defaults = UserDefaults.standard
    let midi = MIDIOutput()
    let player = AuditionPlayer()

    @Published var libraryRoot: URL =
        AppModel.defaultLibraryRoot {
        didSet {
            defaults.set(libraryRoot.path, forKey: "libraryRoot")
        }
    }
    @Published private(set) var instruments: [LibraryItem] = []
    @Published private(set) var snapshots: [LibraryItem] = []
    @Published var searchText = ""
    @Published var selectedItemID: String?
    @Published private(set) var isScanning = false

    @Published var rootPitchClass: Int = 0 {
        didSet { persist() }
    }
    @Published var octave: Int = 4 {
        didSet { persist() }
    }
    @Published var soundKind: SoundKind = .scale {
        didSet { persist() }
    }
    @Published var scale: Scale = .major {
        didSet { persist() }
    }
    @Published var chord: Chord = .major7 {
        didSet { persist() }
    }
    @Published var auditionMode: AuditionMode = .sequence {
        didSet { persist() }
    }
    @Published var bpm: Double = 100 {
        didSet { persist() }
    }
    @Published var gate: Double = 0.8 {
        didSet { persist() }
    }
    @Published var loop = true {
        didSet { persist() }
    }
    @Published var midiChannel = 1 {
        didSet { persist() }
    }
    @Published var destinationID: Int32? {
        didSet {
            midi.selectedDestinationID = destinationID
            defaults.set(destinationID.map { Int($0) }, forKey: "destinationID")
        }
    }

    @Published private(set) var destinations: [MIDIDestination] = []
    @Published private(set) var midiReady = false
    @Published private(set) var activeNotes: Set<UInt8> = []
    @Published private(set) var isPlaying = false
    @Published var statusMessage = ""

    init() {
        if let storedRoot = defaults.string(forKey: "libraryRoot") {
            libraryRoot = URL(fileURLWithPath: storedRoot)
        }
        rootPitchClass = defaults.object(forKey: "rootPitchClass") as? Int ?? 0
        octave = defaults.object(forKey: "octave") as? Int ?? 4
        soundKind = SoundKind(rawValue: defaults.string(forKey: "soundKind") ?? "") ?? .scale
        scale = Scale(rawValue: defaults.string(forKey: "scale") ?? "") ?? .major
        chord = Chord(rawValue: defaults.string(forKey: "chord") ?? "") ?? .major7
        auditionMode = AuditionMode(rawValue: defaults.string(forKey: "auditionMode") ?? "") ?? .sequence
        bpm = defaults.object(forKey: "bpm") as? Double ?? 100
        gate = defaults.object(forKey: "gate") as? Double ?? 0.8
        loop = defaults.object(forKey: "loop") as? Bool ?? true
        midiChannel = defaults.object(forKey: "midiChannel") as? Int ?? 1
        if let storedID = defaults.object(forKey: "destinationID") as? Int {
            destinationID = Int32(storedID)
        }

        player.onNotesChanged = { [weak self] notes in
            self?.activeNotes = notes
        }
        player.onFinished = { [weak self] in
            self?.isPlaying = false
            self?.activeNotes = []
        }

        refreshMIDI()
        if let error = midi.errorMessage {
            statusMessage = error
        }
        loadLibrary()
    }

    var source: SoundSource {
        switch soundKind {
        case .scale: .scale(scale)
        case .chord: .chord(chord)
        }
    }

    var request: AuditionRequest {
        AuditionRequest(
            rootPitchClass: rootPitchClass,
            octave: octave,
            source: source,
            mode: auditionMode
        )
    }

    var currentNotes: [UInt8] { request.notes }

    var rootNoteName: String {
        "\(Self.pitchClassNames[((rootPitchClass % 12) + 12) % 12])\(octave)"
    }

    var filteredInstruments: [LibraryItem] {
        filter(instruments)
    }

    var filteredSnapshots: [LibraryItem] {
        filter(snapshots)
    }

    var selectedItem: LibraryItem? {
        instruments.first { $0.id == selectedItemID }
            ?? snapshots.first { $0.id == selectedItemID }
    }

    func noteName(_ note: UInt8) -> String {
        let pitchClass = Self.pitchClassNames[Int(note) % 12]
        return "\(pitchClass)\(Int(note) / 12 - 1)"
    }

    func noteNames(_ notes: [UInt8]) -> String {
        notes.map(noteName).joined(separator: " ")
    }

    func play() {
        guard !currentNotes.isEmpty else { return }
        player.play(
            notes: currentNotes,
            mode: auditionMode,
            timing: AuditionTiming(bpm: bpm, gate: gate),
            loop: loop,
            midi: midi,
            channel: midiChannelByte
        )
        isPlaying = true
    }

    func stop() {
        player.stop()
        isPlaying = false
    }

    func togglePlay() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }

    func panic() {
        player.stop()
        midi.panic(channel: midiChannelByte)
        isPlaying = false
        statusMessage = "Panic: All Sound Off 전송"
    }

    func testMIDI() {
        midi.playTestNote(channel: midiChannelByte)
        statusMessage = "MIDI 테스트: C4 전송"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard let self else { return }
            self.midi.stopTestNote(channel: self.midiChannelByte)
        }
    }

    func refreshMIDI() {
        midi.refreshDestinations()
        destinations = midi.destinations
        midiReady = midi.isAvailable
        if let id = destinationID, !destinations.contains(where: { $0.id == id }) {
            destinationID = nil
        }
        midi.selectedDestinationID = destinationID
        if let error = midi.errorMessage {
            statusMessage = error
        } else {
            statusMessage = "MIDI 준비됨: \(destinations.count)개 출력 대상"
        }
    }

    func loadLibrary() {
        let root = libraryRoot
        isScanning = true
        statusMessage = "라이브러리 스캔 중…"
        Task {
            do {
                let scan = try await Task.detached(priority: .userInitiated) {
                    try LibraryScanner.scan(root: root)
                }.value
                instruments = scan.instruments
                snapshots = scan.snapshots
                statusMessage =
                    "악기 \(scan.instruments.count)개, 스냅샷 \(scan.snapshots.count)개"
            } catch {
                instruments = []
                snapshots = []
                statusMessage = error.localizedDescription
            }
            isScanning = false
        }
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = libraryRoot
        panel.prompt = "선택"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryRoot = url
        selectedItemID = nil
        loadLibrary()
    }

    func openInKontakt(_ item: LibraryItem) {
        guard item.kind != .snapshot else {
            reveal(item)
            return
        }
        NSWorkspace.shared.open(item.url)
        statusMessage = "Kontakt에서 \(item.name) 여는 중…"
    }

    func reveal(_ item: LibraryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyPath(_ item: LibraryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
        statusMessage = "경로 복사됨: \(item.relativePath)"
    }

    private var midiChannelByte: UInt8 {
        UInt8(min(max(midiChannel, 1), 16) - 1)
    }

    private func filter(_ items: [LibraryItem]) -> [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.relativePath.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private func persist() {
        defaults.set(rootPitchClass, forKey: "rootPitchClass")
        defaults.set(octave, forKey: "octave")
        defaults.set(soundKind.rawValue, forKey: "soundKind")
        defaults.set(scale.rawValue, forKey: "scale")
        defaults.set(chord.rawValue, forKey: "chord")
        defaults.set(auditionMode.rawValue, forKey: "auditionMode")
        defaults.set(bpm, forKey: "bpm")
        defaults.set(gate, forKey: "gate")
        defaults.set(loop, forKey: "loop")
        defaults.set(midiChannel, forKey: "midiChannel")
    }
}

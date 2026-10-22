import Foundation
import Combine
import AppKit
import AVFoundation
import KornflakeCore

final class AppModel: ObservableObject {
    private static let folderDefaultsKey = "instrumentFolderPath"

    /// The single Kontakt instrument folder (for example "Yamaha Motif ES").
    /// Its sub-folders are patch categories and the .nki files inside are patches.
    @Published private(set) var rootURL: URL?
    @Published private(set) var categories: [LibraryRef] = []
    @Published private(set) var instrumentByID: [String: InstrumentRef] = [:]

    @Published var selectedInstrumentID: String?
    @Published var searchText = ""
    @Published var isSearchFocused = false
    @Published private(set) var searchFocusRequest = 0

    @Published private(set) var isScanning = false
    @Published private var scanStatus: ScanStatus = .idle
    @Published private(set) var scanFraction = 0.0

    @Published private(set) var parsedInstrument: ParsedInstrument?
    @Published private(set) var isParsing = false
    @Published private var parseIssue: ParseIssue?
    @Published var language: AppLanguage = {
        UserDefaults.standard.string(forKey: "language").flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.systemDefault
    }() {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    @Published var selectedGroupIndex: Int?

    @Published var mode: AuditionMode = .scale
    @Published var rootPitchClass = 0
    @Published var octave = 4
    @Published var scale: ScaleType = ScaleType.all[0]
    @Published var chord: ChordType = ChordType.all[0]
    @Published var sequential = true
    @Published var descending = false
    @Published var twoOctaves = true
    /// Scale goes up and back down (or down and back up with descending) in one pass.
    @Published var upDown = true
    @Published var extendUp = 0
    @Published var extendDown = 0
    @Published var loop = false
    @Published var noteLength: NoteLength = .quarter
    /// Time from one note's start to the next in sequential mode, separate from how long each note sounds.
    @Published var stepLength: NoteLength = .quarter
    @Published var tempo: Double = 120
    /// Pedal latched on (⌥P). Tab holds the pedal only while pressed (`pedalHeld`).
    @Published var pedalHold = false { didSet { pedalChanged() } }
    @Published private(set) var pedalHeld = false { didSet { pedalChanged() } }
    /// Sequential notes ring into the next one instead of stopping at the note length.
    @Published var legato = false
    /// Restart playback when a control changes while playing, so the new setting is heard at once.
    @Published var autoPlayback = true

    @Published var midiEnabled = AppModel.stored("midiEnabled", false) {
        didSet { UserDefaults.standard.set(midiEnabled, forKey: "midiEnabled") }
    }
    /// 1...16 as shown to the user.
    @Published var midiChannel = AppModel.stored("midiChannel", 1) {
        didSet { UserDefaults.standard.set(midiChannel, forKey: "midiChannel") }
    }
    /// nil is the "Kornflake" virtual port; otherwise the unique ID of a MIDI destination.
    @Published var midiDestinationID: Int32? = {
        (UserDefaults.standard.object(forKey: "midiDestinationID") as? Int).map { Int32(truncatingIfNeeded: $0) }
    }() {
        didSet { UserDefaults.standard.set(midiDestinationID.map { Int($0) }, forKey: "midiDestinationID") }
    }
    /// Keeps the built-in sample sound on so it plays together with MIDI out.
    @Published var internalSound = AppModel.stored("internalSound", true) {
        didSet { UserDefaults.standard.set(internalSound, forKey: "internalSound") }
    }
    @Published private(set) var midiDestinations: [MIDIDestinationInfo] = []

    @Published private(set) var isPlaying = false
    @Published private(set) var currentNoteNames: [String] = []
    @Published private(set) var playbackMessage = ""
    /// Playback has started but the first note has not sounded yet (samples are still loading).
    @Published private(set) var isPreparing = false

    private enum ScanStatus {
        case idle
        case scanning
        case progress(library: String, patches: Int)
        case done(name: String, categories: Int, patches: Int)
        case failed(String)
    }

    private enum ParseIssue {
        case protected
        case k42
        case unknown
        case failed(String)
    }

    private let midi = MIDIOutput()
    private var keyMonitor: Any?
    private var resignObserver: Any?
    private var autoPlaybackCancellable: AnyCancellable?
    private var playWhenParsed = false
    private var isTestTone = false
    private let player = PreviewPlayer()
    private let playbackQueue = DispatchQueue(label: "kornflake.preview", qos: .userInitiated)
    /// MIDI note-off timers run here so main-thread UI work cannot delay them.
    private let timingQueue = DispatchQueue(label: "kornflake.midi.timing", qos: .userInteractive)
    /// Guards the generation counters. Also the condition that playback waits on, so stop()
    /// wakes a sleeping sequence immediately instead of at the next poll.
    private let stateLock = NSCondition()
    private var playbackGeneration: UInt64 = 0
    /// `isPedalDown` for the playback queue, which reads it note by note. Guarded by `stateLock`.
    private var pedalDownForPlayback = false
    private var parseGeneration: UInt64 = 0

    private static func stored<T>(_ key: String, _ fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }

    init() {
        refreshMIDIDestinations()
        midi.onSetupChanged = { [weak self] in
            DispatchQueue.main.async { self?.refreshMIDIDestinations() }
        }

        // @Published fires before the value changes; the debounce lets it settle before restarting.
        let changes: [AnyPublisher<Void, Never>] = [
            $mode.map { _ in }.eraseToAnyPublisher(),
            $rootPitchClass.map { _ in }.eraseToAnyPublisher(),
            $octave.map { _ in }.eraseToAnyPublisher(),
            $scale.map { _ in }.eraseToAnyPublisher(),
            $chord.map { _ in }.eraseToAnyPublisher(),
            $sequential.map { _ in }.eraseToAnyPublisher(),
            $descending.map { _ in }.eraseToAnyPublisher(),
            $twoOctaves.map { _ in }.eraseToAnyPublisher(),
            $upDown.map { _ in }.eraseToAnyPublisher(),
            $extendUp.map { _ in }.eraseToAnyPublisher(),
            $extendDown.map { _ in }.eraseToAnyPublisher(),
            $noteLength.map { _ in }.eraseToAnyPublisher(),
            $stepLength.map { _ in }.eraseToAnyPublisher(),
            $tempo.map { _ in }.eraseToAnyPublisher(),
            $legato.map { _ in }.eraseToAnyPublisher(),
            $loop.map { _ in }.eraseToAnyPublisher(),
            $selectedGroupIndex.map { _ in }.eraseToAnyPublisher(),
            $midiEnabled.map { _ in }.eraseToAnyPublisher(),
            $midiChannel.map { _ in }.eraseToAnyPublisher(),
            $midiDestinationID.map { _ in }.eraseToAnyPublisher(),
            $internalSound.map { _ in }.eraseToAnyPublisher()
        ]
        autoPlaybackCancellable = Publishers.MergeMany(changes)
            .dropFirst(changes.count)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, self.autoPlayback, self.isPlaying, !self.isTestTone else { return }
                self.play()
            }
    }

    var selectedInstrument: InstrumentRef? {
        guard let selectedInstrumentID else { return nil }
        return instrumentByID[selectedInstrumentID]
    }

    var scanMessage: String {
        switch scanStatus {
        case .idle:
            return ""
        case .scanning:
            return tr("Scanning patches…", "패치를 검색하는 중…")
        case .progress(let library, let patches):
            return tr("\(library) · \(patches) patches", "\(library) · 패치 \(patches)개")
        case .done(let name, let categories, let patches):
            return tr(
                "\(name) · \(categories) categories · \(patches) patches",
                "\(name) · 카테고리 \(categories)개 · 패치 \(patches)개"
            )
        case .failed(let message):
            return tr("Scan failed: \(message)", "검색 실패: \(message)")
        }
    }

    var parseMessage: String? {
        switch parseIssue {
        case nil:
            return nil
        case .protected:
            return tr(
                "This is a Kontakt 5+ encrypted container. Kornflake does not decrypt protected instruments. To audition this one, load it in Kontakt.",
                "Kontakt 5+ 암호화 컨테이너입니다. Kornflake는 보호된 악기를 복호화하지 않습니다. 이 악기는 Kontakt에서 불러와 들어 보세요."
            )
        case .k42:
            return tr(
                "Kontakt 4.2 instruments use a different compressed mapping that is not supported yet.",
                "Kontakt 4.2 악기는 다른 압축 매핑을 사용하며 아직 지원하지 않습니다."
            )
        case .unknown:
            return tr("Unrecognized Kontakt file format.", "인식할 수 없는 Kontakt 파일 형식입니다.")
        case .failed(let message):
            return message
        }
    }

    var instrumentName: String {
        rootURL?.lastPathComponent ?? "Yamaha Motif Player"
    }

    var patchCount: Int {
        instrumentByID.values.lazy.filter { $0.isPlayable }.count
    }

    /// Patch categories filtered by the search text. Categories without a match are dropped.
    var visibleCategories: [LibraryRef] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return categories.compactMap { category in
            var patches = category.instruments.filter { $0.isPlayable }
            if !query.isEmpty && !CategoryStyle(folderName: category.name).matches(query) {
                patches = patches.filter { $0.name.localizedCaseInsensitiveContains(query) }
            }
            guard !patches.isEmpty else { return nil }
            var filtered = category
            filtered.instruments = patches
            return filtered
        }
    }

    // MARK: Keyboard navigation

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }

    /// Moves the patch selection through the visible (filtered) list without wrapping.
    func selectAdjacentPatch(_ delta: Int) {
        let ids = visibleCategories.flatMap { $0.instruments.map(\.id) }
        guard !ids.isEmpty else { return }
        guard let current = selectedInstrumentID.flatMap({ ids.firstIndex(of: $0) }) else {
            selectedInstrumentID = delta > 0 ? ids.first : ids.last
            return
        }
        selectedInstrumentID = ids[min(ids.count - 1, max(0, current + delta))]
    }

    func selectFirstVisiblePatch() {
        selectedInstrumentID = visibleCategories.first?.instruments.first?.id
    }

    /// Jumps to the first patch of the next or previous category.
    func selectAdjacentCategory(_ delta: Int) {
        let visible = visibleCategories
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { category in
            category.instruments.contains { $0.id == selectedInstrumentID }
        }
        let target = current.map { min(visible.count - 1, max(0, $0 + delta)) } ?? (delta > 0 ? 0 : visible.count - 1)
        selectedInstrumentID = visible[target].instruments.first?.id
    }

    /// Kontakt group names in these patches are leftovers such as "slice #1 (from: SoTrue) #2",
    /// so a layer is described by what it actually covers instead.
    func layerLabel(_ group: K2Group, position: Int) -> String {
        let zones = parsedInstrument?.zones.filter { $0.groupIndex == group.index } ?? []
        var parts = [tr("Layer \(position)", "레이어 \(position)")]
        if let low = zones.map(\.lowVelocity).min(), let high = zones.map(\.highVelocity).max() {
            parts.append(low <= 1 && high >= 127
                ? tr("all velocities", "전체 벨로시티")
                : tr("velocity \(low)–\(high)", "벨로시티 \(low)–\(high)"))
        }
        if let low = zones.map(\.lowKey).min(), let high = zones.map(\.highKey).max() {
            parts.append("\(NoteNaming.name(midi: low))–\(NoteNaming.name(midi: high))")
        }
        parts.append(tr("\(zones.count) zones", "존 \(zones.count)개"))
        return parts.joined(separator: " · ")
    }

    func cycleLayer(_ delta: Int) {
        let options: [Int?] = [nil] + availableGroups.map { Optional($0.index) }
        let current = options.firstIndex { $0 == selectedGroupIndex } ?? 0
        selectedGroupIndex = options[(current + delta + options.count) % options.count]
    }

    func cycleScaleOrChord(_ delta: Int) {
        if mode == .scale {
            scale = Self.cycled(ScaleType.all, from: scale, by: delta)
        } else {
            chord = Self.cycled(ChordType.all, from: chord, by: delta)
        }
    }

    func refreshMIDIDestinations() {
        midiDestinations = midi.destinations()
        // A remembered port that has been unplugged falls back to the virtual port.
        if let id = midiDestinationID, !midiDestinations.contains(where: { $0.id == id }) {
            midiDestinationID = nil
        }
    }

    /// The MIDI target for a new playback, or nil while MIDI out is off.
    private var activeMIDITarget: MIDITarget? {
        midiEnabled ? MIDITarget(channel: midiChannel - 1, destinationID: midiDestinationID) : nil
    }

    func adjustExtendUp(_ delta: Int) {
        extendUp = min(Self.maxExtension, max(0, extendUp + delta))
    }

    func adjustExtendDown(_ delta: Int) {
        extendDown = min(Self.maxExtension, max(0, extendDown + delta))
    }

    static let maxExtension = 6

    func shiftRoot(_ delta: Int) {
        rootPitchClass = ((rootPitchClass + delta) % 12 + 12) % 12
    }

    func shiftOctave(_ delta: Int) {
        octave = min(6, max(1, octave + delta))
    }

    func cycleNoteLength(_ delta: Int) {
        let all = NoteLength.allCases
        let current = all.firstIndex(of: noteLength) ?? 0
        noteLength = all[min(all.count - 1, max(0, current + delta))]
    }

    func adjustTempo(_ delta: Double) {
        tempo = min(240, max(40, tempo + delta))
    }

    private static func cycled<T: Equatable>(_ all: [T], from value: T, by delta: Int) -> T {
        let current = all.firstIndex(of: value) ?? 0
        return all[(current + delta + all.count) % all.count]
    }

    /// Sample lookup is scoped to the loaded instrument folder.
    private var resolverLocation: (root: URL, library: String) {
        guard let rootURL else { return (URL(fileURLWithPath: "/"), "") }
        return (rootURL.deletingLastPathComponent(), rootURL.lastPathComponent)
    }

    var noteDuration: TimeInterval {
        noteLength.seconds(at: tempo)
    }

    var stepDuration: TimeInterval {
        stepLength.seconds(at: tempo)
    }

    /// Legato only applies to sequential playback; together, every note already overlaps.
    /// The pedal applies live: notes started while it is down ring to their natural decay.
    var isPedalDown: Bool {
        pedalHold || pedalHeld
    }

    var isLegatoActive: Bool {
        legato && sequential
    }

    /// How long each note sounds: the note length, or in legato up to just past the next note.
    var playedNoteDuration: TimeInterval {
        isLegatoActive ? Legato.noteDuration(step: stepDuration) : noteDuration
    }

    var plannedPlan: AuditionPlan {
        AuditionBuilder.makePlan(
            mode: mode,
            rootPitchClass: rootPitchClass,
            octave: octave,
            scale: scale,
            chord: chord,
            descending: descending,
            twoOctaves: twoOctaves,
            extendUp: extendUp,
            extendDown: extendDown,
            upDown: upDown,
            seamless: loop
        )
    }

    var availableGroups: [K2Group] {
        guard let parsedInstrument else { return [] }
        let groupIndices = Set(parsedInstrument.zones.map(\.groupIndex))
        return parsedInstrument.groups.filter { groupIndices.contains($0.index) && !$0.isReleaseTrigger && !$0.isMuted }
    }

    /// Loads the folder remembered from the last session, or asks for one.
    func bootstrap() {
        if let path = UserDefaults.standard.string(forKey: Self.folderDefaultsKey),
           FileManager.default.fileExists(atPath: path) {
            load(folder: URL(fileURLWithPath: path, isDirectory: true))
        } else {
            chooseRoot()
        }
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = tr(
            "Choose the Kontakt instrument folder (for example Yamaha Motif ES)",
            "Kontakt 악기 폴더를 선택하세요 (예: Yamaha Motif ES)"
        )
        panel.prompt = tr("Load Instrument", "악기 불러오기")
        panel.directoryURL = rootURL?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Self.folderDefaultsKey)
            load(folder: url)
        }
    }

    private func load(folder: URL) {
        stop()
        rootURL = folder
        selectedInstrumentID = nil
        parsedInstrument = nil
        scan()
    }

    func scan() {
        guard !isScanning, let root = rootURL else { return }
        isScanning = true
        scanStatus = .scanning
        scanFraction = 0
        categories = []
        instrumentByID = [:]
        selectedInstrumentID = nil
        parsedInstrument = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try KontaktScanner.scan(rootURL: root) { progress in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.scanStatus = .progress(library: progress.library, patches: progress.instruments)
                        self.scanFraction = progress.fraction
                    }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.categories = result
                    var index: [String: InstrumentRef] = [:]
                    for category in result {
                        for instrument in category.instruments {
                            index[instrument.id] = instrument
                        }
                    }
                    self.instrumentByID = index
                    self.isScanning = false
                    self.scanFraction = 1
                    self.scanStatus = .done(name: root.lastPathComponent, categories: result.count, patches: index.count)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isScanning = false
                    self.scanStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    func selectInstrument(_ id: String?) {
        let keepPlaying = autoPlayback && isPlaying && !isTestTone
        parsedInstrument = nil
        parseIssue = nil
        selectedGroupIndex = nil
        playWhenParsed = false
        stop()
        guard let id, let instrument = instrumentByID[id] else { return }
        playWhenParsed = keepPlaying
        parse(instrument: instrument)
    }

    private func parse(instrument: InstrumentRef) {
        stateLock.lock()
        parseGeneration &+= 1
        let generation = parseGeneration
        stateLock.unlock()

        guard instrument.format == .k2 else {
            if instrument.format == .k5 || instrument.format == .k5Monolith {
                parseIssue = .protected
            } else if instrument.format == .k42 {
                parseIssue = .k42
            } else {
                parseIssue = .unknown
            }
            return
        }

        isParsing = true
        let url = instrument.url

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let parsed = try K2Parser.parse(url: url)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.stateLock.lock()
                    let current = self.parseGeneration
                    self.stateLock.unlock()
                    guard current == generation else { return }
                    self.parsedInstrument = parsed
                    self.isParsing = false
                    self.parseIssue = nil
                    self.selectedGroupIndex = nil
                    if self.playWhenParsed {
                        self.playWhenParsed = false
                        self.play()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.stateLock.lock()
                    let current = self.parseGeneration
                    self.stateLock.unlock()
                    guard current == generation else { return }
                    self.isParsing = false
                    self.parseIssue = .failed(error.localizedDescription)
                }
            }
        }
    }

    func play() {
        if isParsing {
            // Space right after picking a patch: start as soon as the mapping is ready.
            playWhenParsed = true
            return
        }
        guard let parsed = parsedInstrument, parsed.format == .k2 else { return }
        stop()

        do {
            try player.prepare()
        } catch {
            playbackMessage = tr(
                "Audio engine could not start: \(error.localizedDescription)",
                "오디오 엔진을 시작할 수 없습니다: \(error.localizedDescription)"
            )
            return
        }

        let plan = plannedPlan
        guard !plan.midiNotes.isEmpty else { return }
        let groupIndex = selectedGroupIndex
        let (root, library) = resolverLocation
        let length = playedNoteDuration
        let step = stepDuration
        let shouldLoop = loop
        let together = !sequential
        // Legato decides where each note ends, so it overrides the pedal.
        let allowPedal = !isLegatoActive
        let fadeOut = isLegatoActive ? Legato.overlap : PreviewPlayer.defaultFadeOut
        let target = activeMIDITarget
        let useInternal = internalSound || target == nil

        let generation = advancePlaybackGeneration()

        if allowPedal, isPedalDown, let target { midi.sustain(true, target: target) }
        isPlaying = true
        currentNoteNames = []
        isPreparing = true

        playbackQueue.async { [weak self] in
            guard let self else { return }
            self.runPlayback(
                parsed: parsed,
                plan: plan,
                groupIndex: groupIndex,
                rootURL: root,
                libraryName: library,
                noteLength: length,
                stepInterval: step,
                loop: shouldLoop,
                together: together,
                allowPedal: allowPedal,
                fadeOut: fadeOut,
                midiTarget: target,
                useInternal: useInternal,
                generation: generation
            )
        }
    }

    /// Key handling that menu key equivalents cannot cover.
    /// - Space: a focused list, button or picker consumes a bare space before the menu sees
    ///   it. Text input still receives the key, so searching for "Full Grand" keeps working.
    /// - Arrow keys: ⌘ and ⌥⌘ with an arrow mirror the H/J/K/L menu shortcuts, so both
    ///   styles work. The menu can only show one shortcut per item.
    /// - Tab: a sustain pedal held while the key is down. Menus only see key-down events.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, !(event.window is NSPanel) else { return event }
            if event.keyCode == 48 {
                return self.handlePedalKey(event) ? nil : event
            }
            guard event.type == .keyDown,
                  !(event.window?.firstResponder is NSText && event.keyCode == 49)
            else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 49, flags.isEmpty {
                if !event.isARepeat { self.togglePlayback() }
                return nil
            }

            let withOption = flags == [.command, .option]
            guard flags == [.command] || withOption else { return event }
            switch event.keyCode {
            case 125: withOption ? self.selectAdjacentCategory(1) : self.selectAdjacentPatch(1)
            case 126: withOption ? self.selectAdjacentCategory(-1) : self.selectAdjacentPatch(-1)
            case 124: withOption ? self.shiftOctave(1) : self.shiftRoot(1)
            case 123: withOption ? self.shiftOctave(-1) : self.shiftRoot(-1)
            default: return event
            }
            return nil
        }
        // A key released while another app is active never sends key-up here.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pedalHeld = false
        }
    }

    /// Tab presses the pedal. Text input keeps Tab for moving focus, but a release always
    /// lifts the pedal so it cannot stick.
    private func handlePedalKey(_ event: NSEvent) -> Bool {
        if event.type == .keyUp {
            guard pedalHeld else { return false }
            pedalHeld = false
            return true
        }
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              !(event.window?.firstResponder is NSText)
        else { return false }
        if !event.isARepeat { pedalHeld = true }
        return true
    }

    /// Hands the pedal to the playback queue and, while playing, moves the MIDI sustain with it.
    private func pedalChanged() {
        let down = isPedalDown
        stateLock.lock()
        let changed = pedalDownForPlayback != down
        pedalDownForPlayback = down
        stateLock.unlock()
        guard changed, isPlaying, isTestTone || !isLegatoActive, let target = activeMIDITarget else { return }
        midi.sustain(down, target: target)
    }

    private func pedalIsDownForPlayback() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pedalDownForPlayback
    }

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    func stop() {
        isTestTone = false
        // Bump first: any note send still in flight finishes under the lock before this
        // returns, so the note-off sweep below catches it.
        advancePlaybackGeneration()
        player.stopAll()
        midi.allNotesOff()
        isPlaying = false
        currentNoteNames = []
        playbackMessage = ""
        isPreparing = false
    }

    func testTone() {
        guard let parsed = parsedInstrument else { return }
        stop()
        do {
            try player.prepare()
        } catch {
            playbackMessage = tr(
                "Audio engine could not start: \(error.localizedDescription)",
                "오디오 엔진을 시작할 수 없습니다: \(error.localizedDescription)"
            )
            return
        }

        let generation = advancePlaybackGeneration()

        isPlaying = true
        isTestTone = true
        let (root, library) = resolverLocation
        let groupIndex = selectedGroupIndex
        let holdForTest = isPedalDown
        let target = activeMIDITarget
        let useInternal = internalSound || target == nil
        if holdForTest, let target { midi.sustain(true, target: target) }
        playbackQueue.async { [weak self] in
            guard let self else { return }
            var wait: TimeInterval = 1.5
            var prepared: [PreparedNote] = []
            if useInternal,
               let zone = self.selectZone(parsed: parsed, groupIndex: groupIndex, midi: 60, velocity: 100),
               let note = self.prepareNote(
                   zone: zone,
                   parsed: parsed,
                   midi: 60,
                   rootURL: root,
                   libraryName: library
               ) {
                prepared = [note]
                if holdForTest {
                    wait = min(12, max(1.5, note.naturalDuration))
                }
            }
            self.playNotes(prepared, midiNotes: [60], target: target, duration: 1.4, hold: holdForTest, generation: generation)
            // Interruptible: this queue is serial, so a plain sleep here would hold back a
            // Play pressed during the test tone until the sleep ended.
            self.sleepInterruptibly(wait, generation: generation)
            self.finishIfCurrent(generation)
        }
    }

    private func runPlayback(
        parsed: ParsedInstrument,
        plan: AuditionPlan,
        groupIndex: Int?,
        rootURL: URL,
        libraryName: String,
        noteLength: Double,
        stepInterval: Double,
        loop: Bool,
        together: Bool,
        allowPedal: Bool,
        fadeOut: TimeInterval,
        midiTarget: MIDITarget?,
        useInternal: Bool,
        generation: UInt64
    ) {
        // Resolve and decode every note before the first one sounds. Decoding then never lands
        // between two notes, and the same buffers serve every loop cycle.
        var prepared: [PreparedNote?] = []
        prepared.reserveCapacity(plan.midiNotes.count)
        for midi in plan.midiNotes {
            if !isCurrent(generation) { return }
            var note: PreparedNote?
            if useInternal,
               let zone = selectZone(parsed: parsed, groupIndex: groupIndex, midi: midi, velocity: 100) {
                note = prepareNote(zone: zone, parsed: parsed, midi: midi, rootURL: rootURL, libraryName: libraryName)
            }
            prepared.append(note)
        }

        repeat {
            if !isCurrent(generation) { return }

            if together {
                let hold = allowPedal && pedalIsDownForPlayback()
                let duration = max(0.1, noteLength)
                let notes = prepared.compactMap { $0 }
                playNotes(
                    notes,
                    midiNotes: plan.midiNotes,
                    target: midiTarget,
                    duration: duration,
                    hold: hold,
                    generation: generation
                )
                updateCurrentNotes(plan.names, generation: generation)
                let ring = notes.map(\.naturalDuration).max() ?? 0
                let interval = hold ? min(12, max(noteLength, ring)) : duration + 0.12
                sleepInterruptibly(interval, generation: generation)
            } else {
                // Each note starts at a fixed offset from the cycle start, so the time spent
                // starting one note never pushes the following notes later.
                var slot = Date()
                var lastNaturalDuration: TimeInterval = 0
                var lastHold = false
                for (index, midi) in plan.midiNotes.enumerated() {
                    sleepInterruptibly(until: slot, generation: generation)
                    if !isCurrent(generation) { return }
                    let hold = allowPedal && pedalIsDownForPlayback()
                    lastHold = hold
                    let notes = prepared[index].map { [$0] } ?? []
                    if let note = notes.first { lastNaturalDuration = note.naturalDuration }
                    playNotes(
                        notes,
                        midiNotes: [midi],
                        target: midiTarget,
                        duration: noteLength,
                        hold: hold,
                        fadeOut: fadeOut,
                        generation: generation
                    )
                    updateCurrentNotes([plan.names[index]], generation: generation)
                    slot = slot.addingTimeInterval(stepInterval)
                }
                // `slot` is now one step after the last note. When not looping, also let the last
                // note finish: it may ring longer than a step, and the MIDI note-off must be sent
                // before the final all-notes-off sweep cuts it.
                var end = slot.addingTimeInterval(0.1)
                if !loop {
                    let lastStart = slot.addingTimeInterval(-stepInterval)
                    end = max(end, lastStart.addingTimeInterval(noteLength + 0.1))
                    if lastHold {
                        end = max(end, lastStart.addingTimeInterval(min(12, max(1.0, lastNaturalDuration)) + 0.1))
                    }
                }
                sleepInterruptibly(until: end, generation: generation)
            }
        } while loop && isCurrent(generation)

        finishIfCurrent(generation)
    }

    private struct PreparedNote {
        let buffer: AVAudioPCMBuffer
        let rate: Double
        let gain: Float
        let pan: Float
        let naturalDuration: TimeInterval
    }

    private func prepareNote(
        zone: K2Zone,
        parsed: ParsedInstrument,
        midi: Int,
        rootURL: URL,
        libraryName: String
    ) -> PreparedNote? {
        do {
            let resolver = SampleResolverStore.shared.resolver(rootURL: rootURL, libraryName: libraryName)
            let url = try resolver.resolve(zone: zone, in: parsed)
            let buffer = try AudioSampleLoader.shared.load(
                url: url,
                startFrame: zone.sampleStart,
                endFrame: zone.sampleEnd
            )

            let group = parsed.groups.first { $0.index == zone.groupIndex }
            let gain = parsed.programVolume
                * (group?.volume ?? 1)
                * zone.volume
            let pan = parsed.programPan + (group?.pan ?? 0) + zone.pan
            let rate = playbackRate(
                midi: midi,
                zone: zone,
                group: group,
                programTranspose: parsed.programTranspose,
                programTune: parsed.programTune
            )
            let naturalDuration = Double(buffer.frameLength) / AudioSampleLoader.shared.engineFormat.sampleRate / max(rate, 0.25)
            return PreparedNote(
                buffer: buffer,
                rate: rate,
                gain: gain,
                pan: pan,
                naturalDuration: naturalDuration
            )
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.playbackMessage = error.localizedDescription
            }
            return nil
        }
    }

    /// Starts the built-in voices and, when MIDI out is on, the same notes on the MIDI port.
    /// Each MIDI note ends after `duration`; the pedal (when held) is released in `finishIfCurrent`.
    private func playNotes(
        _ notes: [PreparedNote],
        midiNotes: [Int],
        target: MIDITarget?,
        duration: Double,
        hold: Bool,
        fadeOut: TimeInterval = PreviewPlayer.defaultFadeOut,
        generation: UInt64
    ) {
        guard !(notes.isEmpty && (target == nil || midiNotes.isEmpty)) else { return }
        // Sent from the playback queue rather than hopping to the main thread, so UI rendering
        // does not add jitter. `ifCurrent` holds the state lock, which keeps stop() from
        // sweeping notes off between the generation check and the note-on.
        ifCurrent(generation) {
            for note in notes {
                player.play(
                    buffer: note.buffer,
                    rate: note.rate,
                    gain: note.gain,
                    pan: note.pan,
                    duration: duration,
                    hold: hold,
                    fadeOut: fadeOut
                )
            }
            guard let target else { return }
            for note in midiNotes {
                midi.noteOn(note, target: target)
            }
        }
        guard let target else { return }
        // stop() already ends active notes, so a stale generation must not send a late
        // note-off that would cut a note of the playback that replaced it.
        timingQueue.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.ifCurrent(generation) {
                for note in midiNotes {
                    self.midi.noteOff(note, target: target)
                }
            }
        }
    }

    private func playbackRate(
        midi: Int,
        zone: K2Zone,
        group: K2Group?,
        programTranspose: Int,
        programTune: Float
    ) -> Double {
        guard zone.rootKey > 0 else { return 1 }
        if let group, !group.keyTracking { return 1 }
        func ratio(_ value: Float) -> Double {
            value > 0.0001 ? Double(value) : 1
        }
        let tune = ratio(zone.tune) * ratio(group?.tune ?? 1) * ratio(programTune)
        let semitones = Double(midi - zone.rootKey + programTranspose) + 12 * log2(tune)
        return pow(2, semitones / 12)
    }

    private func selectZone(
        parsed: ParsedInstrument,
        groupIndex: Int?,
        midi: Int,
        velocity: Int
    ) -> K2Zone? {
        let auditionGroupIndices = Set(parsed.auditionGroups.map(\.index))
        var pool = parsed.zones.filter { auditionGroupIndices.contains($0.groupIndex) }
        if pool.isEmpty { pool = parsed.zones }

        if let groupIndex {
            let restricted = pool.filter { $0.groupIndex == groupIndex }
            if !restricted.isEmpty { pool = restricted }
        }

        func coversKey(_ zone: K2Zone) -> Bool {
            zone.lowKey <= midi && midi <= zone.highKey
        }
        func coversVelocity(_ zone: K2Zone) -> Bool {
            zone.lowVelocity <= velocity && velocity <= zone.highVelocity
        }

        var candidates = pool.filter { coversKey($0) && coversVelocity($0) }
        if candidates.isEmpty {
            candidates = pool.filter { coversKey($0) }
        }
        if candidates.isEmpty {
            candidates = pool.min(by: { distanceToRange(midi, low: $0.lowKey, high: $0.highKey) < distanceToRange(midi, low: $1.lowKey, high: $1.highKey) }).map { [$0] } ?? []
        }

        return candidates.min { lhs, rhs in
            let lWidth = lhs.highVelocity - lhs.lowVelocity
            let rWidth = rhs.highVelocity - rhs.lowVelocity
            if lWidth != rWidth { return lWidth < rWidth }
            if lhs.groupIndex != rhs.groupIndex { return lhs.groupIndex < rhs.groupIndex }
            return abs(lhs.rootKey - midi) < abs(rhs.rootKey - midi)
        }
    }

    private func distanceToRange(_ value: Int, low: Int, high: Int) -> Int {
        if value < low { return low - value }
        if value > high { return value - high }
        return 0
    }

    private func updateCurrentNotes(_ names: [String], generation: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let current = self.playbackGeneration
            self.stateLock.unlock()
            guard current == generation else { return }
            self.currentNoteNames = names
            self.playbackMessage = ""
            self.isPreparing = false
        }
    }

    private func finishIfCurrent(_ generation: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let current = self.playbackGeneration
            self.stateLock.unlock()
            guard current == generation else { return }
            self.midi.allNotesOff()
            self.isPlaying = false
            self.currentNoteNames = []
            self.playbackMessage = ""
            self.isPreparing = false
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        stateLock.lock()
        let current = playbackGeneration
        stateLock.unlock()
        return current == generation
    }

    /// Runs `body` only while `generation` is still current, holding the state lock throughout
    /// so a concurrent stop() cannot slip in between the check and the work.
    private func ifCurrent(_ generation: UInt64, _ body: () -> Void) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard playbackGeneration == generation else { return }
        body()
    }

    /// Invalidates the running playback and wakes any sequence waiting in `sleepInterruptibly`.
    @discardableResult
    private func advancePlaybackGeneration() -> UInt64 {
        stateLock.lock()
        playbackGeneration &+= 1
        let generation = playbackGeneration
        stateLock.broadcast()
        stateLock.unlock()
        return generation
    }

    private func sleepInterruptibly(_ seconds: Double, generation: UInt64) {
        sleepInterruptibly(until: Date().addingTimeInterval(seconds), generation: generation)
    }

    /// Waits until `deadline` or until a newer playback replaces `generation`, whichever is first.
    private func sleepInterruptibly(until deadline: Date, generation: UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        while playbackGeneration == generation {
            // wait(until:) returns false once the deadline has passed.
            if !stateLock.wait(until: deadline) { return }
        }
    }
}

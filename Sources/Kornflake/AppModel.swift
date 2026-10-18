import Foundation
import Combine
import AppKit
import AVFoundation
import KornflakeCore

final class AppModel: ObservableObject {
    static let defaultRoot = URL(fileURLWithPath: "/Volumes/Ultra Touch/Pile/+Kontakt", isDirectory: true)

    @Published var rootURL: URL = AppModel.defaultRoot
    @Published private(set) var libraries: [LibraryRef] = []
    @Published private(set) var instrumentByID: [String: InstrumentRef] = [:]

    @Published var selectedLibraryID: String?
    @Published var selectedInstrumentID: String?
    @Published var searchText = ""
    @Published var drmFreeOnly = true

    @Published private(set) var isScanning = false
    @Published private(set) var scanMessage = ""
    @Published private(set) var scanFraction = 0.0

    @Published private(set) var parsedInstrument: ParsedInstrument?
    @Published private(set) var isParsing = false
    @Published private(set) var parseMessage: String?
    @Published var selectedGroupIndex: Int?

    @Published var mode: AuditionMode = .scale
    @Published var rootPitchClass = 0
    @Published var octave = 4
    @Published var scale: ScaleType = ScaleType.all[0]
    @Published var chord: ChordType = ChordType.all[0]
    @Published var sequential = true
    @Published var descending = false
    @Published var twoOctaves = false
    @Published var loop = false
    @Published var noteLength: NoteLength = .quarter
    @Published var tempo: Double = 120
    @Published var pedalHold = false

    @Published private(set) var isPlaying = false
    @Published private(set) var currentNoteNames: [String] = []
    @Published private(set) var playbackMessage = ""

    private let player = PreviewPlayer()
    private let playbackQueue = DispatchQueue(label: "kornflake.preview", qos: .userInitiated)
    private let stateLock = NSLock()
    private var playbackGeneration: UInt64 = 0
    private var parseGeneration: UInt64 = 0

    var selectedInstrument: InstrumentRef? {
        guard let selectedInstrumentID else { return nil }
        return instrumentByID[selectedInstrumentID]
    }

    var selectedLibrary: LibraryRef? {
        libraries.first { $0.id == selectedLibraryID }
    }

    var visibleLibraries: [LibraryRef] {
        if drmFreeOnly {
            return libraries.filter { $0.playableCount > 0 }
        }
        return libraries
    }

    var totalVisibleInstrumentCount: Int {
        if drmFreeOnly {
            return instrumentByID.values.lazy.filter { $0.isPlayable }.count
        }
        return instrumentByID.count
    }

    var visibleInstruments: [InstrumentRef] {
        var result: [InstrumentRef]
        if let selectedLibrary = selectedLibrary {
            result = selectedLibrary.instruments
        } else {
            result = libraries.flatMap(\.instruments)
        }
        if drmFreeOnly {
            result = result.filter { $0.isPlayable }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { instrument in
                instrument.name.localizedCaseInsensitiveContains(query)
                    || instrument.library.localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    var noteDuration: TimeInterval {
        noteLength.seconds(at: tempo)
    }

    var plannedPlan: AuditionPlan {
        AuditionBuilder.makePlan(
            mode: mode,
            rootPitchClass: rootPitchClass,
            octave: octave,
            scale: scale,
            chord: chord,
            descending: descending,
            twoOctaves: twoOctaves
        )
    }

    var availableGroups: [K2Group] {
        guard let parsedInstrument else { return [] }
        let groupIndices = Set(parsedInstrument.zones.map(\.groupIndex))
        return parsedInstrument.groups.filter { groupIndices.contains($0.index) && !$0.isReleaseTrigger && !$0.isMuted }
    }

    func bootstrap() {
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            rootURL = FileManager.default.homeDirectoryForCurrentUser
        }
        scan()
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Kontakt Folder"
        panel.directoryURL = rootURL
        if panel.runModal() == .OK, let url = panel.url {
            stop()
            rootURL = url
            selectedLibraryID = nil
            selectedInstrumentID = nil
            parsedInstrument = nil
            scan()
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanMessage = "Scanning instrument files…"
        scanFraction = 0
        libraries = []
        instrumentByID = [:]
        selectedInstrumentID = nil
        parsedInstrument = nil

        let root = rootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try KontaktScanner.scan(rootURL: root) { progress in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.scanMessage = "\(progress.library) · \(progress.instruments) instruments"
                        self.scanFraction = progress.fraction
                    }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.libraries = result
                    var index: [String: InstrumentRef] = [:]
                    for library in result {
                        for instrument in library.instruments {
                            index[instrument.id] = instrument
                        }
                    }
                    self.instrumentByID = index
                    self.isScanning = false
                    self.scanFraction = 1
                    self.scanMessage = "\(result.count) libraries · \(index.count) instruments"
                    if self.selectedLibraryID == nil {
                        self.selectedLibraryID = self.visibleLibraries.first(where: { $0.playableCount > 0 })?.id
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isScanning = false
                    self.scanMessage = "Scan failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func selectInstrument(_ id: String?) {
        parsedInstrument = nil
        parseMessage = nil
        selectedGroupIndex = nil
        stop()
        guard let id, let instrument = instrumentByID[id] else { return }
        parse(instrument: instrument)
    }

    private func parse(instrument: InstrumentRef) {
        stateLock.lock()
        parseGeneration &+= 1
        let generation = parseGeneration
        stateLock.unlock()

        guard instrument.format == .k2 else {
            if instrument.format == .k5 || instrument.format == .k5Monolith {
                parseMessage = "This is a Kontakt 5+ encrypted container. Kornflake does not decrypt protected instruments. To audition this one, load it in Kontakt."
            } else if instrument.format == .k42 {
                parseMessage = "Kontakt 4.2 instruments use a different compressed mapping that is not supported yet."
            } else {
                parseMessage = "Unrecognized Kontakt file format."
            }
            return
        }

        isParsing = true
        parseMessage = "Reading instrument mapping…"
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
                    self.parseMessage = nil
                    self.selectedGroupIndex = nil
                    self.playbackMessage = parsed.isMonolith
                        ? "\(parsed.zones.count) zones · \(parsed.groups.count) groups · embedded samples"
                        : "\(parsed.zones.count) zones · \(parsed.groups.count) groups"
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.stateLock.lock()
                    let current = self.parseGeneration
                    self.stateLock.unlock()
                    guard current == generation else { return }
                    self.isParsing = false
                    self.parseMessage = error.localizedDescription
                }
            }
        }
    }

    func play() {
        guard let parsed = parsedInstrument, parsed.format == .k2 else { return }
        stop()

        do {
            try player.prepare()
        } catch {
            playbackMessage = "Audio engine could not start: \(error.localizedDescription)"
            return
        }

        let plan = plannedPlan
        guard !plan.midiNotes.isEmpty else { return }
        let groupIndex = selectedGroupIndex
        let root = rootURL
        let library = selectedInstrument?.library ?? ""
        let length = noteDuration
        let shouldLoop = loop
        let together = !sequential
        let hold = pedalHold

        stateLock.lock()
        playbackGeneration &+= 1
        let generation = playbackGeneration
        stateLock.unlock()

        isPlaying = true
        currentNoteNames = []
        playbackMessage = "Preparing samples…"

        playbackQueue.async { [weak self] in
            guard let self else { return }
            self.runPlayback(
                parsed: parsed,
                plan: plan,
                groupIndex: groupIndex,
                rootURL: root,
                libraryName: library,
                noteLength: length,
                loop: shouldLoop,
                together: together,
                hold: hold,
                generation: generation
            )
        }
    }

    func stop() {
        stateLock.lock()
        playbackGeneration &+= 1
        stateLock.unlock()
        player.stopAll()
        isPlaying = false
        currentNoteNames = []
        playbackMessage = ""
    }

    func testTone() {
        guard let parsed = parsedInstrument else { return }
        stop()
        do {
            try player.prepare()
        } catch {
            playbackMessage = "Audio engine could not start: \(error.localizedDescription)"
            return
        }

        stateLock.lock()
        playbackGeneration &+= 1
        let generation = playbackGeneration
        stateLock.unlock()

        isPlaying = true
        let root = rootURL
        let library = selectedInstrument?.library ?? ""
        let groupIndex = selectedGroupIndex
        let holdForTest = pedalHold
        playbackQueue.async { [weak self] in
            guard let self else { return }
            var wait: TimeInterval = 1.5
            if let zone = self.selectZone(parsed: parsed, groupIndex: groupIndex, midi: 60, velocity: 100),
               let note = self.prepareNote(
                   zone: zone,
                   parsed: parsed,
                   midi: 60,
                   rootURL: root,
                   libraryName: library
               ) {
                self.playNotes([note], duration: 1.4, hold: holdForTest, generation: generation)
                if holdForTest {
                    wait = min(12, max(1.5, note.naturalDuration))
                }
            }
            Thread.sleep(forTimeInterval: wait)
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
        loop: Bool,
        together: Bool,
        hold: Bool,
        generation: UInt64
    ) {
        repeat {
            if !isCurrent(generation) { return }

            if together {
                let duration = max(0.1, noteLength)
                var notes: [PreparedNote] = []
                for midi in plan.midiNotes {
                    if !isCurrent(generation) { return }
                    if let zone = selectZone(parsed: parsed, groupIndex: groupIndex, midi: midi, velocity: 100),
                       let note = prepareNote(
                           zone: zone,
                           parsed: parsed,
                           midi: midi,
                           rootURL: rootURL,
                           libraryName: libraryName
                       ) {
                        notes.append(note)
                    }
                }
                playNotes(notes, duration: duration, hold: hold, generation: generation)
                updateCurrentNotes(plan.names, generation: generation)
                let ring = notes.map(\.naturalDuration).max() ?? 0
                let interval = hold ? min(12, max(noteLength, ring)) : duration + 0.12
                sleepInterruptibly(interval, generation: generation)
            } else {
                var lastNaturalDuration: TimeInterval = 0
                for (index, midi) in plan.midiNotes.enumerated() {
                    if !isCurrent(generation) { return }
                    if let zone = selectZone(parsed: parsed, groupIndex: groupIndex, midi: midi, velocity: 100),
                       let note = prepareNote(
                           zone: zone,
                           parsed: parsed,
                           midi: midi,
                           rootURL: rootURL,
                           libraryName: libraryName
                       ) {
                        lastNaturalDuration = note.naturalDuration
                        playNotes([note], duration: noteLength, hold: hold, generation: generation)
                    }
                    updateCurrentNotes([plan.names[index]], generation: generation)
                    sleepInterruptibly(noteLength, generation: generation)
                }
                sleepInterruptibly(0.1, generation: generation)
                if hold && !loop {
                    sleepInterruptibly(min(12, max(1.0, lastNaturalDuration)), generation: generation)
                }
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

    private func playNotes(_ notes: [PreparedNote], duration: Double, hold: Bool, generation: UInt64) {
        guard !notes.isEmpty, isCurrent(generation) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            for note in notes {
                self.player.play(
                    buffer: note.buffer,
                    rate: note.rate,
                    gain: note.gain,
                    pan: note.pan,
                    duration: duration,
                    hold: hold
                )
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
        }
    }

    private func finishIfCurrent(_ generation: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let current = self.playbackGeneration
            self.stateLock.unlock()
            guard current == generation else { return }
            self.isPlaying = false
            self.currentNoteNames = []
            self.playbackMessage = ""
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        stateLock.lock()
        let current = playbackGeneration
        stateLock.unlock()
        return current == generation
    }

    private func sleepInterruptibly(_ seconds: Double, generation: UInt64) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !isCurrent(generation) { return }
            Thread.sleep(forTimeInterval: min(0.02, deadline.timeIntervalSinceNow))
        }
    }
}

import Foundation

/// The on-disk container variant of a Kontakt instrument.
public enum KontaktFormat: String, Codable, Sendable {
    /// Kontakt 2/3 unencrypted instrument (zlib-compressed XML mapping).
    case k2
    /// Kontakt 4.2 instrument (FastLZ-compressed binary mapping). Not supported yet.
    case k42
    /// Kontakt 5+ container (`hsin`), generally copy-protected.
    case k5
    /// Kontakt 5+ monolith container (samples embedded).
    case k5Monolith
    /// Could not identify the file.
    case unknown

    public var isPlayable: Bool {
        self == .k2
    }

    public var shortLabel: String {
        switch self {
        case .k2: return "K2 · DRM-free"
        case .k42: return "K4.2"
        case .k5: return "K5 · protected"
        case .k5Monolith: return "K5 · protected"
        case .unknown: return "unknown"
        }
    }
}

/// A single instrument file discovered under the Kontakt root.
public struct InstrumentRef: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let library: String
    public let name: String
    public let format: KontaktFormat
    public let size: Int64
    /// False for K2 files that do not contain a readable zlib mapping (for example
    /// some incomplete library copies). They are listed but cannot be auditioned.
    public let hasMapping: Bool

    public init(
        url: URL,
        library: String,
        name: String,
        format: KontaktFormat,
        size: Int64,
        hasMapping: Bool = true
    ) {
        self.id = url.path
        self.url = url
        self.library = library
        self.name = name
        self.format = format
        self.size = size
        self.hasMapping = hasMapping
    }

    public var fileName: String { url.lastPathComponent }

    public var isPlayable: Bool {
        format.isPlayable && hasMapping
    }
}

/// A top-level folder under the Kontakt root.
public struct LibraryRef: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public var instruments: [InstrumentRef]

    public init(url: URL, instruments: [InstrumentRef]) {
        self.id = url.path
        self.name = url.lastPathComponent
        self.url = url
        self.instruments = instruments
    }

    public var playableCount: Int {
        instruments.lazy.filter { $0.isPlayable }.count
    }

    public var protectedCount: Int {
        instruments.lazy.filter { $0.format == .k5 || $0.format == .k5Monolith }.count
    }
}

/// A parsed Kontakt 2 program, reduced to what a preview player needs.
public struct ParsedInstrument: Sendable {
    public let sourceURL: URL
    public let programName: String
    public let format: KontaktFormat
    public let isMonolith: Bool
    public let groups: [K2Group]
    public let zones: [K2Zone]
    public let programTranspose: Int
    public let programVolume: Float
    public let programPan: Float
    public let programTune: Float
    public let monolith: K2MonolithIndex?

    public init(
        sourceURL: URL,
        programName: String,
        format: KontaktFormat,
        isMonolith: Bool,
        groups: [K2Group],
        zones: [K2Zone],
        programTranspose: Int,
        programVolume: Float,
        programPan: Float,
        programTune: Float,
        monolith: K2MonolithIndex? = nil
    ) {
        self.sourceURL = sourceURL
        self.programName = programName
        self.format = format
        self.isMonolith = isMonolith
        self.groups = groups
        self.zones = zones
        self.programTranspose = programTranspose
        self.programVolume = programVolume
        self.programPan = programPan
        self.programTune = programTune
        self.monolith = monolith
    }

    /// Groups that can produce a normal note-on sound. Release-trigger groups are
    /// excluded from the default preview set.
    public var auditionGroups: [K2Group] {
        let normal = groups.filter { !$0.isReleaseTrigger && !$0.isMuted }
        return normal.isEmpty ? groups : normal
    }
}

public struct K2Group: Identifiable, Hashable, Sendable {
    public let id: Int
    public let index: Int
    public let name: String
    public let volume: Float
    public let pan: Float
    public let tune: Float
    public let keyTracking: Bool
    public let isReleaseTrigger: Bool
    public let isMuted: Bool

    public init(
        index: Int,
        name: String,
        volume: Float,
        pan: Float,
        tune: Float,
        keyTracking: Bool,
        isReleaseTrigger: Bool,
        isMuted: Bool
    ) {
        self.id = index
        self.index = index
        self.name = name
        self.volume = volume
        self.pan = pan
        self.tune = tune
        self.keyTracking = keyTracking
        self.isReleaseTrigger = isReleaseTrigger
        self.isMuted = isMuted
    }
}

public struct K2Zone: Identifiable, Hashable, Sendable {
    public let id: Int
    public let index: Int
    public let groupIndex: Int
    public let lowKey: Int
    public let highKey: Int
    public let lowVelocity: Int
    public let highVelocity: Int
    public let rootKey: Int
    public let volume: Float
    public let pan: Float
    public let tune: Float
    public let sampleStart: Int
    /// Negative values mean "from the end"; 0 means "whole sample".
    public let sampleEnd: Int
    public let loopStart: Int
    public let loopLength: Int
    public let loopMode: String
    public let samplePath: String
    public let sampleName: String
    public let isPurged: Bool

    public init(
        index: Int,
        groupIndex: Int,
        lowKey: Int,
        highKey: Int,
        lowVelocity: Int,
        highVelocity: Int,
        rootKey: Int,
        volume: Float,
        pan: Float,
        tune: Float,
        sampleStart: Int,
        sampleEnd: Int,
        loopStart: Int,
        loopLength: Int,
        loopMode: String,
        samplePath: String,
        sampleName: String,
        isPurged: Bool
    ) {
        self.id = index
        self.index = index
        self.groupIndex = groupIndex
        self.lowKey = max(0, lowKey)
        self.highKey = min(127, max(lowKey, highKey))
        self.lowVelocity = max(1, lowVelocity)
        self.highVelocity = min(127, max(lowVelocity, highVelocity))
        self.rootKey = rootKey
        self.volume = volume
        self.pan = pan
        self.tune = tune
        self.sampleStart = max(0, sampleStart)
        self.sampleEnd = sampleEnd
        self.loopStart = max(0, loopStart)
        self.loopLength = max(0, loopLength)
        self.loopMode = loopMode
        self.samplePath = samplePath
        self.sampleName = sampleName
        self.isPurged = isPurged
    }
}

public enum AuditionMode: String, CaseIterable, Identifiable, Sendable {
    case scale = "Scale"
    case chord = "Chord"

    public var id: String { rawValue }
}

/// Musical note lengths offered in the playback panel. Values are fractions of a
/// whole note in 4/4: 1/16, 1/8, 1/4, 1/2, 1, 2, 3, 4.
public enum NoteLength: String, CaseIterable, Identifiable, Sendable {
    case sixteenth = "1/16"
    case eighth = "1/8"
    case quarter = "1/4"
    case half = "1/2"
    case whole = "1"
    case twoWhole = "2"
    case threeWhole = "3"
    case fourWhole = "4"

    public var id: String { rawValue }

    /// Length in whole notes.
    public var wholeNotes: Double {
        switch self {
        case .sixteenth: return 1.0 / 16.0
        case .eighth: return 1.0 / 8.0
        case .quarter: return 1.0 / 4.0
        case .half: return 1.0 / 2.0
        case .whole: return 1
        case .twoWhole: return 2
        case .threeWhole: return 3
        case .fourWhole: return 4
        }
    }

    public func seconds(at bpm: Double) -> TimeInterval {
        let beats = wholeNotes * 4
        return beats * 60.0 / max(1, bpm)
    }
}


public struct ScaleType: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let intervals: [Int]

    public static let all: [ScaleType] = [
        ScaleType(id: "major", name: "Major (Ionian)", intervals: [0, 2, 4, 5, 7, 9, 11]),
        ScaleType(id: "minor", name: "Natural Minor (Aeolian)", intervals: [0, 2, 3, 5, 7, 8, 10]),
        ScaleType(id: "harmonicMinor", name: "Harmonic Minor", intervals: [0, 2, 3, 5, 7, 8, 11]),
        ScaleType(id: "melodicMinor", name: "Melodic Minor", intervals: [0, 2, 3, 5, 7, 9, 11]),
        ScaleType(id: "dorian", name: "Dorian", intervals: [0, 2, 3, 5, 7, 9, 10]),
        ScaleType(id: "phrygian", name: "Phrygian", intervals: [0, 1, 3, 5, 7, 8, 10]),
        ScaleType(id: "lydian", name: "Lydian", intervals: [0, 2, 4, 6, 7, 9, 11]),
        ScaleType(id: "mixolydian", name: "Mixolydian", intervals: [0, 2, 4, 5, 7, 9, 10]),
        ScaleType(id: "locrian", name: "Locrian", intervals: [0, 1, 3, 5, 6, 8, 10]),
        ScaleType(id: "majorPentatonic", name: "Major Pentatonic", intervals: [0, 2, 4, 7, 9]),
        ScaleType(id: "minorPentatonic", name: "Minor Pentatonic", intervals: [0, 3, 5, 7, 10]),
        ScaleType(id: "blues", name: "Blues", intervals: [0, 3, 5, 6, 7, 10]),
        ScaleType(id: "diminishedWH", name: "Diminished (W–H)", intervals: [0, 2, 3, 5, 6, 8, 9, 11]),
        ScaleType(id: "diminishedHW", name: "Diminished (H–W)", intervals: [0, 1, 3, 4, 6, 7, 9, 10]),
        ScaleType(id: "wholeTone", name: "Whole Tone", intervals: [0, 2, 4, 6, 8, 10]),
        ScaleType(id: "chromatic", name: "Chromatic", intervals: Array(0...11))
    ]
}

public struct ChordType: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let intervals: [Int]

    public static let all: [ChordType] = [
        ChordType(id: "major", name: "Major", intervals: [0, 4, 7]),
        ChordType(id: "minor", name: "Minor", intervals: [0, 3, 7]),
        ChordType(id: "dim", name: "Diminished", intervals: [0, 3, 6]),
        ChordType(id: "aug", name: "Augmented", intervals: [0, 4, 8]),
        ChordType(id: "sus2", name: "Sus2", intervals: [0, 2, 7]),
        ChordType(id: "sus4", name: "Sus4", intervals: [0, 5, 7]),
        ChordType(id: "maj7", name: "Major 7", intervals: [0, 4, 7, 11]),
        ChordType(id: "min7", name: "Minor 7", intervals: [0, 3, 7, 10]),
        ChordType(id: "dom7", name: "Dominant 7", intervals: [0, 4, 7, 10]),
        ChordType(id: "dim7", name: "Diminished 7", intervals: [0, 3, 6, 9]),
        ChordType(id: "halfDim7", name: "Half-diminished 7", intervals: [0, 3, 6, 10]),
        ChordType(id: "minMaj7", name: "Minor–Major 7", intervals: [0, 3, 7, 11]),
        ChordType(id: "six", name: "Major 6", intervals: [0, 4, 7, 9]),
        ChordType(id: "min6", name: "Minor 6", intervals: [0, 3, 7, 9]),
        ChordType(id: "add9", name: "Add 9", intervals: [0, 4, 7, 14]),
        ChordType(id: "nine", name: "Dominant 9", intervals: [0, 4, 7, 10, 14]),
        ChordType(id: "min9", name: "Minor 9", intervals: [0, 3, 7, 10, 14]),
        ChordType(id: "sevenSus4", name: "7 Sus4", intervals: [0, 5, 7, 10])
    ]
}

public enum NoteNaming {
    public static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    public static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    public static func name(pitchClass: Int, octave: Int) -> String {
        "\(sharpNames[((pitchClass % 12) + 12) % 12])\(octave)"
    }

    public static func name(midi: Int) -> String {
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return "\(sharpNames[pc])\(octave)"
    }

    public static func midi(pitchClass: Int, octave: Int) -> Int {
        (octave + 1) * 12 + pitchClass
    }
}

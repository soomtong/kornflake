import Foundation

public enum Scale: String, CaseIterable, Identifiable, Sendable {
    case major
    case naturalMinor
    case harmonicMinor
    case melodicMinor
    case majorPentatonic
    case minorPentatonic
    case blues
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case locrian
    case wholeTone
    case diminishedWholeHalf
    case diminishedHalfWhole

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .major: "장음계 (Major)"
        case .naturalMinor: "자연 단음계 (Natural Minor)"
        case .harmonicMinor: "화성 단음계 (Harmonic Minor)"
        case .melodicMinor: "선율 단음계 (Melodic Minor)"
        case .majorPentatonic: "펜타토닉 장음계 (Major Pentatonic)"
        case .minorPentatonic: "펜타토닉 단음계 (Minor Pentatonic)"
        case .blues: "블루스 (Blues)"
        case .dorian: "도리안 (Dorian)"
        case .phrygian: "프리지안 (Phrygian)"
        case .lydian: "리디안 (Lydian)"
        case .mixolydian: "믹솔리디안 (Mixolydian)"
        case .locrian: "로크리안 (Locrian)"
        case .wholeTone: "온음계 (Whole Tone)"
        case .diminishedWholeHalf: "디미니시드 Whole-Half"
        case .diminishedHalfWhole: "디미니시드 Half-Whole"
        }
    }

    /// Semitone offsets from the root, ascending, without the octave.
    public var intervals: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: [0, 2, 3, 5, 7, 9, 11]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        case .blues: [0, 3, 5, 6, 7, 10]
        case .dorian: [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: [0, 1, 3, 5, 7, 8, 10]
        case .lydian: [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: [0, 2, 4, 5, 7, 9, 10]
        case .locrian: [0, 1, 3, 5, 6, 8, 10]
        case .wholeTone: [0, 2, 4, 6, 8, 10]
        case .diminishedWholeHalf: [0, 2, 3, 5, 6, 8, 9, 11]
        case .diminishedHalfWhole: [0, 1, 3, 4, 6, 7, 9, 10]
        }
    }
}

public enum Chord: String, CaseIterable, Identifiable, Sendable {
    case major
    case minor
    case diminished
    case augmented
    case sus2
    case sus4
    case power5
    case major6
    case minor6
    case major7
    case minor7
    case dominant7
    case diminished7
    case halfDiminished7
    case add9
    case dominant9

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .major: "메이저 (Major)"
        case .minor: "마이너 (Minor)"
        case .diminished: "디미니시드 (Diminished)"
        case .augmented: "어그먼티드 (Augmented)"
        case .sus2: "Sus2"
        case .sus4: "Sus4"
        case .power5: "파워 5 (Power 5)"
        case .major6: "메이저 6 (Major 6)"
        case .minor6: "마이너 6 (Minor 6)"
        case .major7: "메이저 7 (Major 7)"
        case .minor7: "마이너 7 (Minor 7)"
        case .dominant7: "도미넌트 7 (Dominant 7)"
        case .diminished7: "디미니시드 7 (Diminished 7)"
        case .halfDiminished7: "하프 디미니시드 7 (m7b5)"
        case .add9: "애드 9 (Add 9)"
        case .dominant9: "도미넌트 9 (Dominant 9)"
        }
    }

    /// Semitone offsets from the root, ascending.
    public var intervals: [Int] {
        switch self {
        case .major: [0, 4, 7]
        case .minor: [0, 3, 7]
        case .diminished: [0, 3, 6]
        case .augmented: [0, 4, 8]
        case .sus2: [0, 2, 7]
        case .sus4: [0, 5, 7]
        case .power5: [0, 7]
        case .major6: [0, 4, 7, 9]
        case .minor6: [0, 3, 7, 9]
        case .major7: [0, 4, 7, 11]
        case .minor7: [0, 3, 7, 10]
        case .dominant7: [0, 4, 7, 10]
        case .diminished7: [0, 3, 6, 9]
        case .halfDiminished7: [0, 3, 6, 10]
        case .add9: [0, 4, 7, 14]
        case .dominant9: [0, 4, 7, 10, 14]
        }
    }
}

public enum SoundKind: String, CaseIterable, Identifiable, Sendable {
    case scale
    case chord

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scale: "스케일"
        case .chord: "코드"
        }
    }
}

public enum SoundSource: Equatable, Sendable {
    case scale(Scale)
    case chord(Chord)

    public var kind: SoundKind {
        switch self {
        case .scale: .scale
        case .chord: .chord
        }
    }

    public var intervals: [Int] {
        switch self {
        case .scale(let scale): scale.intervals
        case .chord(let chord): chord.intervals
        }
    }

    public var displayName: String {
        switch self {
        case .scale(let scale): scale.displayName
        case .chord(let chord): chord.displayName
        }
    }
}

public enum AuditionMode: String, CaseIterable, Identifiable, Sendable {
    case sequence
    case simultaneous

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sequence: "순차 재생"
        case .simultaneous: "동시 재생"
        }
    }
}

public struct AuditionRequest: Equatable, Sendable {
    public var rootPitchClass: Int
    public var octave: Int
    public var source: SoundSource
    public var mode: AuditionMode

    public init(
        rootPitchClass: Int = 0,
        octave: Int = 4,
        source: SoundSource = .scale(.major),
        mode: AuditionMode = .sequence
    ) {
        self.rootPitchClass = rootPitchClass
        self.octave = octave
        self.source = source
        self.mode = mode
    }

    /// MIDI note number of the root. C4 is 60.
    public var rootMIDINote: Int {
        let pitchClass = ((rootPitchClass % 12) + 12) % 12
        return 12 * (octave + 1) + pitchClass
    }

    /// Notes to send, ascending. A scale gets its octave note in sequence mode;
    /// a simultaneous scale is voiced as a cluster without the doubled octave.
    public var notes: [UInt8] {
        var intervals = source.intervals
        if source.kind == .scale && mode == .sequence {
            intervals.append(12)
        }
        return intervals
            .map { rootMIDINote + $0 }
            .filter { (0...127).contains($0) }
            .map(UInt8.init)
    }
}

public struct AuditionTiming: Equatable, Sendable {
    public var bpm: Double
    public var gate: Double

    public init(bpm: Double, gate: Double) {
        self.bpm = min(max(bpm, 20), 300)
        self.gate = min(max(gate, 0.05), 0.98)
    }

    public var stepSeconds: Double { 60.0 / bpm }
    public var noteSeconds: Double { stepSeconds * gate }
    public var gapSeconds: Double { max(0.01, stepSeconds - noteSeconds) }
}

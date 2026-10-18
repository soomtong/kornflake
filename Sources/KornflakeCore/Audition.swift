import Foundation

public struct AuditionPlan: Sendable {
    public let midiNotes: [Int]
    public let names: [String]

    public init(midiNotes: [Int]) {
        self.midiNotes = midiNotes
        self.names = midiNotes.map { NoteNaming.name(midi: $0) }
    }
}

public enum AuditionBuilder {
    public static func makePlan(
        mode: AuditionMode,
        rootPitchClass: Int,
        octave: Int,
        scale: ScaleType,
        chord: ChordType,
        descending: Bool,
        twoOctaves: Bool
    ) -> AuditionPlan {
        let root = NoteNaming.midi(pitchClass: rootPitchClass, octave: octave)
        var notes: [Int]

        switch mode {
        case .scale:
            let repeats = twoOctaves ? 2 : 1
            notes = []
            for octaveIndex in 0..<repeats {
                for interval in scale.intervals {
                    notes.append(root + interval + octaveIndex * 12)
                }
            }
            // Close the scale on the root.
            notes.append(root + repeats * 12)
        case .chord:
            notes = chord.intervals.map { root + $0 }
        }

        if descending {
            notes.reverse()
        }
        return AuditionPlan(midiNotes: notes.map { min(127, max(0, $0)) })
    }
}

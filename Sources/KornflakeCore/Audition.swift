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
        twoOctaves: Bool,
        extendUp: Int = 0,
        extendDown: Int = 0,
        upDown: Bool = false,
        seamless: Bool = false
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
            if upDown {
                // Up then back down (or down then up when descending); the turning note is
                // played once. `seamless` drops the closing note so a loop does not repeat it.
                let first = descending ? Array(notes.reversed()) : notes
                let second = Array(first.reversed().dropFirst())
                notes = first + second
                if seamless { notes.removeLast() }
            }
        case .chord:
            notes = chord.intervals.map { root + $0 }
        }

        if descending && !(mode == .scale && upDown) {
            notes.reverse()
        }
        var clamped = notes.map { min(127, max(0, $0)) }
        if mode == .chord {
            clamped = widened(clamped, chord: chord, root: root, up: extendUp, down: extendDown)
        }
        return AuditionPlan(midiNotes: clamped)
    }

    /// Widens a chord by continuing its tone pattern above and below. C major (C E G)
    /// extended up by 2 adds C E one octave higher; extended down by 1 adds G below.
    /// Notes outside the MIDI range are dropped, not clamped, so no pitch is doubled.
    private static func widened(_ notes: [Int], chord: ChordType, root: Int, up: Int, down: Int) -> [Int] {
        let intervals = chord.intervals.sorted()
        let count = intervals.count
        guard count > 0, up > 0 || down > 0 else { return notes }

        func tone(at index: Int) -> Int {
            // Floor division so negative indices wrap into the octave below.
            let octave = Int((Double(index) / Double(count)).rounded(.down))
            let position = index - octave * count
            return root + intervals[position] + 12 * octave
        }

        let below = (0..<max(0, down)).map { tone(at: -($0 + 1)) }
        let above = (0..<max(0, up)).map { tone(at: count + $0) }
        let extra = (below + above).filter { (0...127).contains($0) }
        // Descending plans are played top-down, so keep the whole set in playing order.
        let all = Set(notes + extra).sorted()
        let descending = notes.count > 1 && notes[0] > notes[notes.count - 1]
        return descending ? all.reversed() : all
    }
}

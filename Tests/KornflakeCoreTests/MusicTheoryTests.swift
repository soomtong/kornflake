import XCTest
@testable import KornflakeCore

final class MusicTheoryTests: XCTestCase {
    func testMajorScaleSequenceIncludesOctave() {
        let request = AuditionRequest(
            rootPitchClass: 0,
            octave: 4,
            source: .scale(.major),
            mode: .sequence
        )
        XCTAssertEqual(request.rootMIDINote, 60)
        XCTAssertEqual(request.notes, [60, 62, 64, 65, 67, 69, 71, 72])
    }

    func testScaleSimultaneousOmitsDoubledOctave() {
        let request = AuditionRequest(
            rootPitchClass: 0,
            octave: 4,
            source: .scale(.major),
            mode: .simultaneous
        )
        XCTAssertEqual(request.notes, [60, 62, 64, 65, 67, 69, 71])
    }

    func testMinorPentatonic() {
        let request = AuditionRequest(
            rootPitchClass: 9,
            octave: 3,
            source: .scale(.minorPentatonic),
            mode: .sequence
        )
        XCTAssertEqual(request.rootMIDINote, 57)
        XCTAssertEqual(request.notes, [57, 60, 62, 64, 67, 69])
    }

    func testChords() {
        XCTAssertEqual(
            AuditionRequest(source: .chord(.major), mode: .sequence).notes,
            [60, 64, 67]
        )
        XCTAssertEqual(
            AuditionRequest(source: .chord(.add9), mode: .simultaneous).notes,
            [60, 64, 67, 74]
        )
        XCTAssertEqual(
            AuditionRequest(source: .chord(.diminished7), mode: .simultaneous).notes,
            [60, 63, 66, 69]
        )
    }

    func testPitchClassNormalization() {
        XCTAssertEqual(AuditionRequest(rootPitchClass: -1, octave: 4).rootMIDINote, 71)
        XCTAssertEqual(AuditionRequest(rootPitchClass: 12, octave: 4).rootMIDINote, 60)
        XCTAssertEqual(AuditionRequest(rootPitchClass: 13, octave: 4).rootMIDINote, 61)
    }

    func testNotesAreClampedToMIDIRange() {
        let request = AuditionRequest(
            rootPitchClass: 0,
            octave: 9,
            source: .scale(.major),
            mode: .sequence
        )
        XCTAssertEqual(request.rootMIDINote, 120)
        XCTAssertEqual(request.notes, [120, 122, 124, 125, 127])
        XCTAssertTrue(request.notes.allSatisfy { $0 <= 127 })
    }

    func testEveryScaleAndChordStartsAtRootAndAscends() {
        for scale in Scale.allCases {
            let intervals = scale.intervals
            XCTAssertEqual(intervals.first, 0, scale.rawValue)
            XCTAssertEqual(intervals, intervals.sorted(), scale.rawValue)
            XCTAssertEqual(Set(intervals).count, intervals.count, scale.rawValue)
        }
        for chord in Chord.allCases {
            let intervals = chord.intervals
            XCTAssertEqual(intervals.first, 0, chord.rawValue)
            XCTAssertEqual(intervals, intervals.sorted(), chord.rawValue)
            XCTAssertEqual(Set(intervals).count, intervals.count, chord.rawValue)
        }
    }

    func testTimingClampsAndDerives() {
        let timing = AuditionTiming(bpm: 120, gate: 0.5)
        XCTAssertEqual(timing.stepSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(timing.noteSeconds, 0.25, accuracy: 0.0001)
        XCTAssertEqual(timing.gapSeconds, 0.25, accuracy: 0.0001)

        XCTAssertEqual(AuditionTiming(bpm: 1, gate: 0).bpm, 20)
        XCTAssertEqual(AuditionTiming(bpm: 999, gate: 2).bpm, 300)
        XCTAssertEqual(AuditionTiming(bpm: 120, gate: 0).gate, 0.05)
        XCTAssertEqual(AuditionTiming(bpm: 120, gate: 2).gate, 0.98)
    }
}

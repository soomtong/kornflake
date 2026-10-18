import Foundation
import KornflakeCore

/// Drives the MIDI stream on the main actor. Sleeps are async, so the UI stays
/// responsive while notes are scheduled.
@MainActor
final class AuditionPlayer {
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var activeNotes: Set<UInt8> = []
    private var midi: MIDIOutput?
    private var channel: UInt8 = 0

    var onNotesChanged: ((Set<UInt8>) -> Void)?
    var onFinished: (() -> Void)?

    func play(
        notes: [UInt8],
        mode: AuditionMode,
        timing: AuditionTiming,
        loop: Bool,
        midi: MIDIOutput,
        channel: UInt8
    ) {
        stop()
        guard !notes.isEmpty else {
            onFinished?()
            return
        }

        self.midi = midi
        self.channel = channel
        let id = UUID()
        runID = id
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(notes: notes, mode: mode, timing: timing, loop: loop, id: id)
        }
    }

    func stop() {
        runID = UUID()
        task?.cancel()
        task = nil
        releaseActiveNotes()
        midi?.allNotesOff(channel: channel)
        onFinished?()
    }

    private func run(
        notes: [UInt8],
        mode: AuditionMode,
        timing: AuditionTiming,
        loop: Bool,
        id: UUID
    ) async {
        defer {
            releaseActiveNotes()
            if !Task.isCancelled, runID == id {
                task = nil
                onFinished?()
            }
        }

        switch mode {
        case .sequence:
            repeat {
                for note in notes {
                    guard !Task.isCancelled else { return }
                    noteOn(note)
                    let slept = await sleep(timing.noteSeconds)
                    noteOff(note)
                    guard slept, !Task.isCancelled else { return }
                    guard await sleep(timing.gapSeconds) else { return }
                }
            } while loop

        case .simultaneous:
            repeat {
                guard !Task.isCancelled else { return }
                for note in notes {
                    noteOn(note)
                }
                let slept = await sleep(timing.noteSeconds)
                for note in notes {
                    noteOff(note)
                }
                guard slept, !Task.isCancelled else { return }
                if loop {
                    let repeatGap = max(0.05, timing.stepSeconds * 2 - timing.noteSeconds)
                    guard await sleep(repeatGap) else { return }
                }
            } while loop
        }
    }

    private func noteOn(_ note: UInt8) {
        midi?.noteOn(note, velocity: 100, channel: channel)
        activeNotes.insert(note)
        onNotesChanged?(activeNotes)
    }

    private func noteOff(_ note: UInt8) {
        midi?.noteOff(note, channel: channel)
        activeNotes.remove(note)
        onNotesChanged?(activeNotes)
    }

    private func releaseActiveNotes() {
        for note in activeNotes {
            midi?.noteOff(note, channel: channel)
        }
        activeNotes.removeAll()
        onNotesChanged?([])
    }

    private func sleep(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

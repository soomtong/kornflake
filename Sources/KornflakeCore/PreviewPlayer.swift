import Foundation
import AVFoundation

/// A small polyphonic preview voice pool. It intentionally implements only what is
/// needed for auditioning scales and chords: sample playback, pitch via varispeed,
/// gain/pan, and a timed note-off with a fade.
public final class PreviewPlayer: @unchecked Sendable {
    private final class Voice {
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        let mixer = AVAudioMixerNode()
        var generation: UInt64 = 0
        var busyUntil = Date.distantPast
    }

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voices: [Voice] = []
    private var prepared = false
    private let lock = NSLock()
    /// Note-off timers run here instead of on the main queue so UI work cannot delay them.
    private let timing = DispatchQueue(label: "kornflake.preview.timing", qos: .userInteractive)

    public init() {
        self.format = AudioSampleLoader.shared.engineFormat
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return prepared && engine.isRunning
    }

    public func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !prepared else {
            if !engine.isRunning { try engine.start() }
            return
        }

        for _ in 0..<24 {
            let voice = Voice()
            engine.attach(voice.player)
            engine.attach(voice.varispeed)
            engine.attach(voice.mixer)
            engine.connect(voice.player, to: voice.varispeed, format: format)
            engine.connect(voice.varispeed, to: voice.mixer, format: format)
            engine.connect(voice.mixer, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        engine.prepare()
        try engine.start()
        prepared = true
    }

    /// Plays one note. `rate` is a sampler-style speed/pitch ratio.
    /// Safe to call from any thread; voice state and node calls are serialized by the lock.
    public func play(
        buffer: AVAudioPCMBuffer,
        rate: Double,
        gain: Float,
        pan: Float,
        duration: TimeInterval,
        hold: Bool = false
    ) {
        guard buffer.frameLength > 0 else { return }
        let clampedRate = min(max(rate, 0.25), 4.0)
        let noteBuffer: AVAudioPCMBuffer
        let playbackDuration: TimeInterval
        if hold {
            noteBuffer = buffer
            playbackDuration = Double(buffer.frameLength) / format.sampleRate / clampedRate
        } else {
            noteBuffer = makeNoteBuffer(from: buffer, rate: clampedRate, duration: duration)
            playbackDuration = min(
                duration,
                Double(noteBuffer.frameLength) / format.sampleRate / clampedRate
            )
        }

        lock.lock()
        guard let voice = allocateVoiceLocked() else {
            lock.unlock()
            return
        }
        voice.generation &+= 1
        let generation = voice.generation
        voice.player.stop()
        voice.varispeed.rate = Float(clampedRate)
        voice.mixer.outputVolume = min(max(gain, 0), 1.5)
        voice.mixer.pan = min(max(pan, -1), 1)
        voice.player.volume = 1
        voice.player.scheduleBuffer(noteBuffer, at: nil, options: [], completionHandler: nil)
        voice.player.play()
        voice.busyUntil = Date().addingTimeInterval(playbackDuration + 0.1)
        lock.unlock()

        let stopAt = playbackDuration + 0.03
        timing.asyncAfter(deadline: .now() + stopAt) { [weak self, weak voice] in
            guard let self, let voice else { return }
            self.lock.lock()
            if voice.generation == generation {
                voice.player.stop()
            }
            self.lock.unlock()
        }
    }

    public func stopAll() {
        lock.lock()
        for voice in voices {
            voice.generation &+= 1
            voice.player.stop()
            voice.busyUntil = .distantPast
        }
        lock.unlock()
    }

    /// Caller must hold `lock`.
    private func allocateVoiceLocked() -> Voice? {
        let now = Date()
        if let free = voices.first(where: { $0.busyUntil < now }) {
            return free
        }
        return voices.min(by: { $0.busyUntil < $1.busyUntil })
    }

    private func makeNoteBuffer(from source: AVAudioPCMBuffer, rate: Double, duration: TimeInterval) -> AVAudioPCMBuffer {
        let targetFrames = Int(min(
            Double(source.frameLength),
            duration * format.sampleRate * rate
        ))
        guard targetFrames > 0, targetFrames < Int(source.frameLength) else {
            return source
        }
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(targetFrames)),
              let sourceData = source.floatChannelData,
              let outputData = output.floatChannelData else {
            return source
        }
        output.frameLength = AVAudioFrameCount(targetFrames)
        for channel in 0..<Int(format.channelCount) {
            memcpy(outputData[channel], sourceData[channel], targetFrames * MemoryLayout<Float>.size)
        }

        let fadeFrames = min(targetFrames, Int(format.sampleRate * 0.02))
        if fadeFrames > 1 {
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<fadeFrames {
                    let index = targetFrames - fadeFrames + i
                    outputData[channel][index] *= 1 - Float(i) / Float(fadeFrames - 1)
                }
            }
        }
        return output
    }
}

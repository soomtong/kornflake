import Foundation
import AVFoundation

/// Loads WAV/AIFF samples, converts them to a single engine format, trims them to the
/// zone's sample range, and applies short fades.
public final class AudioSampleLoader: @unchecked Sendable {
    public static let shared = AudioSampleLoader()

    public static let sampleRate: Double = 44_100
    public static let channelCount: AVAudioChannelCount = 2

    private let format: AVAudioFormat
    private let lock = NSLock()
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var order: [String] = []
    private let cacheLimit = 32

    public init() {
        self.format = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: Self.channelCount
        )!
    }

    public var engineFormat: AVAudioFormat { format }

    public func load(url: URL, startFrame: Int, endFrame: Int) throws -> AVAudioPCMBuffer {
        let key = cacheKey(url: url, start: startFrame, end: endFrame)
        lock.lock()
        if let cached = cache[key] {
            touch(key)
            lock.unlock()
            return cached
        }
        lock.unlock()

        let buffer = try decode(url: url, startFrame: startFrame, endFrame: endFrame)

        lock.lock()
        cache[key] = buffer
        touch(key)
        while order.count > cacheLimit {
            let oldest = order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        lock.unlock()
        return buffer
    }

    private func decode(url: URL, startFrame: Int, endFrame: Int) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else {
            throw SampleLoadError.emptyFile(url.lastPathComponent)
        }

        // Read only the part of the sample that can actually be heard. This matters
        // for monolith samples that can be several minutes long.
        var start = min(max(0, startFrame), totalFrames - 1)
        var end: Int
        if endFrame > 0 {
            end = min(endFrame, totalFrames)
        } else if endFrame < 0 {
            end = max(start + 1, totalFrames + endFrame)
        } else {
            end = totalFrames
        }
        let maximumSourceFrames = Int(sourceFormat.sampleRate * 12)
        end = min(max(start + 1, end), start + maximumSourceFrames)

        let frameCount = AVAudioFrameCount(end - start)
        file.framePosition = AVAudioFramePosition(start)
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw SampleLoadError.cannotAllocate
        }
        try file.read(into: source, frameCount: frameCount)

        let converted: AVAudioPCMBuffer
        if sourceFormat.sampleRate == format.sampleRate && sourceFormat.channelCount == format.channelCount {
            converted = source
        } else {
            converted = try convert(source, from: sourceFormat)
        }

        applyFades(buffer: converted)
        return converted
    }

    private func convert(_ source: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: sourceFormat, to: format) else {
            throw SampleLoadError.cannotConvert
        }
        let ratio = format.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw SampleLoadError.cannotAllocate
        }

        var error: NSError?
        var supplied = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return source
        }

        let result = converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        if result == .error {
            throw SampleLoadError.conversionFailed(error?.localizedDescription ?? "unknown")
        }
        if output.frameLength == 0 {
            output.frameLength = min(capacity, AVAudioFrameCount(Double(source.frameLength) * ratio))
        }
        return output
    }

    private func applyFades(buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 2 else { return }
        let fadeIn = min(frames, Int(format.sampleRate * 0.004))
        let fadeOut = min(frames, Int(format.sampleRate * 0.025))

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            if fadeIn > 1 {
                for i in 0..<fadeIn {
                    samples[i] *= Float(i) / Float(fadeIn - 1)
                }
            }
            if fadeOut > 1 {
                for i in 0..<fadeOut {
                    let index = frames - fadeOut + i
                    samples[index] *= 1 - Float(i) / Float(fadeOut - 1)
                }
            }
        }
    }

    private func cacheKey(url: URL, start: Int, end: Int) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(mtime)|\(start)|\(end)"
    }

    private func touch(_ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}

public enum SampleLoadError: LocalizedError {
    case emptyFile(String)
    case cannotAllocate
    case cannotConvert
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyFile(let name): return "Sample is empty: \(name)"
        case .cannotAllocate: return "Could not allocate an audio buffer."
        case .cannotConvert: return "This sample format cannot be converted."
        case .conversionFailed(let detail): return "Audio conversion failed: \(detail)"
        }
    }
}

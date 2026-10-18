import Foundation
import CryptoKit

/// Lightweight index of the samples embedded in a Kontakt 2 monolith (.nki).
/// The actual audio is extracted lazily into the app cache.
public struct K2MonolithIndex: Sendable {
    public struct SampleExtent: Sendable {
        public let offset: UInt64
        public let length: Int
        public let name: String
    }

    public let sourceURL: URL
    public let extentsByName: [String: SampleExtent]
    public let rawSampleNames: Set<String>

    private static let nkrHeader: UInt32 = 0x5E70_AC54
    private static let wallpaper: UInt32 = 0x2AE9_05FA
    private static let nkiHeader: UInt32 = 0x4916_E63C
    private static let sampleHeader: UInt32 = 0x16CC_F80A
    private static let rawSampleHeader: UInt32 = 0x0040_179F

    struct DirectoryEntry {
        let name: String
        let type: Int
        let pointer: UInt64
    }

    static func read(url: URL) throws -> K2MonolithIndex {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        var position: UInt64 = 170
        var directories: [[DirectoryEntry]] = []
        var extents: [SampleExtent] = []
        var rawNames = Set<String>()

        func read(at offset: UInt64, count: Int) throws -> Data {
            guard offset <= fileSize else { return Data() }
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: min(count, Int(fileSize - offset))) ?? Data()
        }

        while position + 4 <= fileSize {
            let magicData = try read(at: position, count: 4)
            guard magicData.count == 4 else { break }
            let magic = magicData.readUInt32(at: 0, littleEndian: true)

            switch magic {
            case nkrHeader:
                var p = position + 4
                let header = try read(at: p, count: 18)
                guard header.count >= 18 else { throw K2Error.monolithUnreadable }
                // 10 unknown bytes, then item count, then 4 bytes of padding.
                let count = header.readUInt32(at: 10, littleEndian: true)
                p += 18
                var entries: [DirectoryEntry] = []
                for _ in 0..<count {
                    let entryHeader = try read(at: p, count: 8)
                    guard entryHeader.count == 8 else { break }
                    let length = Int(entryHeader.readUInt16(at: 0, littleEndian: true))
                    let pointer = UInt64(entryHeader.readUInt32(at: 2, littleEndian: true))
                    let type = Int(entryHeader.readUInt16(at: 6, littleEndian: true))
                    p += 8
                    guard length >= 8 else { break }
                    let content = try read(at: p, count: length - 8)
                    p += UInt64(length - 8)
                    let name = String(data: content, encoding: .utf16LittleEndian)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
                    entries.append(DirectoryEntry(name: name, type: type, pointer: pointer))
                }
                directories.append(entries)
                position = p

            case wallpaper:
                let header = try read(at: position + 4, count: 18)
                guard header.count >= 18 else { throw K2Error.monolithUnreadable }
                let length = header.readUInt64(at: 10, littleEndian: true)
                // The length comes from the file; a corrupt value must not trap on overflow.
                let (next, overflow) = (position + 4 + 18).addingReportingOverflow(length)
                guard !overflow, next <= fileSize else { throw K2Error.monolithUnreadable }
                position = next

            case nkiHeader:
                // The mapping XML starts here (after a 27-byte NKI header + 170-byte K2 header).
                position = fileSize

            case sampleHeader:
                let header = try read(at: position + 4, count: 27)
                guard header.count >= 27 else { throw K2Error.monolithUnreadable }
                let length = Int(header.readUInt32(at: 15, littleEndian: true))
                let dataOffset = position + 4 + 27
                // A block that runs past the end of the file is truncated or corrupt. Keep the
                // samples found so far and stop indexing instead of recording an unreadable extent.
                guard dataOffset + UInt64(length) <= fileSize else {
                    position = fileSize
                    continue
                }
                extents.append(SampleExtent(offset: dataOffset, length: length, name: ""))
                position = dataOffset + UInt64(length)

            case rawSampleHeader:
                rawNames.insert("raw")
                if let next = try findNextSampleBlock(handle: handle, from: position + 4, fileSize: fileSize) {
                    position = next
                } else {
                    position = fileSize
                }

            default:
                position = fileSize
            }
        }

        // Sample directory entries (type 2) are in the same order as the sample blocks.
        let sampleNames = directories
            .flatMap { $0 }
            .filter {
                $0.type == 2
                    || $0.name.lowercased().hasSuffix(".wav")
                    || $0.name.lowercased().hasSuffix(".ncw")
                    || $0.name.lowercased().hasSuffix(".aif")
                    || $0.name.lowercased().hasSuffix(".aiff")
            }
            .map(\.name)

        var byName: [String: SampleExtent] = [:]
        for (index, extent) in extents.enumerated() {
            let name = index < sampleNames.count ? sampleNames[index] : "Sample \(index + 1).wav"
            var named = SampleExtent(offset: extent.offset, length: extent.length, name: name)
            if named.length == 0 { continue }
            let key = name.lowercased()
            if byName[key] == nil {
                byName[key] = named
            }
            // Also make the bare basename available.
            let base = (name as NSString).lastPathComponent.lowercased()
            if byName[base] == nil {
                named = SampleExtent(offset: extent.offset, length: extent.length, name: name)
                byName[base] = named
            }
        }

        return K2MonolithIndex(sourceURL: url, extentsByName: byName, rawSampleNames: rawNames)
    }

    private static func findNextSampleBlock(handle: FileHandle, from start: UInt64, fileSize: UInt64) throws -> UInt64? {
        let needle: [UInt8] = [0x0A, 0xF8, 0xCC, 0x16]
        let chunkSize = 1 << 20
        var position = start
        while position + 4 < fileSize {
            try handle.seek(toOffset: position)
            guard let chunk = try handle.read(upToCount: min(chunkSize, Int(fileSize - position))), !chunk.isEmpty else {
                break
            }
            let bytes = [UInt8](chunk)
            if bytes.count >= 4 {
                for i in 0...(bytes.count - 4) where bytes[i] == needle[0] && bytes[i + 1] == needle[1] && bytes[i + 2] == needle[2] && bytes[i + 3] == needle[3] {
                    return position + UInt64(i)
                }
            }
            position += UInt64(max(1, bytes.count - 3))
        }
        return nil
    }

    /// Extract a sample from the monolith into the cache and return a playable file URL.
    public func sampleURL(named name: String) throws -> URL {
        let base = (name as NSString).lastPathComponent
        let key = name.lowercased()
        guard let extent = extentsByName[key] ?? extentsByName[base.lowercased()] else {
            throw K2Error.sampleNotFound(name)
        }

        let fileManager = FileManager.default
        let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Kornflake", isDirectory: true)
            .appendingPathComponent("Monolith", isDirectory: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let modified = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let digest = SHA256.hash(data: Data("\(sourceURL.path)|\(modified)|\(key)".utf8))
        let prefix = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        let safeName = base.replacingOccurrences(of: "/", with: "_")
        let destination = cacheRoot.appendingPathComponent("\(prefix)-\(safeName)")

        if fileManager.fileExists(atPath: destination.path),
           let attrs = try? fileManager.attributesOfItem(atPath: destination.path),
           (attrs[.size] as? NSNumber)?.intValue == extent.length {
            return destination
        }

        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard extent.offset + UInt64(extent.length) <= fileSize else { throw K2Error.monolithUnreadable }
        try handle.seek(toOffset: extent.offset)

        // Copy in chunks so a multi-minute sample never has to sit in memory as a whole.
        let temporary = destination.appendingPathExtension("tmp")
        try? fileManager.removeItem(at: temporary)
        guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
            throw K2Error.monolithUnreadable
        }
        let output = try FileHandle(forWritingTo: temporary)
        var copied = 0
        do {
            let chunkSize = 4 << 20
            while copied < extent.length {
                let want = min(chunkSize, extent.length - copied)
                guard let chunk = try handle.read(upToCount: want), !chunk.isEmpty else {
                    throw K2Error.monolithUnreadable
                }
                try output.write(contentsOf: chunk)
                copied += chunk.count
            }
            try output.close()
        } catch {
            try? output.close()
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        return destination
    }
}

extension Data {
    func readUInt64(at offset: Int, littleEndian: Bool) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        var value: UInt64 = 0
        if littleEndian {
            for i in (0..<8).reversed() {
                value = (value << 8) | UInt64(self[startIndex + offset + i])
            }
        } else {
            for i in 0..<8 {
                value = (value << 8) | UInt64(self[startIndex + offset + i])
            }
        }
        return value
    }
}

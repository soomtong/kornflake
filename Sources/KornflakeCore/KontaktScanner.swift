import Foundation

public enum KontaktScanner {
    public struct Progress: Sendable {
        public let library: String
        public let instruments: Int
        public let fraction: Double
    }

    public static func inspect(url: URL) -> (format: KontaktFormat, hasMapping: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 176),
              data.count >= 16 else {
            return (.unknown, false)
        }
        try? handle.close()

        let format = detectFormat(data: data)
        guard format == .k2 else { return (format, false) }

        let littleEndian = data.readUInt32BE(at: 0) == 0x1290_A87F
        let isMonolith = data.readUInt32(at: 42, littleEndian: littleEndian) == 1
        if isMonolith { return (format, true) }

        let bytes = [UInt8](data)
        return (format, K2Compression.looksLikeZlibHeader(bytes, at: 170))
    }

    public static func detectFormat(url: URL) -> KontaktFormat {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 24),
              data.count >= 16 else {
            return .unknown
        }
        try? handle.close()
        return detectFormat(data: data)
    }

    private static func detectFormat(data: Data) -> KontaktFormat {
        if data.count >= 16, data.subdata(in: 12..<16) == Data("hsin".utf8) {
            return .k5
        }

        let magic = data.readUInt32BE(at: 0)
        switch magic {
        case 0x1290_A87F, 0x7FA8_9012:
            let version = data.readUInt16(at: 8, littleEndian: magic == 0x1290_A87F)
            switch version {
            case 0x0100: return .k2
            case 0x0110: return .k42
            default: return .unknown
            }
        case 0x2F5C_204E:
            return .k5Monolith
        default:
            return .unknown
        }
    }

    public static func scan(
        rootURL: URL,
        progress: ((Progress) -> Void)? = nil
    ) throws -> [LibraryRef] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isRegularFileKey]

        let topLevel = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        var libraries: [LibraryRef] = []
        var totalInstruments = 0

        for (libraryIndex, libraryURL) in topLevel.enumerated() {
            let libraryName = libraryURL.lastPathComponent
            var instruments: [InstrumentRef] = []

            if let enumerator = fileManager.enumerator(
                at: libraryURL,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) {
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                    if values?.isDirectory == true {
                        if shouldSkipDirectory(fileURL.lastPathComponent) {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                    guard fileURL.pathExtension.lowercased() == "nki" else { continue }
                    let size = Int64(values?.fileSize ?? 0)
                    let inspection = inspect(url: fileURL)
                    instruments.append(InstrumentRef(
                        url: fileURL,
                        library: libraryName,
                        name: fileURL.deletingPathExtension().lastPathComponent,
                        format: inspection.format,
                        size: size,
                        hasMapping: inspection.hasMapping
                    ))
                    totalInstruments += 1
                }
            }

            if !instruments.isEmpty {
                instruments.sort {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                libraries.append(LibraryRef(url: libraryURL, instruments: instruments))
            }

            progress?(Progress(
                library: libraryName,
                instruments: totalInstruments,
                fraction: Double(libraryIndex + 1) / Double(max(1, topLevel.count))
            ))
        }

        libraries.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return libraries
    }

    private static func shouldSkipDirectory(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower == "documentation" || lower == "docs" || lower == "snapshots"
            || lower == "library data" || lower == "multis" || lower == "resources"
            || lower == "previews" || lower == ".previews" || lower == "wallpaper" {
            return true
        }
        // Sample folders are often named "X Samples", "IR Samples", etc.
        if lower.contains("samples") || lower.contains("sample library") {
            return true
        }
        return false
    }
}

public enum InstrumentLibraryGrouping {
    /// Instruments that sit directly under the root are grouped separately.
    public static func rootLibraryName() -> String { "(root)" }
}

import Foundation
import Compression

// MARK: - Header

public struct K2Header: Sendable {
    public let isBigEndian: Bool
    public let headerVersion: UInt16
    public let isMonolith: Bool
    public let compressedLength: UInt32
    public let zoneCount: UInt16
    public let groupCount: UInt16
    public let instrumentCount: UInt16
    public let sampleByteCount: UInt32
    public let fileSize: Int64

    public static func read(from url: URL) throws -> K2Header {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let head = try handle.read(upToCount: 170), head.count >= 170 else {
            throw K2Error.notAK2File
        }
        let magic = head.readUInt32BE(at: 0)
        let littleEndian: Bool
        switch magic {
        case 0x1290_A87F, 0x01EF_85AB:
            littleEndian = true
        case 0x7FA8_9012, 0xAB85_EF01:
            littleEndian = false
        default:
            throw K2Error.notAK2File
        }

        func u16(_ offset: Int) -> UInt16 {
            head.readUInt16(at: offset, littleEndian: littleEndian)
        }
        func u32(_ offset: Int) -> UInt32 {
            head.readUInt32(at: offset, littleEndian: littleEndian)
        }

        let version = u16(8)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return K2Header(
            isBigEndian: !littleEndian,
            headerVersion: version,
            isMonolith: u32(42) == 1,
            compressedLength: u32(4),
            zoneCount: u16(32),
            groupCount: u16(34),
            instrumentCount: u16(36),
            sampleByteCount: u32(38),
            fileSize: size
        )
    }
}

// MARK: - Errors

public enum K2Error: LocalizedError {
    case notAK2File
    case unsupportedVersion(UInt16)
    case missingXML
    case corruptXML(String)
    case unsupportedPath(String)
    case sampleNotFound(String)
    case noZones
    case monolithUnreadable

    public var errorDescription: String? {
        switch self {
        case .notAK2File:
            return "This is not a Kontakt 2/3 instrument."
        case .unsupportedVersion(let version):
            return String(format: "Unsupported Kontakt container version 0x%X.", version)
        case .missingXML:
            return "The instrument mapping could not be found inside the .nki file."
        case .corruptXML(let detail):
            return "The instrument mapping is corrupt: \(detail)"
        case .unsupportedPath(let path):
            return "Unsupported sample path encoding: \(path)"
        case .sampleNotFound(let name):
            return "Sample not found: \(name)"
        case .noZones:
            return "The instrument contains no sample zones."
        case .monolithUnreadable:
            return "The embedded sample container could not be read."
        }
    }
}

// MARK: - zlib

enum K2Compression {
    /// K2 stores a normal zlib stream. Compression.framework's COMPRESSION_ZLIB
    /// consumes raw DEFLATE, so skip the 2-byte zlib header.
    static func inflate(_ data: Data) throws -> Data {
        guard data.count > 6 else { throw K2Error.missingXML }
        let raw = data.dropFirst(2)
        var capacity = max(4 << 20, raw.count * 8)
        let maximum = 32 << 20

        while capacity <= maximum {
            var output = [UInt8](repeating: 0, count: capacity)
            let written: Int = output.withUnsafeMutableBytes { outPtr in
                raw.withUnsafeBytes { inPtr in
                    guard let outBase = outPtr.bindMemory(to: UInt8.self).baseAddress,
                          let inBase = inPtr.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
                    return compression_decode_buffer(
                        outBase, capacity,
                        inBase, raw.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 {
                return Data(output.prefix(written))
            }
            capacity *= 2
        }
        throw K2Error.missingXML
    }

    static func looksLikeZlibHeader(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index + 1 < bytes.count else { return false }
        let cmf = Int(bytes[index])
        let flg = Int(bytes[index + 1])
        guard cmf == 0x78, flg == 0x01 || flg == 0x5E || flg == 0x9C || flg == 0xDA else {
            return false
        }
        return ((cmf << 8) + flg) % 31 == 0
    }
}

// MARK: - Path decoder

public enum K2PathDecoder {
    public static func decode(_ encoded: String) throws -> String {
        guard encoded.hasPrefix("@") else {
            return encoded.replacingOccurrences(of: "\\", with: "/")
        }

        let units = Array(encoded.utf16)
        var i = 1
        var path = ""

        func readFolder() throws -> String {
            guard i + 3 <= units.count else { throw K2Error.unsupportedPath(encoded) }
            let digits = String(decoding: units[i..<(i + 3)], as: UTF16.self)
            guard let length = Int(digits), length >= 0, i + 3 + length <= units.count else {
                throw K2Error.unsupportedPath(encoded)
            }
            i += 3
            let value = String(decoding: units[i..<(i + length)], as: UTF16.self)
            i += length
            return value
        }

        while i < units.count {
            let code = units[i]
            i += 1
            switch code {
            case 0x76: // 'v' — drive / volume
                let value = try readFolder()
                if !value.contains(":") { path += "/" }
                path += value + "/"
            case 0x62: // 'b' — parent
                path += "../"
            case 0x64: // 'd' — directory
                path += try readFolder() + "/"
            case 0x46, 0x66: // 'F' or 'f' — file
                i += (code == 0x46 ? 11 : 6)
                guard i <= units.count else { throw K2Error.unsupportedPath(encoded) }
                path += String(decoding: units[i...], as: UTF16.self)
                i = units.count
            case 0x6D: // 'm' — NKS library container
                // The library itself is not a filesystem path. Skip the segment and
                // let the basename fallback in SampleResolver find the sample.
                _ = try readFolder()
            default:
                throw K2Error.unsupportedPath(encoded)
            }
        }
        return decodePercentEscapes(path)
    }

    static func decodePercentEscapes(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "%%", with: "\u{0}")
        result = result.replacingOccurrences(of: "%%", with: "%")

        var output = ""
        let scalars = Array(result.unicodeScalars)
        var i = 0
        while i < scalars.count {
            if scalars[i] == "%", i + 2 < scalars.count,
               let value = UInt32(String(String.UnicodeScalarView(scalars[(i + 1)...(i + 2)])), radix: 16),
               let scalar = UnicodeScalar(value) {
                output.unicodeScalars.append(scalar)
                i += 3
            } else {
                output.unicodeScalars.append(scalars[i])
                i += 1
            }
        }
        return output.replacingOccurrences(of: "\u{0}", with: "%")
    }
}

// MARK: - XML tree

final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XMLNode? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [XMLNode] {
        children.filter { $0.name == name }
    }

    func firstDescendant(named name: String) -> XMLNode? {
        if self.name == name { return self }
        for child in children {
            if let found = child.firstDescendant(named: name) { return found }
        }
        return nil
    }

    func valueMap() -> [String: String] {
        var map: [String: String] = [:]
        for node in children where node.name == "V" {
            if let key = node.attributes["name"] {
                map[key] = node.attributes["value"] ?? ""
            }
        }
        return map
    }
}

final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private(set) var root: XMLNode?
    private var stack: [XMLNode] = []
    private(set) var parseError: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError.localizedDescription
    }
}

// MARK: - Parser

public enum K2Parser {
    public static func parse(url: URL) throws -> ParsedInstrument {
        let header = try K2Header.read(from: url)
        if header.headerVersion == 0x110 {
            throw K2Error.unsupportedVersion(header.headerVersion)
        }
        let xml = try extractXML(url: url, header: header)
        let node = try parseXML(xml)
        guard node.name == "K2_Container" else {
            throw K2Error.corruptXML("unexpected root \(node.name)")
        }

        guard let program = node.firstDescendant(named: "K2_Program") else {
            throw K2Error.noZones
        }

        let programParameters = program.child("Parameters")?.valueMap() ?? [:]
        let programName = program.attributes["name"] ?? url.deletingPathExtension().lastPathComponent
        let programTranspose = intValue(programParameters["transpose"], default: 0)
        let programVolume = floatValue(programParameters["volume"], default: 0.5)
        let programPan = floatValue(programParameters["pan"], default: 0)
        let programTune = floatValue(programParameters["tune"], default: 1)

        let groupNodes = program.child("Groups")?.children(named: "K2_Group") ?? []
        var groups: [K2Group] = []
        for (fallbackIndex, groupNode) in groupNodes.enumerated() {
            let params = groupNode.child("Parameters")?.valueMap() ?? [:]
            let index = intValue(groupNode.attributes["index"], default: fallbackIndex)
            let name = groupNode.attributes["name"] ?? "Group \(index + 1)"
            groups.append(K2Group(
                index: index,
                name: name,
                volume: floatValue(params["volume"], default: 1),
                pan: floatValue(params["pan"], default: 0),
                tune: floatValue(params["tune"], default: 1),
                keyTracking: boolValue(params["keyTracking"], default: true),
                isReleaseTrigger: boolValue(params["releaseTrigger"], default: false),
                isMuted: boolValue(params["muted"], default: false) || boolValue(params["mute"], default: false)
            ))
        }

        let zoneNodes = program.child("Zones")?.children(named: "K2_Zone") ?? []
        var zones: [K2Zone] = []
        for (fallbackIndex, zoneNode) in zoneNodes.enumerated() {
            let params = zoneNode.child("Parameters")?.valueMap() ?? [:]
            let sample = zoneNode.child("Sample")?.valueMap() ?? [:]
            let encodedPath = [sample["file_ex2"], sample["file"]]
                .compactMap { $0 }
                .first { !$0.isEmpty && $0 != "@" } ?? ""
            guard !encodedPath.isEmpty else { continue }
            let path = try K2PathDecoder.decode(encodedPath)
            let name = (path as NSString).lastPathComponent
            let loop = zoneNode.child("Loops")?.children(named: "Loop").first?.valueMap() ?? [:]

            zones.append(K2Zone(
                index: intValue(zoneNode.attributes["index"], default: fallbackIndex),
                groupIndex: intValue(zoneNode.attributes["groupIdx"], default: 0),
                lowKey: intValue(params["lowKey"], default: 0),
                highKey: intValue(params["highKey"], default: 127),
                lowVelocity: intValue(params["lowVelocity"], default: 1),
                highVelocity: intValue(params["highVelocity"], default: 127),
                rootKey: intValue(params["rootKey"], default: 60),
                volume: floatValue(params["zoneVolume"], default: 1),
                pan: floatValue(params["zonePan"], default: 0),
                tune: floatValue(params["zoneTune"], default: 1),
                sampleStart: intValue(params["sampleStart"], default: 0),
                sampleEnd: intValue(params["sampleEnd"], default: 0),
                loopStart: intValue(loop["loopStart"], default: 0),
                loopLength: intValue(loop["loopLength"], default: 0),
                loopMode: loop["mode"] ?? "no_loop",
                samplePath: path,
                sampleName: name,
                isPurged: boolValue(sample["purged"], default: false)
            ))
        }

        guard !zones.isEmpty else { throw K2Error.noZones }

        let monolith = header.isMonolith ? try K2MonolithIndex.read(url: url) : nil
        return ParsedInstrument(
            sourceURL: url,
            programName: programName,
            format: .k2,
            isMonolith: header.isMonolith,
            groups: groups,
            zones: zones,
            programTranspose: programTranspose,
            programVolume: programVolume,
            programPan: programPan,
            programTune: programTune,
            monolith: monolith
        )
    }

    private static func extractXML(url: URL, header: K2Header) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = Int(header.fileSize)

        // The typical K2 header is exactly 170 bytes. Try the likely offsets first.
        let preferred = [170, 174, 166, 178]
        for offset in preferred where offset < fileSize {
            let length = min(4 << 20, fileSize - offset)
            try? handle.seek(toOffset: UInt64(offset))
            guard let data = try? handle.read(upToCount: length), !data.isEmpty else { continue }
            if let xml = try? decodeXMLCandidate(data) { return xml }
        }

        // Monolith files place the mapping at the very end. Non-monoliths place it
        // immediately after the header, so a small prefix is enough.
        let scanLength = header.isMonolith ? min(8 << 20, fileSize) : min(64 << 10, fileSize)
        let scanStart = header.isMonolith ? max(0, fileSize - scanLength) : 0
        try? handle.seek(toOffset: UInt64(scanStart))
        guard let scan = try? handle.read(upToCount: min(scanLength, fileSize - scanStart)), !scan.isEmpty else {
            throw K2Error.missingXML
        }

        let bytes = [UInt8](scan)
        let maximumAttempts = 24
        var attempts = 0

        if header.isMonolith {
            var index = bytes.count - 2
            while index >= 0 && attempts < maximumAttempts {
                if K2Compression.looksLikeZlibHeader(bytes, at: index) {
                    attempts += 1
                    let candidate = scan.subdata(in: index..<scan.count)
                    if let xml = try? decodeXMLCandidate(candidate) { return xml }
                }
                index -= 1
            }
        } else {
            var index = 0
            while index < bytes.count - 1 && attempts < maximumAttempts {
                if K2Compression.looksLikeZlibHeader(bytes, at: index) {
                    attempts += 1
                    let candidate = scan.subdata(in: index..<scan.count)
                    if let xml = try? decodeXMLCandidate(candidate) { return xml }
                }
                index += 1
            }
        }

        throw K2Error.missingXML
    }

    private static func decodeXMLCandidate(_ data: Data) throws -> Data {
        let inflated = try K2Compression.inflate(data)
        let bytes = [UInt8](inflated)
        let start: Int
        if let range = inflated.range(of: Data("<?xml".utf8)) {
            start = inflated.distance(from: inflated.startIndex, to: range.lowerBound)
        } else if let range = inflated.range(of: Data("<K2_Container".utf8)) {
            start = inflated.distance(from: inflated.startIndex, to: range.lowerBound)
        } else {
            throw K2Error.missingXML
        }

        let endMarker = Data("</K2_Container>".utf8)
        guard let endRange = inflated.range(of: endMarker, options: .backwards) else {
            throw K2Error.missingXML
        }
        let end = inflated.distance(from: inflated.startIndex, to: endRange.upperBound)
        guard start < end, end <= bytes.count else { throw K2Error.missingXML }
        return inflated.subdata(in: start..<end)
    }

    private static func parseXML(_ data: Data) throws -> XMLNode {
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root = builder.root else {
            throw K2Error.corruptXML(builder.parseError ?? "XML parser failed")
        }
        return root
    }
}

// MARK: - Small parsing helpers

func intValue(_ text: String?, default fallback: Int) -> Int {
    guard let text, !text.isEmpty else { return fallback }
    if let value = Int(text) { return value }
    if let value = Double(text) { return Int(value.rounded()) }
    return fallback
}

func floatValue(_ text: String?, default fallback: Float) -> Float {
    guard let text, !text.isEmpty else { return fallback }
    return Float(text) ?? fallback
}

func boolValue(_ text: String?, default fallback: Bool) -> Bool {
    guard let text else { return fallback }
    switch text.lowercased() {
    case "yes", "true", "1": return true
    case "no", "false", "0": return false
    default: return fallback
    }
}

// MARK: - Data helpers

extension Data {
    func readUInt16(at offset: Int, littleEndian: Bool) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let b0 = UInt16(self[startIndex + offset])
        let b1 = UInt16(self[startIndex + offset + 1])
        return littleEndian ? (b0 | (b1 << 8)) : ((b0 << 8) | b1)
    }

    func readUInt32(at offset: Int, littleEndian: Bool) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let b0 = UInt32(self[startIndex + offset])
        let b1 = UInt32(self[startIndex + offset + 1])
        let b2 = UInt32(self[startIndex + offset + 2])
        let b3 = UInt32(self[startIndex + offset + 3])
        if littleEndian {
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        readUInt32(at: offset, littleEndian: false)
    }
}

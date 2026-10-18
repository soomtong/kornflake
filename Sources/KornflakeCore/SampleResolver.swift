import Foundation

/// Resolves the sample references inside K2 instruments to real files.
/// Absolute paths in old libraries often point at machines that no longer exist, so
/// there is a basename fallback scoped to the library folder.
public final class SampleResolver: @unchecked Sendable {
    private let rootURL: URL
    private let libraryURL: URL
    private let lock = NSLock()
    private var basenameIndex: [String: URL]?
    /// Zone to file mapping found so far. Resolving walks several candidate paths (and, for
    /// monoliths, hashes and extracts), so each zone is only resolved once per session.
    private var resolvedByZone: [String: URL] = [:]

    public init(rootURL: URL, libraryName: String) {
        self.rootURL = rootURL
        self.libraryURL = rootURL.appendingPathComponent(libraryName, isDirectory: true)
    }

    public func resolve(zone: K2Zone, in instrument: ParsedInstrument) throws -> URL {
        let cacheKey = "\(instrument.sourceURL.path)|\(zone.index)|\(zone.sampleName)"
        lock.lock()
        let cached = resolvedByZone[cacheKey]
        lock.unlock()
        // One stat to notice an extracted monolith sample that was removed from the cache folder.
        if let cached, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let url = try locate(zone: zone, in: instrument)
        lock.lock()
        resolvedByZone[cacheKey] = url
        lock.unlock()
        return url
    }

    private func locate(zone: K2Zone, in instrument: ParsedInstrument) throws -> URL {
        if let monolith = instrument.monolith {
            return try monolith.sampleURL(named: zone.sampleName)
        }

        let nkiFolder = instrument.sourceURL.deletingLastPathComponent()
        let rawPath = zone.samplePath

        var candidates: [URL] = []
        if rawPath.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: rawPath))
        }
        candidates.append(URL(fileURLWithPath: rawPath, relativeTo: nkiFolder).standardizedFileURL)
        candidates.append(nkiFolder.appendingPathComponent((rawPath as NSString).lastPathComponent))
        candidates.append(libraryURL.appendingPathComponent((rawPath as NSString).lastPathComponent))

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if let indexed = index()[zone.sampleName.lowercased()] {
            return indexed
        }

        throw K2Error.sampleNotFound(zone.sampleName)
    }

    private func index() -> [String: URL] {
        lock.lock()
        defer { lock.unlock() }
        if let basenameIndex { return basenameIndex }

        var map: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        if let enumerator = FileManager.default.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "wav" || ext == "aif" || ext == "aiff" || ext == "wave" else { continue }
                let key = url.lastPathComponent.lowercased()
                if map[key] == nil { map[key] = url }
            }
        }
        basenameIndex = map
        return map
    }
}

public final class SampleResolverStore: @unchecked Sendable {
    public static let shared = SampleResolverStore()
    private var resolvers: [String: SampleResolver] = [:]
    private let lock = NSLock()

    public func resolver(rootURL: URL, libraryName: String) -> SampleResolver {
        lock.lock()
        defer { lock.unlock() }
        let key = rootURL.appendingPathComponent(libraryName).path
        if let existing = resolvers[key] { return existing }
        let resolver = SampleResolver(rootURL: rootURL, libraryName: libraryName)
        resolvers[key] = resolver
        return resolver
    }
}

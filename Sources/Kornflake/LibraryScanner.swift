import Foundation

struct LibraryItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case instrument
        case multi
        case snapshot
    }

    let id: String
    let url: URL
    let name: String
    let relativePath: String
    let kind: Kind
}

struct LibraryScan: Sendable {
    let instruments: [LibraryItem]
    let snapshots: [LibraryItem]
}

enum LibraryScannerError: LocalizedError {
    case rootMissing(URL)

    var errorDescription: String? {
        switch self {
        case .rootMissing(let url):
            "라이브러리 경로를 찾을 수 없습니다: \(url.path)"
        }
    }
}

enum LibraryScanner {
    static func scan(root: URL) throws -> LibraryScan {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw LibraryScannerError.rootMissing(root)
        }

        let rootPath = root.standardizedFileURL.path
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw LibraryScannerError.rootMissing(root)
        }

        var instruments: [LibraryItem] = []
        var snapshots: [LibraryItem] = []

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else {
                continue
            }

            let kind: LibraryItem.Kind
            switch url.pathExtension.lowercased() {
            case "nki":
                kind = .instrument
            case "nkm":
                kind = .multi
            case "nksn":
                kind = .snapshot
            default:
                continue
            }

            let relative = url.standardizedFileURL.path
                .replacingOccurrences(of: rootPath + "/", with: "")
            let item = LibraryItem(
                id: url.standardizedFileURL.path,
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                relativePath: relative,
                kind: kind
            )
            if kind == .snapshot {
                snapshots.append(item)
            } else {
                instruments.append(item)
            }
        }

        instruments.sort {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        snapshots.sort {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return LibraryScan(instruments: instruments, snapshots: snapshots)
    }
}

import Foundation

/// SwiftData performs an additive lightweight migration. Back up the complete
/// unopened SQLite store, WAL and external-data support directories beforehand.
enum StorageMigration {
    static let currentFormat = 4
    static func prepareStore(at url: URL) throws {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: "folioStoreFormat") < currentFormat,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let parent = url.deletingLastPathComponent()
        let backup = parent.appending(path: "Library Backups/Before-v\(currentFormat)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [])
        for file in files where file.lastPathComponent.hasPrefix("Folio") || file.lastPathComponent.hasPrefix(".Folio") {
            try FileManager.default.copyItem(at: file, to: backup.appending(path: file.lastPathComponent))
        }
    }
}

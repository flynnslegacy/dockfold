import Foundation
import NidoCore

/// Reads and rewrites the apps pinned in the Dock.
protocol DockServicing {
    func persistentApps() -> [DockTile]
    func write(_ tiles: [DockTile])
    func restart()
    var hasBackup: Bool { get }
    /// Saves the Dock as it was before Nido's first change. Later calls keep that first copy.
    func backupIfNeeded(_ tiles: [DockTile]) throws
    func restoreBackup() -> Bool
}

final class DockService: DockServicing {
    private let domain = "com.apple.dock" as CFString
    private let key = "persistent-apps" as CFString
    private let backupURL: URL

    init(backupURL: URL) {
        self.backupURL = backupURL
    }

    func persistentApps() -> [DockTile] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [DockTile] ?? []
    }

    func write(_ tiles: [DockTile]) {
        CFPreferencesSetAppValue(key, tiles as NSArray as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    /// The Dock only reads its preferences when it starts.
    func restart() {
        try? ProcessRunner.run("/usr/bin/killall", ["Dock"])
    }

    var hasBackup: Bool { FileManager.default.fileExists(atPath: backupURL.path) }

    func backupIfNeeded(_ tiles: [DockTile]) throws {
        guard !hasBackup else { return }
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: tiles, format: .xml, options: 0)
        try data.write(to: backupURL, options: .atomic)
    }

    func restoreBackup() -> Bool {
        guard let data = try? Data(contentsOf: backupURL),
              let tiles = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [DockTile] else { return false }
        write(tiles)
        restart()
        return true
    }
}

enum ProcessRunner {
    struct Failure: LocalizedError {
        let tool: String
        let message: String
        var errorDescription: String? { "\(tool) a échoué : \(message)" }
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure(tool: (executable as NSString).lastPathComponent,
                          message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

import Foundation

/// An application placed inside a Dock folder.
public struct FolderApp: Codable, Hashable, Identifiable, Sendable {
    public var path: String
    public var name: String
    public var bundleIdentifier: String?

    public var id: String { path }

    public init(path: String, name: String, bundleIdentifier: String? = nil) {
        self.path = path
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    /// Validates a URL coming from the outside (drop, open panel) and builds an entry.
    /// Returns nil for anything that is not an existing local `.app` bundle.
    public init?(bundleURL: URL, fileManager: FileManager = .default) {
        guard bundleURL.isFileURL else { return nil }
        let url = bundleURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "app" else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        var name = fileManager.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        self.init(path: url.path, name: name, bundleIdentifier: Bundle(url: url)?.bundleIdentifier)
    }
}

/// A group of apps shown as a single icon in the Dock.
public struct DockFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var apps: [FolderApp]

    public init(id: UUID = UUID(), name: String, apps: [FolderApp] = []) {
        self.id = id
        self.name = name
        self.apps = apps
    }

    /// Each folder gets its own launcher identity so LaunchServices never mixes two folders up.
    public var bundleIdentifier: String { "local.dockfold.folder." + id.uuidString.lowercased() }

    public var displayName: String { FolderNaming.displayName(name) }

    public func contains(path: String) -> Bool { apps.contains { $0.path == path } }

    /// Appends the apps that are not already inside, keeping their order. Returns how many were added.
    @discardableResult
    public mutating func add(_ newApps: [FolderApp]) -> Int {
        var added = 0
        for app in newApps where !contains(path: app.path) {
            apps.append(app)
            added += 1
        }
        return added
    }

    public mutating func remove(path: String) {
        apps.removeAll { $0.path == path }
    }
}

public enum FolderNaming {
    public static let fallback = "Dossier"
    public static let maxLength = 60

    /// Name shown in the Dock and in the bubble.
    public static func displayName(_ raw: String) -> String {
        let flattened = raw.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(maxLength))
    }

    /// Name usable as a bundle file name: no path separators, no control characters, not hidden.
    public static func fileSafeName(_ raw: String) -> String {
        var name = displayName(raw)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        name.unicodeScalars.removeAll { CharacterSet.controlCharacters.contains($0) }
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? fallback : name
    }
}

/// Where Dockfold keeps its data.
public struct DockfoldPaths: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static var standard: DockfoldPaths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DockfoldPaths(root: support.appendingPathComponent("Dockfold", isDirectory: true))
    }

    public var foldersDirectory: URL { root.appendingPathComponent("Folders", isDirectory: true) }
    public var storeURL: URL { root.appendingPathComponent("folders.json") }
    public var dockBackupURL: URL { root.appendingPathComponent("dock-backup.plist") }

    public func folderDirectory(for id: UUID) -> URL {
        foldersDirectory.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    /// Any Dock tile whose path starts with this prefix belongs to the folder.
    public func matchPrefix(for id: UUID) -> String { folderDirectory(for: id).path + "/" }
}

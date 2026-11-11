import Foundation

/// What Nido persists: the folders being edited, and the folders last written to the Dock.
public struct StoreState: Codable, Equatable, Sendable {
    public var folders: [DockFolder]
    public var applied: [DockFolder]

    public init(folders: [DockFolder] = [], applied: [DockFolder] = []) {
        self.folders = folders
        self.applied = applied
    }
}

public protocol FolderStoring {
    func load() throws -> StoreState
    func save(_ state: StoreState) throws
}

public struct JSONFolderStore: FolderStoring {
    public let fileURL: URL

    private struct Envelope: Codable {
        var version: Int
        var state: StoreState
    }

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> StoreState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StoreState() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Envelope.self, from: data).state
    }

    public func save(_ state: StoreState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(version: 1, state: state)).write(to: fileURL, options: .atomic)
    }
}

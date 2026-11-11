import Foundation

/// One entry of the Dock's `persistent-apps` preference.
public typealias DockTile = [String: Any]

/// What the Dock should show for one folder.
public struct FolderPlacement {
    public var bundlePath: String
    public var label: String
    public var bundleIdentifier: String
    /// Any tile under this directory is this folder (covers renames of the bundle).
    public var matchPrefix: String
    /// Apps grouped in the folder: their own tiles leave the Dock.
    public var appPaths: [String]
    /// Apps taken out of the folder since the last update: they come back right after it.
    public var appsToRestore: [FolderApp]

    public init(bundlePath: String, label: String, bundleIdentifier: String, matchPrefix: String,
                appPaths: [String], appsToRestore: [FolderApp] = []) {
        self.bundlePath = bundlePath
        self.label = label
        self.bundleIdentifier = bundleIdentifier
        self.matchPrefix = matchPrefix
        self.appPaths = appPaths
        self.appsToRestore = appsToRestore
    }
}

/// Pure edits of the Dock's tile list. Nothing here touches the real Dock.
public enum DockTiles {
    public static func path(of tile: DockTile) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String else { return nil }
        let type = (file["_CFURLStringType"] as? NSNumber)?.intValue ?? 15
        if type == 0 { return normalize(string) }
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return normalize(url.path)
    }

    public static func makeAppTile(path: String, label: String, bundleIdentifier: String?) -> DockTile {
        var data: [String: Any] = [
            "file-data": [
                "_CFURLString": URL(fileURLWithPath: path, isDirectory: true).absoluteString,
                "_CFURLStringType": 15
            ] as [String: Any],
            "file-label": label,
            "file-type": 41
        ]
        if let bundleIdentifier { data["bundle-identifier"] = bundleIdentifier }
        return ["tile-data": data, "tile-type": "file-tile", "GUID": Int.random(in: 1..<Int(Int32.max))]
    }

    /// Applications pinned in the Dock, without Nido's own folders.
    public static func dockApps(in tiles: [DockTile], excludingPrefix prefix: String?) -> [FolderApp] {
        tiles.compactMap { tile in
            guard (tile["tile-type"] as? String ?? "file-tile") == "file-tile",
                  let path = path(of: tile), path.lowercased().hasSuffix(".app") else { return nil }
            if let prefix, path.hasPrefix(prefix) { return nil }
            let data = tile["tile-data"] as? [String: Any]
            let fallback = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return FolderApp(path: path, name: data?["file-label"] as? String ?? fallback,
                             bundleIdentifier: data?["bundle-identifier"] as? String)
        }
    }

    /// Puts each folder in the Dock and takes its apps out.
    /// The folder keeps its current place, or takes the place of its first app, or goes last.
    public static func applying(_ placements: [FolderPlacement], to tiles: [DockTile]) -> [DockTile] {
        var result = tiles
        for placement in placements {
            let grouped = Set(placement.appPaths.map(normalize))
            let isFolder: (DockTile) -> Bool = { path(of: $0)?.hasPrefix(placement.matchPrefix) == true }
            let isGrouped: (DockTile) -> Bool = { path(of: $0).map(grouped.contains) == true }
            let anchor = result.firstIndex(where: isFolder) ?? result.firstIndex(where: isGrouped)

            var kept: [DockTile] = []
            var insertAt: Int?
            for (index, tile) in result.enumerated() {
                if index == anchor { insertAt = kept.count }
                if !isFolder(tile) && !isGrouped(tile) { kept.append(tile) }
            }

            var present = Set(kept.compactMap(path(of:)))
            var insertion = [makeAppTile(path: placement.bundlePath, label: placement.label,
                                         bundleIdentifier: placement.bundleIdentifier)]
            for app in placement.appsToRestore {
                let appPath = normalize(app.path)
                guard !present.contains(appPath), !grouped.contains(appPath) else { continue }
                present.insert(appPath)
                insertion.append(makeAppTile(path: appPath, label: app.name, bundleIdentifier: app.bundleIdentifier))
            }
            kept.insert(contentsOf: insertion, at: insertAt ?? kept.count)
            result = kept
        }
        return result
    }

    /// Takes a folder out of the Dock and puts its apps back where it was.
    /// When the folder is not in the Dock (removed by hand), nothing changes.
    public static func removingFolder(matchPrefix prefix: String, restoring apps: [FolderApp],
                                      from tiles: [DockTile]) -> [DockTile] {
        let isFolder: (DockTile) -> Bool = { path(of: $0)?.hasPrefix(prefix) == true }
        guard let index = tiles.firstIndex(where: isFolder) else { return tiles }
        let insertAt = tiles[..<index].filter { !isFolder($0) }.count
        var kept = tiles.filter { !isFolder($0) }
        var present = Set(kept.compactMap(path(of:)))
        var insertion: [DockTile] = []
        for app in apps {
            let appPath = normalize(app.path)
            guard !present.contains(appPath) else { continue }
            present.insert(appPath)
            insertion.append(makeAppTile(path: appPath, label: app.name, bundleIdentifier: app.bundleIdentifier))
        }
        kept.insert(contentsOf: insertion, at: insertAt)
        return kept
    }

    static func normalize(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

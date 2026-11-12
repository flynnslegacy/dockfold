import AppKit
import CoreServices
import DockfoldCore

/// Turns a folder into a launcher bundle the Dock can hold among the apps.
protocol FolderBuilding: Sendable {
    func build(_ folder: DockFolder) throws -> URL
    func remove(_ id: UUID)
}

struct FolderBuilder: FolderBuilding {
    enum BuildError: LocalizedError {
        case missingTemplate

        var errorDescription: String? {
            "le modèle de dossier est introuvable dans Dockfold.app. Reconstruis l'app avec scripts/build-app.sh."
        }
    }

    let paths: DockfoldPaths
    let templateURL: URL?
    private let renderer = IconRenderer()

    init(paths: DockfoldPaths, templateURL: URL?) {
        self.paths = paths
        self.templateURL = templateURL
    }

    func build(_ folder: DockFolder) throws -> URL {
        let fileManager = FileManager.default
        guard let templateURL, fileManager.fileExists(atPath: templateURL.path) else { throw BuildError.missingTemplate }
        terminateRunning(folder.bundleIdentifier)

        // Build next to the final bundle, then swap it in: the path the Dock knows never disappears.
        let directory = paths.folderDirectory(for: folder.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = directory.appendingPathComponent(FolderNaming.fileSafeName(folder.name) + ".app", isDirectory: true)
        let staging = directory.appendingPathComponent(".staging-\(UUID().uuidString).app", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: templateURL, to: staging)
        try customise(staging, for: folder)
        if fileManager.fileExists(atPath: bundle.path) {
            _ = try fileManager.replaceItemAt(bundle, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: bundle)
        }

        // A renamed folder leaves its old bundle behind.
        let leftovers = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in leftovers where item.pathExtension == "app" && item.lastPathComponent != bundle.lastPathComponent
            && !item.lastPathComponent.hasPrefix(".staging-") {
            try? fileManager.removeItem(at: item)
        }
        LSRegisterURL(bundle as CFURL, true)
        return bundle
    }

    private func customise(_ bundle: URL, for folder: DockFolder) throws {
        let fileManager = FileManager.default
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        try writeInfo(at: contents.appendingPathComponent("Info.plist"), for: folder)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(folder).write(to: resources.appendingPathComponent("folder.json"), options: .atomic)
        try renderer.writeFolderICNS(apps: folder.apps, to: resources.appendingPathComponent("FolderIcon.icns"))

        // Info.plist is sealed by the signature: sign again after editing it.
        try ProcessRunner.run("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
    }

    func remove(_ id: UUID) {
        terminateRunning(DockFolder(id: id, name: "").bundleIdentifier)
        try? FileManager.default.removeItem(at: paths.folderDirectory(for: id))
    }

    private func writeInfo(at url: URL, for folder: DockFolder) throws {
        let data = try Data(contentsOf: url)
        guard var info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        info["CFBundleIdentifier"] = folder.bundleIdentifier
        info["CFBundleName"] = folder.displayName
        info["CFBundleDisplayName"] = folder.displayName
        info["CFBundleIconFile"] = "FolderIcon"
        let output = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try output.write(to: url, options: .atomic)
    }

    private func terminateRunning(_ bundleIdentifier: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).forEach { $0.terminate() }
    }
}

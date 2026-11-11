import AppKit
import SwiftUI
import NidoCore

/// Whether an app of the Dock already sits in a folder.
enum Membership: Equatable {
    case none
    case here
    case other(String)
}

@MainActor
final class ManagerModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case applying
        case failed(String)
    }

    @Published var folders: [DockFolder] { didSet { persist() } }
    @Published var selection: DockFolder.ID?
    @Published private(set) var applied: [DockFolder]
    @Published private(set) var dockApps: [FolderApp] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hasBackup: Bool

    private let store: FolderStoring
    private let dock: DockServicing
    private let builder: FolderBuilding
    private let paths: NidoPaths
    private let renderer = IconRenderer()
    private var previewCache: [String: NSImage] = [:]

    init(store: FolderStoring, dock: DockServicing, builder: FolderBuilding, paths: NidoPaths) {
        self.store = store
        self.dock = dock
        self.builder = builder
        self.paths = paths
        let state = (try? store.load()) ?? StoreState()
        folders = state.folders
        applied = state.applied
        selection = state.folders.first?.id
        hasBackup = dock.hasBackup
        refreshDockApps()
    }

    // MARK: - State

    var isDirty: Bool { folders != applied }

    var statusText: String {
        switch phase {
        case .applying: return "Mise à jour du Dock…"
        case .failed(let message): return "Erreur : \(message)"
        case .idle:
            if isDirty { return "Modifications pas encore appliquées au Dock." }
            return folders.isEmpty ? "Aucun dossier pour l'instant." : "Le Dock est à jour."
        }
    }

    func refreshDockApps() {
        dockApps = DockTiles.dockApps(in: dock.persistentApps(), excludingPrefix: paths.foldersDirectory.path + "/")
    }

    func binding(for id: DockFolder.ID) -> Binding<DockFolder>? {
        guard folders.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.folders.first { $0.id == id } ?? DockFolder(id: id, name: "") },
            set: { [weak self] newValue in
                guard let self, let index = self.folders.firstIndex(where: { $0.id == id }) else { return }
                self.folders[index] = newValue
            }
        )
    }

    func membership(of app: FolderApp, in id: DockFolder.ID) -> Membership {
        if folders.first(where: { $0.id == id })?.contains(path: app.path) == true { return .here }
        if let other = folders.first(where: { $0.contains(path: app.path) }) { return .other(other.displayName) }
        return .none
    }

    func preview(for folder: DockFolder, size: CGFloat) -> NSImage {
        let key = "\(size)|" + folder.apps.map(\.path).joined(separator: "|")
        if let cached = previewCache[key] { return cached }
        let image = renderer.previewImage(apps: folder.apps, points: size)
        previewCache[key] = image
        return image
    }

    // MARK: - Editing

    func addFolder() {
        let folder = DockFolder(name: uniqueName("Nouveau dossier"))
        folders.append(folder)
        selection = folder.id
    }

    func deleteFolder(_ id: DockFolder.ID) {
        folders.removeAll { $0.id == id }
        if selection == id { selection = folders.first?.id }
    }

    func add(_ apps: [FolderApp], to id: DockFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].add(apps)
    }

    func addURLs(_ urls: [URL], to id: DockFolder.ID) {
        add(urls.compactMap { FolderApp(bundleURL: $0) }, to: id)
    }

    func remove(_ app: FolderApp, from id: DockFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].remove(path: app.path)
    }

    func toggle(_ app: FolderApp, in id: DockFolder.ID) {
        if membership(of: app, in: id) == .here { remove(app, from: id) } else { add([app], to: id) }
    }

    func pickApps(for id: DockFolder.ID) {
        let panel = NSOpenPanel()
        panel.title = "Ajouter des apps au dossier"
        panel.prompt = "Ajouter"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        addURLs(panel.urls, to: id)
    }

    // MARK: - Dock

    func apply() async {
        guard phase != .applying else { return }
        phase = .applying
        let current = folders
        let previous = applied
        let builder = self.builder
        do {
            // Read the Dock first: while bundles are rebuilt it may briefly lose track of them.
            var tiles = dock.persistentApps()
            try dock.backupIfNeeded(tiles)
            let built: [UUID: URL] = try await Task.detached(priority: .userInitiated) {
                var result: [UUID: URL] = [:]
                for folder in current where !folder.apps.isEmpty {
                    result[folder.id] = try builder.build(folder)
                }
                return result
            }.value

            let grouped = Set(current.flatMap { $0.apps.map(\.path) })

            // Folders deleted or emptied: their apps go back where the folder was.
            for old in previous where built[old.id] == nil {
                let restore = old.apps.filter { !grouped.contains($0.path) }
                tiles = DockTiles.removingFolder(matchPrefix: paths.matchPrefix(for: old.id), restoring: restore, from: tiles)
                builder.remove(old.id)
            }

            let placements = current.compactMap { folder -> FolderPlacement? in
                guard let url = built[folder.id] else { return nil }
                let before = previous.first { $0.id == folder.id }?.apps ?? []
                return FolderPlacement(bundlePath: url.path, label: folder.displayName,
                                       bundleIdentifier: folder.bundleIdentifier,
                                       matchPrefix: paths.matchPrefix(for: folder.id),
                                       appPaths: folder.apps.map(\.path),
                                       appsToRestore: before.filter { !grouped.contains($0.path) })
            }
            tiles = DockTiles.applying(placements, to: tiles)
            dock.write(tiles)
            dock.restart()

            applied = current
            persist()
            hasBackup = dock.hasBackup
            dockApps = DockTiles.dockApps(in: tiles, excludingPrefix: paths.foldersDirectory.path + "/")
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func restoreDock() {
        let alert = NSAlert()
        alert.messageText = "Remettre le Dock comme avant Nido ?"
        alert.informativeText = "Le Dock retrouve les icônes qu'il avait avant ta première modification avec Nido. Tes dossiers restent enregistrés ici : tu pourras les réappliquer."
        alert.addButton(withTitle: "Restaurer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard dock.restoreBackup() else {
            phase = .failed("aucune sauvegarde du Dock n'a été trouvée.")
            return
        }
        applied.forEach { builder.remove($0.id) }
        applied = []
        persist()
        refreshDockApps()
        phase = .idle
    }

    // MARK: - Private

    private func persist() {
        do {
            try store.save(StoreState(folders: folders, applied: applied))
        } catch {
            phase = .failed("impossible d'enregistrer les dossiers (\(error.localizedDescription)).")
        }
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(folders.map(\.name))
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }
}

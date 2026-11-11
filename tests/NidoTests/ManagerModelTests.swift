import XCTest
import NidoCore
@testable import Nido

// MARK: - Test doubles

final class FakeDock: DockServicing {
    var tiles: [DockTile]
    var backup: [DockTile]?
    private(set) var writes = 0
    private(set) var restarts = 0

    init(apps: [String]) {
        tiles = apps.map { DockTiles.makeAppTile(path: $0, label: ($0 as NSString).lastPathComponent, bundleIdentifier: nil) }
    }

    var paths: [String] { tiles.compactMap(DockTiles.path(of:)) }

    func persistentApps() -> [DockTile] { tiles }
    func write(_ tiles: [DockTile]) { self.tiles = tiles; writes += 1 }
    func restart() { restarts += 1 }
    var hasBackup: Bool { backup != nil }
    func backupIfNeeded(_ tiles: [DockTile]) throws { if backup == nil { backup = tiles } }
    func restoreBackup() -> Bool {
        guard let backup else { return false }
        write(backup)
        return true
    }
}

final class FakeBuilder: FolderBuilding, @unchecked Sendable {
    let paths: NidoPaths
    var failure: Error?
    private(set) var built: [String] = []
    private(set) var removed: [UUID] = []

    init(paths: NidoPaths) { self.paths = paths }

    func build(_ folder: DockFolder) throws -> URL {
        if let failure { throw failure }
        built.append(folder.name)
        return paths.folderDirectory(for: folder.id).appendingPathComponent(FolderNaming.fileSafeName(folder.name) + ".app")
    }

    func remove(_ id: UUID) { removed.append(id) }
}

final class MemoryStore: FolderStoring {
    var state = StoreState()
    func load() throws -> StoreState { state }
    func save(_ state: StoreState) throws { self.state = state }
}

// MARK: - Tests

@MainActor
final class ManagerModelTests: XCTestCase {
    private let mail = "/System/Applications/Mail.app"
    private let word = "/Applications/Microsoft Word.app"
    private let excel = "/Applications/Microsoft Excel.app"
    private let notion = "/Applications/Notion.app"
    private let paths = NidoPaths(root: URL(fileURLWithPath: "/tmp/nido-tests"))

    private var dock: FakeDock!
    private var builder: FakeBuilder!
    private var store: MemoryStore!
    private var model: ManagerModel!

    override func setUp() async throws {
        dock = FakeDock(apps: [mail, word, notion, excel])
        builder = FakeBuilder(paths: paths)
        store = MemoryStore()
        model = ManagerModel(store: store, dock: dock, builder: builder, paths: paths)
    }

    private func app(_ path: String) -> FolderApp { FolderApp(path: path, name: (path as NSString).lastPathComponent) }

    private func makeOffice(_ apps: [String]) -> DockFolder.ID {
        model.addFolder()
        let id = model.selection!
        model.binding(for: id)!.wrappedValue.name = "Office"
        model.add(apps.map(app), to: id)
        return id
    }

    private func folderPath(_ id: DockFolder.ID, _ name: String = "Office") -> String {
        paths.folderDirectory(for: id).appendingPathComponent(name + ".app").path
    }

    func testApplyReplacesGroupedAppsByTheFolderAndBacksUpTheDock() async {
        let id = makeOffice([word, excel])
        XCTAssertTrue(model.isDirty)

        await model.apply()

        XCTAssertEqual(dock.paths, [mail, folderPath(id), notion])
        XCTAssertEqual(dock.backup?.compactMap(DockTiles.path(of:)), [mail, word, notion, excel])
        XCTAssertEqual(dock.restarts, 1)
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(store.state.applied.map(\.id), [id])
        XCTAssertEqual(model.dockApps.map(\.path), [mail, notion])
    }

    func testDeletingAFolderPutsItsAppsBackWhereItWas() async {
        let id = makeOffice([word, excel])
        await model.apply()

        model.deleteFolder(id)
        await model.apply()

        XCTAssertEqual(dock.paths, [mail, word, excel, notion])
        XCTAssertEqual(builder.removed, [id])
    }

    func testAppTakenOutOfAFolderComesBackNextToIt() async {
        let id = makeOffice([word, excel])
        await model.apply()

        model.remove(app(excel), from: id)
        await model.apply()

        XCTAssertEqual(dock.paths, [mail, folderPath(id), excel, notion])
    }

    func testRenamedFolderKeepsItsPlace() async {
        let id = makeOffice([word])
        await model.apply()

        model.binding(for: id)!.wrappedValue.name = "Bureau"
        await model.apply()

        XCTAssertEqual(dock.paths, [mail, folderPath(id, "Bureau"), notion, excel])
    }

    func testEmptyFolderIsNotPutInTheDock() async {
        _ = makeOffice([])
        await model.apply()

        XCTAssertEqual(dock.paths, [mail, word, notion, excel])
        XCTAssertTrue(builder.built.isEmpty)
    }

    func testFailedBuildLeavesTheDockAlone() async {
        _ = makeOffice([word])
        builder.failure = CocoaError(.fileWriteNoPermission)

        await model.apply()

        XCTAssertEqual(dock.writes, 0)
        XCTAssertEqual(dock.restarts, 0)
        XCTAssertTrue(model.isDirty)
        if case .failed = model.phase {} else { XCTFail("expected a failure, got \(model.phase)") }
    }

    func testMembershipTellsWhereAnAppAlreadyIs() {
        let office = makeOffice([word])
        model.addFolder()
        let other = model.selection!

        XCTAssertEqual(model.membership(of: app(word), in: office), .here)
        XCTAssertEqual(model.membership(of: app(word), in: other), .other("Office"))
        XCTAssertEqual(model.membership(of: app(mail), in: other), Membership.none)
    }

    func testNewFoldersGetDistinctNames() {
        model.addFolder()
        model.addFolder()
        XCTAssertEqual(model.folders.map(\.name), ["Nouveau dossier", "Nouveau dossier 2"])
    }
}

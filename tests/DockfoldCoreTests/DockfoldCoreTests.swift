import XCTest
import CoreGraphics
@testable import DockfoldCore

final class GridShapeTests: XCTestCase {
    func testSmallFoldersStayOnOneRow() {
        XCTAssertEqual(BubbleLayout.grid(forCount: 1), GridShape(columns: 1, rows: 1))
        XCTAssertEqual(BubbleLayout.grid(forCount: 5), GridShape(columns: 5, rows: 1))
    }

    func testLargerFoldersAreBalanced() {
        XCTAssertEqual(BubbleLayout.grid(forCount: 6), GridShape(columns: 3, rows: 2))
        XCTAssertEqual(BubbleLayout.grid(forCount: 7), GridShape(columns: 4, rows: 2))
        XCTAssertEqual(BubbleLayout.grid(forCount: 10), GridShape(columns: 5, rows: 2))
        XCTAssertEqual(BubbleLayout.grid(forCount: 11), GridShape(columns: 4, rows: 3))
    }

    func testEmptyFolderStillHasOneCell() {
        XCTAssertEqual(BubbleLayout.grid(forCount: 0), GridShape(columns: 1, rows: 1))
    }
}

final class BubblePlacementTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let content = CGSize(width: 200, height: 100)

    func testBottomDockCentersOverAnchor() {
        let p = BubbleLayout.place(contentSize: content, anchor: CGPoint(x: 500, y: 20), edge: .bottom, dockInset: 50, screen: screen)
        XCTAssertEqual(p.frame, CGRect(x: 400, y: 50, width: 200, height: 100 + BubbleLayout.arrowLength))
        XCTAssertEqual(p.arrowOffset, 100)
        XCTAssertEqual(p.edge, .bottom)
    }

    func testBottomDockClampsToScreenAndKeepsArrowAwayFromCorner() {
        let p = BubbleLayout.place(contentSize: content, anchor: CGPoint(x: 30, y: 20), edge: .bottom, dockInset: 50, screen: screen)
        XCTAssertEqual(p.frame.minX, BubbleLayout.screenMargin)
        XCTAssertEqual(p.arrowOffset, BubbleLayout.cornerRadius + BubbleLayout.arrowHalfWidth)
    }

    func testLeftDockPutsBubbleToTheRight() {
        let p = BubbleLayout.place(contentSize: content, anchor: CGPoint(x: 20, y: 400), edge: .left, dockInset: 50, screen: screen)
        XCTAssertEqual(p.frame, CGRect(x: 50, y: 350, width: 200 + BubbleLayout.arrowLength, height: 100))
        XCTAssertEqual(p.arrowOffset, 50)
    }

    func testRightDockPutsBubbleToTheLeft() {
        let p = BubbleLayout.place(contentSize: content, anchor: CGPoint(x: 980, y: 400), edge: .right, dockInset: 50, screen: screen)
        XCTAssertEqual(p.frame.maxX, 950)
        XCTAssertEqual(p.frame.midY, 400)
    }
}

final class DockInsetTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testUsesSpaceReservedByTheDock() {
        let visible = CGRect(x: 0, y: 50, width: 1000, height: 725)
        let metrics = DockMetrics(edge: .bottom, tileSize: 32)
        XCTAssertEqual(BubbleLayout.dockInset(screenFrame: screen, visibleFrame: visible, metrics: metrics), 54)
    }

    func testAutohideFallsBackToTileSize() {
        let metrics = DockMetrics(edge: .bottom, tileSize: 32, autohide: true)
        XCTAssertEqual(BubbleLayout.dockInset(screenFrame: screen, visibleFrame: screen, metrics: metrics), 52)
    }

    func testMagnificationUsesLargeSize() {
        let metrics = DockMetrics(edge: .bottom, tileSize: 32, magnification: true, largeSize: 64)
        XCTAssertEqual(BubbleLayout.dockInset(screenFrame: screen, visibleFrame: screen, metrics: metrics), 84)
    }

    func testLeftDockReadsHorizontalInset() {
        let visible = CGRect(x: 60, y: 0, width: 940, height: 775)
        XCTAssertEqual(BubbleLayout.dockInset(screenFrame: screen, visibleFrame: visible, metrics: DockMetrics(edge: .left, tileSize: 32)), 64)
    }

    func testMetricsParseDockPreferences() {
        let m = DockMetrics(preferences: ["orientation": "left", "tilesize": NSNumber(value: 40.0), "magnification": NSNumber(value: true), "largesize": NSNumber(value: 72), "autohide": NSNumber(value: true)])
        XCTAssertEqual(m, DockMetrics(edge: .left, tileSize: 40, magnification: true, largeSize: 72, autohide: true))
    }

    func testMetricsDefaultToBottomDock() {
        XCTAssertEqual(DockMetrics(preferences: ["orientation": "top"]).edge, .bottom)
    }
}

final class BubbleShapeTests: XCTestCase {
    func testOutlineFillsItsRectOnEveryEdge() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 150)
        for edge in [DockEdge.bottom, .left, .right] {
            let box = BubbleShape.path(in: rect, edge: edge, arrowOffset: 60).boundingBoxOfPath
            XCTAssertEqual(box.minX, rect.minX, accuracy: 0.01, "\(edge)")
            XCTAssertEqual(box.maxX, rect.maxX, accuracy: 0.01, "\(edge)")
            XCTAssertEqual(box.minY, rect.minY, accuracy: 0.01, "\(edge)")
            XCTAssertEqual(box.maxY, rect.maxY, accuracy: 0.01, "\(edge)")
        }
    }

    func testBodyLeavesRoomForTheArrow() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(BubbleShape.bodyRect(in: rect, edge: .bottom), CGRect(x: 0, y: 9, width: 200, height: 91))
        XCTAssertEqual(BubbleShape.bodyRect(in: rect, edge: .left), CGRect(x: 9, y: 0, width: 191, height: 100))
        XCTAssertEqual(BubbleShape.bodyRect(in: rect, edge: .right), CGRect(x: 0, y: 0, width: 191, height: 100))
    }
}

final class FolderIconLayoutTests: XCTestCase {
    func testBodyFollowsTheMacIconGrid() {
        XCTAssertEqual(FolderIconLayout.bodyRect(canvas: 1024), CGRect(x: 100, y: 100, width: 824, height: 824))
    }

    func testMiniIconsFillRowsFromTheTopLeft() {
        let rects = FolderIconLayout.miniIconRects(count: 4, canvas: 1024)
        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(rects[0].minY, rects[2].minY)
        XCTAssertLessThan(rects[0].minX, rects[1].minX)
        XCTAssertGreaterThan(rects[0].minY, rects[3].minY)
        XCTAssertEqual(rects[3].minX, rects[0].minX)
    }

    func testAtMostNineMiniIconsInsideTheBody() {
        let body = FolderIconLayout.bodyRect(canvas: 512)
        let rects = FolderIconLayout.miniIconRects(count: 14, canvas: 512)
        XCTAssertEqual(rects.count, 9)
        XCTAssertTrue(rects.allSatisfy { body.contains($0) })
    }
}

final class DockTilesTests: XCTestCase {
    private let mail = "/System/Applications/Mail.app"
    private let word = "/Applications/Microsoft Word.app"
    private let excel = "/Applications/Microsoft Excel.app"
    private let notion = "/Applications/Notion.app"
    private let folderDir = "/Users/x/Library/Application Support/Dockfold/Folders/abc/"

    private func tile(_ path: String) -> DockTile {
        DockTiles.makeAppTile(path: path, label: (path as NSString).lastPathComponent, bundleIdentifier: nil)
    }

    private func paths(_ tiles: [DockTile]) -> [String] { tiles.compactMap(DockTiles.path(of:)) }

    private func placement(apps: [String], restore: [FolderApp] = []) -> FolderPlacement {
        FolderPlacement(bundlePath: folderDir + "Office.app", label: "Office", bundleIdentifier: "local.dockfold.folder.abc",
                        matchPrefix: folderDir, appPaths: apps, appsToRestore: restore)
    }

    func testPathOfTileDecodesFileURL() {
        let t: DockTile = ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Microsoft%20Word.app/", "_CFURLStringType": 15]]]
        XCTAssertEqual(DockTiles.path(of: t), word)
    }

    func testMadeTilesRoundTripTheirPath() {
        XCTAssertEqual(DockTiles.path(of: tile(word)), word)
    }

    func testGroupedAppsAreReplacedByTheFolderAtTheFirstAppPosition() {
        let result = DockTiles.applying([placement(apps: [word, excel])], to: [tile(mail), tile(word), tile(notion), tile(excel)])
        XCTAssertEqual(paths(result), [mail, folderDir + "Office.app", notion])
    }

    func testExistingFolderKeepsItsPositionAfterARename() {
        let result = DockTiles.applying([placement(apps: [word])], to: [tile(mail), tile(folderDir + "Ancien.app"), tile(notion), tile(word)])
        XCTAssertEqual(paths(result), [mail, folderDir + "Office.app", notion])
    }

    func testFolderIsAppendedWhenNoneOfItsAppsIsInTheDock() {
        let result = DockTiles.applying([placement(apps: [word])], to: [tile(mail)])
        XCTAssertEqual(paths(result), [mail, folderDir + "Office.app"])
    }

    func testAppsTakenOutOfAFolderComeBackNextToIt() {
        let restore = [FolderApp(path: excel, name: "Excel"), FolderApp(path: mail, name: "Mail")]
        let result = DockTiles.applying([placement(apps: [word], restore: restore)], to: [tile(mail), tile(folderDir + "Office.app"), tile(notion)])
        XCTAssertEqual(paths(result), [mail, folderDir + "Office.app", excel, notion])
    }

    func testRemovingAFolderPutsItsAppsBackInItsPlace() {
        let apps = [FolderApp(path: word, name: "Word"), FolderApp(path: excel, name: "Excel"), FolderApp(path: word, name: "Word")]
        let result = DockTiles.removingFolder(matchPrefix: folderDir, restoring: apps, from: [tile(mail), tile(folderDir + "Office.app"), tile(notion)])
        XCTAssertEqual(paths(result), [mail, word, excel, notion])
    }

    func testRemovingAFolderSkipsAppsAlreadyInTheDock() {
        let apps = [FolderApp(path: word, name: "Word"), FolderApp(path: excel, name: "Excel")]
        let result = DockTiles.removingFolder(matchPrefix: folderDir, restoring: apps, from: [tile(word), tile(folderDir + "Office.app")])
        XCTAssertEqual(paths(result), [word, excel])
    }

    func testRemovingAFolderThatIsNotInTheDockChangesNothing() {
        let result = DockTiles.removingFolder(matchPrefix: folderDir, restoring: [FolderApp(path: word, name: "Word")], from: [tile(mail)])
        XCTAssertEqual(paths(result), [mail])
    }

    func testDockAppsSkipsFolderTilesAndNonApps() {
        let other: DockTile = ["tile-type": "spacer-tile", "tile-data": [String: Any]()]
        let apps = DockTiles.dockApps(in: [tile(mail), other, tile(folderDir + "Office.app"), tile(word)], excludingPrefix: folderDir)
        XCTAssertEqual(apps.map(\.path), [mail, word])
        XCTAssertEqual(apps.first?.name, "Mail.app")
    }
}

final class FolderModelTests: XCTestCase {
    func testFileSafeNameReplacesSeparators() {
        XCTAssertEqual(FolderNaming.fileSafeName("Jeux/Fun:2"), "Jeux-Fun-2")
        XCTAssertEqual(FolderNaming.fileSafeName(".caché"), "caché")
    }

    func testBlankNamesFallBack() {
        XCTAssertEqual(FolderNaming.displayName("   \n"), FolderNaming.fallback)
    }

    func testLongNamesAreTruncated() {
        XCTAssertEqual(FolderNaming.displayName(String(repeating: "a", count: 100)).count, FolderNaming.maxLength)
    }

    func testAddingAppsSkipsDuplicates() {
        var folder = DockFolder(name: "Office", apps: [FolderApp(path: "/A.app", name: "A")])
        let added = folder.add([FolderApp(path: "/A.app", name: "A"), FolderApp(path: "/B.app", name: "B"), FolderApp(path: "/B.app", name: "B")])
        XCTAssertEqual(added, 1)
        XCTAssertEqual(folder.apps.map(\.path), ["/A.app", "/B.app"])
    }

    func testBundleIdentifierIsStablePerFolder() {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        XCTAssertEqual(DockFolder(id: id, name: "x").bundleIdentifier, "local.dockfold.folder.6f9619ff-8b86-d011-b42d-00c04fc964ff")
    }

    func testAppFromURLRejectsNonApplications() {
        XCTAssertNil(FolderApp(bundleURL: URL(fileURLWithPath: "/etc/hosts")))
        XCTAssertNil(FolderApp(bundleURL: URL(string: "https://example.com/Evil.app")!))
        XCTAssertEqual(FolderApp(bundleURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"))?.path, "/System/Applications/Calculator.app")
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFolderStore(fileURL: dir.appendingPathComponent("folders.json"))
        XCTAssertEqual(try store.load(), StoreState())
        let folder = DockFolder(name: "Jeux", apps: [FolderApp(path: "/Applications/Steam.app", name: "Steam", bundleIdentifier: "com.valvesoftware.steam")])
        let state = StoreState(folders: [folder], applied: [])
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
    }
}

final class QuarantineTests: XCTestCase {
    func testStripRemovesTheAttributeFromABundleAndItsContents() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: bundle) }
        let binary = bundle.appendingPathComponent("Contents/MacOS/Launcher")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: binary)
        let value = Array("0081;00000000;Safari;".utf8)
        for url in [bundle, binary] {
            XCTAssertEqual(setxattr(url.path, Quarantine.attribute, value, value.count, 0, 0), 0)
        }
        XCTAssertTrue(Quarantine.isQuarantined(binary))

        XCTAssertEqual(Quarantine.strip(at: bundle), 2)

        XCTAssertFalse(Quarantine.isQuarantined(bundle))
        XCTAssertFalse(Quarantine.isQuarantined(binary))
        XCTAssertEqual(Quarantine.strip(at: bundle), 0)
    }
}

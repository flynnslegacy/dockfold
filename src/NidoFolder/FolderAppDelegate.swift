import AppKit
import NidoCore

final class FolderAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: FolderPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = FolderPanelController(folder: FolderConfiguration.load())
        self.controller = controller
        controller.show()
    }

    /// Sent when the Dock tile is clicked while the launcher is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.toggleFromDock()
        return false
    }
}

enum FolderConfiguration {
    /// Reads `folder.json` from the bundle, or the file given with `--config` (handy for testing).
    static func load(arguments: [String] = CommandLine.arguments, bundle: Bundle = .main) -> DockFolder {
        var url = bundle.url(forResource: "folder", withExtension: "json")
        if let index = arguments.firstIndex(of: "--config"), index + 1 < arguments.count {
            url = URL(fileURLWithPath: arguments[index + 1])
        }
        if let url, let data = try? Data(contentsOf: url),
           let folder = try? JSONDecoder().decode(DockFolder.self, from: data) {
            return folder
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? FolderNaming.fallback
        return DockFolder(name: name)
    }
}

enum DockPreferences {
    static func read() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in ["orientation", "tilesize", "magnification", "largesize", "autohide"] {
            if let value = CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) {
                values[key] = value
            }
        }
        return values
    }
}

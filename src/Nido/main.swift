import AppKit
import NidoCore

let arguments = CommandLine.arguments

// Build-time helper: renders Nido's own icon (used by scripts/build-app.sh).
if let index = arguments.firstIndex(of: "--export-iconset"), index + 1 < arguments.count {
    do {
        try IconRenderer().exportAppIconset(to: URL(fileURLWithPath: arguments[index + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// Test helper: builds one folder bundle from a JSON file without touching the Dock.
if let index = arguments.firstIndex(of: "--build-folder"), index + 1 < arguments.count {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[index + 1]))
        let folder = try JSONDecoder().decode(DockFolder.self, from: data)
        let builder = FolderBuilder(paths: .standard, templateURL: Bundle.main.url(forResource: "NidoFolder", withExtension: "app"))
        print(try builder.build(folder).path)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}

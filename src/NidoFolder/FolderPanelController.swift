import AppKit
import NidoCore

/// Shows and hides the bubble above the folder's Dock tile.
final class FolderPanelController {
    private let folder: DockFolder
    private var panel: BubblePanel?
    private var outsideClickMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var lastOutsideClose = Date.distantPast

    init(folder: DockFolder) {
        self.folder = folder
    }

    var isShown: Bool { panel != nil }

    func toggleFromDock() {
        if isShown {
            close(restoringFocus: true)
            return
        }
        // Clicking our own tile while the bubble is open first closes it through the
        // outside-click monitor; the reopen that follows must not open it again.
        guard Date().timeIntervalSince(lastOutsideClose) > 0.4 else { return }
        show()
    }

    func show() {
        close(restoringFocus: false, animated: false)
        NSApp.unhide(nil)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let metrics = DockMetrics(preferences: DockPreferences.read())
        let inset = BubbleLayout.dockInset(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, metrics: metrics)

        let content = BubbleContentView(title: folder.displayName, apps: launchableApps) { [weak self] app in
            self?.launch(app)
        }
        let placement = BubbleLayout.place(contentSize: content.preferredContentSize, anchor: mouse,
                                           edge: metrics.edge, dockInset: inset, screen: screen.frame)
        content.configure(edge: placement.edge, arrowOffset: placement.arrowOffset)

        let panel = BubblePanel(frame: placement.frame)
        panel.contentView = content
        panel.onEscape = { [weak self] in self?.close(restoringFocus: true) }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        content.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        installMonitors()
    }

    func close(restoringFocus: Bool, animated: Bool = true) {
        removeMonitors()
        guard let panel else { return }
        self.panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
        // Give the focus back to the app the user was in.
        if restoringFocus, NSApp.isActive { NSApp.hide(nil) }
    }

    private var launchableApps: [FolderApp] {
        folder.apps.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func launch(_ app: FolderApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { _, error in
            if error != nil { DispatchQueue.main.async { NSSound.beep() } }
        }
        close(restoringFocus: false)
    }

    private func installMonitors() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.isShown else { return }
            self.lastOutsideClose = Date()
            self.close(restoringFocus: true)
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.close(restoringFocus: false)
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }
}

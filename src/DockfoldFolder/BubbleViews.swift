import AppKit
import DockfoldCore

/// Borderless floating panel that can take keyboard focus without activating the app.
final class BubblePanel: NSPanel {
    var onEscape: (() -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Dark frosted bubble with the folder name and the grid of apps.
final class BubbleContentView: NSView {
    private static let padding = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    private static let titleHeight: CGFloat = 16
    private static let titleSpacing: CGFloat = 4

    private let effect = NSVisualEffectView()
    private let border = BubbleBorderView()
    private let titleLabel: NSTextField
    private let grid: AppGridView
    private var edge: DockEdge = .bottom
    private var arrowOffset: CGFloat = 0

    init(title: String, apps: [FolderApp], onLaunch: @escaping (FolderApp) -> Void) {
        titleLabel = NSTextField(labelWithString: title)
        grid = AppGridView(apps: apps, onLaunch: onLaunch)
        super.init(frame: .zero)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.85)
        titleLabel.lineBreakMode = .byTruncatingTail
        [effect, border, titleLabel, grid].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Size of the bubble body, arrow excluded.
    var preferredContentSize: CGSize {
        let p = Self.padding
        let gridSize = grid.preferredSize
        let titleWidth = min(titleLabel.intrinsicContentSize.width, 360)
        return CGSize(width: ceil(max(gridSize.width, titleWidth)) + p.left + p.right,
                      height: p.top + Self.titleHeight + Self.titleSpacing + gridSize.height + p.bottom)
    }

    func configure(edge: DockEdge, arrowOffset: CGFloat) {
        self.edge = edge
        self.arrowOffset = arrowOffset
        needsLayout = true
    }

    override func layout() {
        super.layout()
        effect.frame = bounds
        border.frame = bounds
        let outline = BubbleShape.path(in: bounds, edge: edge, arrowOffset: arrowOffset)
        effect.maskImage = Self.maskImage(size: bounds.size, path: outline)
        border.outline = outline

        let body = BubbleShape.bodyRect(in: bounds, edge: edge)
        let p = Self.padding
        let gridSize = grid.preferredSize
        grid.frame = CGRect(x: body.minX + (body.width - gridSize.width) / 2, y: body.minY + p.bottom,
                            width: gridSize.width, height: gridSize.height)
        titleLabel.frame = CGRect(x: body.minX + p.left, y: body.maxY - p.top - Self.titleHeight,
                                  width: body.width - p.left - p.right, height: Self.titleHeight)
    }

    private static func maskImage(size: CGSize, path: CGPath) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
    }
}

/// Thin light rim around the bubble.
final class BubbleBorderView: NSView {
    var outline: CGPath? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let outline, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline)
        context.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
        context.setLineWidth(1)
        context.strokePath()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AppGridView: NSView {
    static let cellSize = CGSize(width: 74, height: 76)

    private let shape: GridShape
    private let cells: [AppCellView]
    private let emptyLabel: NSTextField?

    init(apps: [FolderApp], onLaunch: @escaping (FolderApp) -> Void) {
        shape = BubbleLayout.grid(forCount: apps.count)
        cells = apps.map { AppCellView(app: $0, onLaunch: onLaunch) }
        emptyLabel = apps.isEmpty ? NSTextField(labelWithString: "Ce dossier est vide") : nil
        super.init(frame: .zero)
        cells.forEach(addSubview)
        if let emptyLabel {
            emptyLabel.textColor = NSColor(white: 1, alpha: 0.6)
            emptyLabel.alignment = .center
            addSubview(emptyLabel)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    var preferredSize: CGSize {
        if emptyLabel != nil { return CGSize(width: 180, height: 36) }
        return CGSize(width: CGFloat(shape.columns) * Self.cellSize.width, height: CGFloat(shape.rows) * Self.cellSize.height)
    }

    override func layout() {
        super.layout()
        emptyLabel?.frame = CGRect(x: 0, y: 9, width: bounds.width, height: 18)
        for (index, cell) in cells.enumerated() {
            let row = index / shape.columns
            let column = index % shape.columns
            cell.frame = CGRect(x: CGFloat(column) * Self.cellSize.width, y: CGFloat(row) * Self.cellSize.height,
                                width: Self.cellSize.width, height: Self.cellSize.height)
        }
    }
}

/// One app: icon, name, hover highlight, launches on click.
final class AppCellView: NSView {
    private let app: FolderApp
    private let onLaunch: (FolderApp) -> Void
    private let imageView = NSImageView()
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(app: FolderApp, onLaunch: @escaping (FolderApp) -> Void) {
        self.app = app
        self.onLaunch = onLaunch
        label = NSTextField(labelWithString: app.name)
        super.init(frame: .zero)
        imageView.image = NSWorkspace.shared.icon(forFile: app.path)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 11)
        label.textColor = NSColor(white: 1, alpha: 0.92)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(imageView)
        addSubview(label)
        toolTip = app.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(app.name)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        imageView.frame = CGRect(x: (bounds.width - 48) / 2, y: 6, width: 48, height: 48)
        label.frame = CGRect(x: 3, y: 57, width: bounds.width - 6, height: 15)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering || pressed else { return }
        NSColor(white: 1, alpha: pressed ? 0.22 : 0.12).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 9, yRadius: 9).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressed = false
    }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { onLaunch(app) }
    }

    override func accessibilityPerformPress() -> Bool {
        onLaunch(app)
        return true
    }
}

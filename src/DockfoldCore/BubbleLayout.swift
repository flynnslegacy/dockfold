import CoreGraphics
import Foundation

public enum DockEdge: String, Sendable {
    case bottom, left, right
}

public struct GridShape: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

/// The Dock settings that decide where the bubble goes.
public struct DockMetrics: Equatable, Sendable {
    public var edge: DockEdge
    public var tileSize: CGFloat
    public var magnification: Bool
    public var largeSize: CGFloat
    public var autohide: Bool

    public init(edge: DockEdge = .bottom, tileSize: CGFloat = 48, magnification: Bool = false,
                largeSize: CGFloat = 64, autohide: Bool = false) {
        self.edge = edge
        self.tileSize = tileSize
        self.magnification = magnification
        self.largeSize = largeSize
        self.autohide = autohide
    }

    /// Reads the values stored under `com.apple.dock`.
    public init(preferences: [String: Any]) {
        self.init()
        if let raw = preferences["orientation"] as? String, let edge = DockEdge(rawValue: raw) { self.edge = edge }
        if let size = (preferences["tilesize"] as? NSNumber)?.doubleValue { tileSize = CGFloat(size) }
        magnification = (preferences["magnification"] as? NSNumber)?.boolValue ?? false
        if let size = (preferences["largesize"] as? NSNumber)?.doubleValue { largeSize = CGFloat(size) }
        autohide = (preferences["autohide"] as? NSNumber)?.boolValue ?? false
    }
}

public struct BubblePlacement: Equatable, Sendable {
    /// Window frame, arrow included.
    public let frame: CGRect
    public let edge: DockEdge
    /// Arrow position along the side facing the Dock, from the frame's left (bottom Dock) or bottom (side Dock).
    public let arrowOffset: CGFloat
}

public enum BubbleLayout {
    public static let arrowLength: CGFloat = 9
    public static let arrowHalfWidth: CGFloat = 9
    public static let cornerRadius: CGFloat = 14
    public static let screenMargin: CGFloat = 8
    public static let maxColumns = 5
    /// Dock height around an icon (background padding).
    static let dockPadding: CGFloat = 16
    static let gap: CGFloat = 4

    /// Balanced grid: one row up to 5 apps, then rows of similar length.
    public static func grid(forCount count: Int, maxColumns: Int = maxColumns) -> GridShape {
        let n = max(count, 1)
        let rows = Int((Double(n) / Double(maxColumns)).rounded(.up))
        let columns = Int((Double(n) / Double(rows)).rounded(.up))
        return GridShape(columns: columns, rows: rows)
    }

    /// Distance from the screen edge to the arrow tip, so the bubble clears the (possibly magnified) Dock.
    public static func dockInset(screenFrame: CGRect, visibleFrame: CGRect, metrics: DockMetrics) -> CGFloat {
        let reserved: CGFloat
        switch metrics.edge {
        case .bottom: reserved = visibleFrame.minY - screenFrame.minY
        case .left: reserved = visibleFrame.minX - screenFrame.minX
        case .right: reserved = screenFrame.maxX - visibleFrame.maxX
        }
        let icon = metrics.magnification ? max(metrics.tileSize, metrics.largeSize) : metrics.tileSize
        return max(reserved, icon + dockPadding) + gap
    }

    public static func place(contentSize: CGSize, anchor: CGPoint, edge: DockEdge, dockInset: CGFloat,
                             screen: CGRect) -> BubblePlacement {
        switch edge {
        case .bottom:
            let size = CGSize(width: contentSize.width, height: contentSize.height + arrowLength)
            let x = clamp(anchor.x - size.width / 2, screen.minX + screenMargin, screen.maxX - screenMargin - size.width)
            let frame = CGRect(origin: CGPoint(x: x, y: screen.minY + dockInset), size: size)
            return BubblePlacement(frame: frame, edge: edge, arrowOffset: arrowOffset(anchor.x - x, extent: size.width))
        case .left, .right:
            let size = CGSize(width: contentSize.width + arrowLength, height: contentSize.height)
            let y = clamp(anchor.y - size.height / 2, screen.minY + screenMargin, screen.maxY - screenMargin - size.height)
            let x = edge == .left ? screen.minX + dockInset : screen.maxX - dockInset - size.width
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            return BubblePlacement(frame: frame, edge: edge, arrowOffset: arrowOffset(anchor.y - y, extent: size.height))
        }
    }

    static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        high < low ? low : min(max(value, low), high)
    }

    static func arrowOffset(_ raw: CGFloat, extent: CGFloat) -> CGFloat {
        let low = cornerRadius + arrowHalfWidth
        let high = extent - low
        return high < low ? extent / 2 : min(max(raw, low), high)
    }
}

/// Outline of the bubble: rounded rectangle with an arrow pointing at the Dock.
public enum BubbleShape {
    public static func bodyRect(in rect: CGRect, edge: DockEdge, arrowLength: CGFloat = BubbleLayout.arrowLength) -> CGRect {
        switch edge {
        case .bottom: return CGRect(x: rect.minX, y: rect.minY + arrowLength, width: rect.width, height: rect.height - arrowLength)
        case .left: return CGRect(x: rect.minX + arrowLength, y: rect.minY, width: rect.width - arrowLength, height: rect.height)
        case .right: return CGRect(x: rect.minX, y: rect.minY, width: rect.width - arrowLength, height: rect.height)
        }
    }

    public static func path(in rect: CGRect, edge: DockEdge, arrowOffset: CGFloat,
                            radius: CGFloat = BubbleLayout.cornerRadius,
                            arrowLength: CGFloat = BubbleLayout.arrowLength,
                            arrowHalfWidth: CGFloat = BubbleLayout.arrowHalfWidth) -> CGPath {
        // Work in "edge space": u runs along the side facing the Dock, v moves away from it.
        let along = edge == .bottom ? rect.width : rect.height
        let depth = edge == .bottom ? rect.height : rect.width
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            switch edge {
            case .bottom: return CGPoint(x: rect.minX + u, y: rect.minY + v)
            case .left: return CGPoint(x: rect.minX + v, y: rect.minY + u)
            case .right: return CGPoint(x: rect.maxX - v, y: rect.minY + u)
            }
        }
        let r = max(0, min(radius, (depth - arrowLength) / 2, along / 2))
        let a = arrowOffset
        let path = CGMutablePath()
        path.move(to: point(a - arrowHalfWidth, arrowLength))
        path.addLine(to: point(a, 0))
        path.addLine(to: point(a + arrowHalfWidth, arrowLength))
        path.addArc(tangent1End: point(along, arrowLength), tangent2End: point(along, depth), radius: r)
        path.addArc(tangent1End: point(along, depth), tangent2End: point(0, depth), radius: r)
        path.addArc(tangent1End: point(0, depth), tangent2End: point(0, arrowLength), radius: r)
        path.addArc(tangent1End: point(0, arrowLength), tangent2End: point(a - arrowHalfWidth, arrowLength), radius: r)
        path.closeSubpath()
        return path
    }
}

/// Geometry of the folder icon: Mac icon grid with a 3×3 grid of mini icons, like iPhone folders.
public enum FolderIconLayout {
    public static let columns = 3
    /// App icons have transparent margins; drawing them this much larger makes their body fill the cell.
    public static let iconBleed: CGFloat = 0.121

    public static func bodyRect(canvas: CGFloat) -> CGRect {
        let inset = canvas * 100 / 1024
        return CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    }

    public static func cornerRadius(canvas: CGFloat) -> CGFloat { canvas * 185.4 / 1024 }

    public static func miniIconRects(count: Int, canvas: CGFloat) -> [CGRect] {
        let body = bodyRect(canvas: canvas)
        let padding = body.width * 0.13
        let gap = body.width * 0.05
        let cell = (body.width - 2 * padding - CGFloat(columns - 1) * gap) / CGFloat(columns)
        return (0..<min(max(count, 0), columns * columns)).map { index in
            let row = index / columns
            let column = index % columns
            let x = body.minX + padding + CGFloat(column) * (cell + gap)
            let y = body.maxY - padding - cell - CGFloat(row) * (cell + gap)
            return CGRect(x: x, y: y, width: cell, height: cell)
        }
    }
}

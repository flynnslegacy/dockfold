import AppKit
import SwiftUI
import DockfoldCore

/// Draws the folder icons (frosted squircle with a 3×3 grid of app icons) and Dockfold's own icon.
struct IconRenderer: Sendable {
    private static let iconsetSizes: [(name: String, pixels: Int)] = [
        ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
        ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
        ("512x512", 512), ("512x512@2x", 1024)
    ]

    /// Folder icons are static images: they follow the appearance the Mac has when they are built.
    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// The background must be opaque and shaped like a Mac icon, otherwise macOS 26+
    /// shrinks the icon into a grey container in the Dock.
    func folderBitmap(apps: [FolderApp], pixels: Int, dark: Bool = IconRenderer.systemIsDark) -> NSBitmapImageRep {
        draw(pixels: pixels) { canvas in
            let body = FolderIconLayout.bodyRect(canvas: canvas)
            let radius = FolderIconLayout.cornerRadius(canvas: canvas)
            let shape = Self.squircle(body, radius: radius)
            let top = dark ? NSColor(srgbRed: 0.38, green: 0.38, blue: 0.41, alpha: 1) : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
            let bottom = dark ? NSColor(srgbRed: 0.25, green: 0.25, blue: 0.28, alpha: 1) : NSColor(srgbRed: 0.80, green: 0.81, blue: 0.84, alpha: 1)
            NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: -90)

            let line = max(1, canvas / 256)
            let rim = Self.squircle(body.insetBy(dx: line / 2, dy: line / 2), radius: radius - line / 2)
            rim.lineWidth = line
            NSColor(white: dark ? 1 : 0, alpha: dark ? 0.14 : 0.08).setStroke()
            rim.stroke()

            // Mini icons use the icon style chosen in System Settings, like the rest of the Dock.
            let icons = Array(apps.prefix(FolderIconLayout.columns * FolderIconLayout.columns))
            for (rect, app) in zip(FolderIconLayout.miniIconRects(count: icons.count, canvas: canvas), icons) {
                NSGraphicsContext.saveGraphicsState()
                Self.squircle(rect, radius: rect.width * 0.225).addClip()
                let bleed = rect.width * FolderIconLayout.iconBleed
                NSWorkspace.shared.icon(forFile: app.path).draw(in: rect.insetBy(dx: -bleed, dy: -bleed),
                                                                from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    /// Dockfold's icon: a warm gradient squircle holding a 3×3 grid of light tiles.
    func appIconBitmap(pixels: Int) -> NSBitmapImageRep {
        draw(pixels: pixels) { canvas in
            let body = FolderIconLayout.bodyRect(canvas: canvas)
            let radius = FolderIconLayout.cornerRadius(canvas: canvas)
            let shape = Self.squircle(body, radius: radius)
            let gradient = NSGradient(colors: [
                NSColor(srgbRed: 0.33, green: 0.20, blue: 0.70, alpha: 1),
                NSColor(srgbRed: 0.80, green: 0.40, blue: 0.55, alpha: 1),
                NSColor(srgbRed: 0.98, green: 0.70, blue: 0.47, alpha: 1)
            ])
            gradient?.draw(in: shape, angle: -60)
            let alphas: [CGFloat] = [0.95, 0.8, 0.65, 0.8, 0.65, 0.5, 0.65, 0.5, 0.35]
            for (rect, alpha) in zip(FolderIconLayout.miniIconRects(count: 9, canvas: canvas), alphas) {
                NSColor(white: 1, alpha: alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.25, yRadius: rect.width * 0.25).fill()
            }
        }
    }

    /// Rounded rectangle with Apple's continuous corners, like system icons.
    static func squircle(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(cgPath: RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
    }

    func previewImage(apps: [FolderApp], points: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(folderBitmap(apps: apps, pixels: Int(points * 2)))
        return image
    }

    func writeFolderICNS(apps: [FolderApp], to url: URL) throws {
        try writeICNS(to: url) { folderBitmap(apps: apps, pixels: $0) }
    }

    func exportAppIconset(to directory: URL) throws {
        try writeIconset(to: directory) { appIconBitmap(pixels: $0) }
    }

    private func writeICNS(to url: URL, render: (Int) -> NSBitmapImageRep) throws {
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
        defer { try? FileManager.default.removeItem(at: iconset) }
        try writeIconset(to: iconset, render: render)
        try ProcessRunner.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", url.path])
    }

    private func writeIconset(to directory: URL, render: (Int) -> NSBitmapImageRep) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in Self.iconsetSizes {
            guard let png = render(size.pixels).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: directory.appendingPathComponent("icon_\(size.name).png"))
        }
    }

    private func draw(pixels: Int, _ body: (CGFloat) -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        context?.imageInterpolation = .high
        NSGraphicsContext.current = context
        body(CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

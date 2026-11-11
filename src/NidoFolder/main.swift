import AppKit

// One copy of this launcher lives in each folder's bundle. Its Dock tile is the folder icon;
// launching it (or clicking the tile again) opens the bubble with the folder's apps.
let application = NSApplication.shared
let delegate = FolderAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

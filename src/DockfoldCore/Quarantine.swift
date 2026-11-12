import Darwin
import Foundation

/// Downloaded apps carry the `com.apple.quarantine` attribute, and copying a file keeps it.
/// Folder launchers are copied from Dockfold's own bundle then re-signed locally, so they lose the
/// notarization ticket: if they stayed quarantined, Gatekeeper would refuse to open them.
public enum Quarantine {
    public static let attribute = "com.apple.quarantine"

    /// Removes the attribute from `url` and everything inside it. Returns how many items had it.
    @discardableResult
    public static func strip(at url: URL) -> Int {
        var items = [url]
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let item as URL in enumerator { items.append(item) }
        }
        return items.filter { removexattr($0.path, attribute, XATTR_NOFOLLOW) == 0 }.count
    }

    public static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
}

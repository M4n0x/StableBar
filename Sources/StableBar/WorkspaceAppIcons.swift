import AppKit

@MainActor
final class WorkspaceAppIcons {
    // Fresh NSWorkspace images compare unequal in SwiftUI, even for the same icon.
    // Keep their identity stable while hover and workspace animations redraw the row.
    private var images: [String: NSImage] = [:]
    private let load: (String) -> NSImage?

    init(load: @escaping (String) -> NSImage? = { bundleID in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }) {
        self.load = load
    }

    func image(for bundleID: String) -> NSImage? {
        if let image = images[bundleID] { return image }
        guard let image = load(bundleID) else { return nil }
        images[bundleID] = image
        return image
    }
}

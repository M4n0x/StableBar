import AppKit
@preconcurrency import ApplicationServices
import Observation
import SwiftUI

struct AppMenuItem: Hashable {
    let title: String
    let element: AXUIElement
}

struct AppMenuEntry {
    let title: String
    let element: AXUIElement
    let isEnabled: Bool
    let isChecked: Bool
    let hasSubmenu: Bool
}

@MainActor @Observable
final class AppMenu: NSObject {
    private(set) var appleMenu: AppMenuItem?
    private(set) var items: [AppMenuItem] = []
    private(set) var isTrusted: Bool
    @ObservationIgnored private let checkAccess: () -> Bool
    @ObservationIgnored private let readAttribute: @Sendable (String, AXUIElement) -> CFTypeRef?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var app: NSRunningApplication?
    @ObservationIgnored private var submenus: [PopupPanel] = []
    @ObservationIgnored private(set) var readTask: Task<Void, Never>?

    init(checkAccess: @escaping () -> Bool = { AXIsProcessTrusted() },
         readAttribute: @escaping @Sendable (String, AXUIElement) -> CFTypeRef? = { name, element in
             var value: CFTypeRef?
             guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
             return value
         },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.checkAccess = checkAccess
        self.readAttribute = readAttribute
        self.sleep = sleep
        isTrusted = checkAccess()
        super.init()
    }

    func read(_ app: NSRunningApplication?) {
        if let app, app.processIdentifier == ProcessInfo.processInfo.processIdentifier || app.bundleIdentifier == "org.stablebar.app" { return }
        readTask?.cancel()
        self.app = app
        let sleep = sleep
        readTask = Task { [weak self] in
            do {
                for delay in [0, 250, 500, 1000, 2000] {
                    try await sleep(.milliseconds(delay))
                    guard let self else { return }
                    if try await readItems() { return }
                }
            } catch {}
        }
    }

    private func readItems() async throws -> Bool {
        isTrusted = checkAccess()
        var next: [AppMenuItem] = []
        if isTrusted, let app {
            let pid = app.processIdentifier
            let readAttribute = readAttribute
            let items = await Task.detached { () -> [AppMenuItem]? in
                let element = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(element, 0.1)
                guard let menuBar = readAttribute(kAXMenuBarAttribute, element),
                      let children = readAttribute(kAXChildrenAttribute, menuBar as! AXUIElement) as? [AXUIElement] else { return nil }
                var items: [AppMenuItem] = []
                for item in children {
                    guard let title = readAttribute(kAXTitleAttribute, item) as? String else { return nil }
                    items.append(AppMenuItem(title: title, element: item))
                }
                return items
            }.value
            try Task.checkCancellation()
            guard let items else { return false }
            next = items
        }
        if next.first != appleMenu { appleMenu = next.first }
        if Array(next.dropFirst()) != items { items = Array(next.dropFirst()) }
        return true
    }

    func refresh() {
        read(app)
    }

    func popup(for item: AppMenuItem) -> PopupConfiguration? {
        var pid: pid_t = 0
        AXUIElementGetPid(item.element, &pid)
        guard pid == app?.processIdentifier else { return nil }
        return popup(entries(of: item.element))
    }

    private func popup(_ entries: [AppMenuEntry]) -> PopupConfiguration {
        var popup = PopupConfiguration(style: WidgetStyle(paddingHorizontal: 5, paddingVertical: 5, spacing: 0, width: 260),
                                       layout: PopupBlock(content: .appMenu(entries)))
        popup.alignment = .leading
        return popup
    }

    private func entries(of element: AXUIElement) -> [AppMenuEntry] {
        guard let menu = children(of: element).first else { return [] }
        return children(of: menu).map { child in
            AppMenuEntry(title: attribute(kAXTitleAttribute, of: child) as? String ?? "", element: child,
                         isEnabled: attribute(kAXEnabledAttribute, of: child) as? Bool == true,
                         isChecked: attribute(kAXMenuItemMarkCharAttribute, of: child) as? String != nil,
                         hasSubmenu: !children(of: child).isEmpty)
        }
    }

    func openSubmenu<Content: View>(_ element: AXUIElement?, beside row: NSView, content: (PopupConfiguration) -> Content) {
        let window = row.window!
        closeSubmenus(after: window)
        guard let element else { return }
        let popup = popup(entries(of: element))
        let host = NSHostingView(rootView: content(popup).frame(width: popup.style.width!))
        let frame = window.convertToScreen(row.convert(row.bounds, to: nil))
        let screen = window.screen!.visibleFrame
        let size = NSSize(width: popup.style.width!, height: min(host.fittingSize.height, screen.height - 16))
        let gap = popup.style.paddingHorizontal! + 4
        let x = frame.maxX + gap + size.width <= screen.maxX ? frame.maxX + gap : frame.minX - gap - size.width
        let panel = PopupPanel(contentRect: NSRect(x: x, y: max(frame.maxY + popup.style.paddingVertical! - size.height, screen.minY + 8),
                                                   width: size.width, height: size.height),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "App submenu"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = window.level
        panel.collectionBehavior = window.collectionBehavior
        panel.appearance = window.appearance
        panel.contentView = host
        (submenus.first?.parent ?? window).addChildWindow(panel, ordered: .above)
        submenus.append(panel)
    }

    func closeSubmenus(after window: NSWindow?) {
        let kept = submenus.firstIndex { $0 === window }.map { $0 + 1 } ?? 0
        for panel in submenus[kept...] {
            panel.parent?.removeChildWindow(panel)
            panel.close()
        }
        submenus.removeSubrange(kept...)
    }

    func press(_ element: AXUIElement) {
        Task.detached { AXUIElementPerformAction(element, kAXPressAction as CFString) }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        return readAttribute(name, element)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }
}

import AppKit
@preconcurrency import ApplicationServices
import Observation

struct AppMenuItem: Hashable {
    let title: String
    let element: AXUIElement
}

@MainActor @Observable
final class AppMenu: NSObject, NSMenuDelegate {
    private(set) var appleMenu: AppMenuItem?
    private(set) var items: [AppMenuItem] = []
    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored private var app: NSRunningApplication?
    @ObservationIgnored private var menus: [NSMenu: AXUIElement] = [:]

    func read(_ app: NSRunningApplication?) {
        if let app, app.processIdentifier == ProcessInfo.processInfo.processIdentifier || app.bundleIdentifier == "org.stablebar.app" { return }
        self.app = app
        isTrusted = AXIsProcessTrusted()
        var next: [AppMenuItem] = []
        if isTrusted, let app {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            if let menuBar = attribute(kAXMenuBarAttribute, of: element) {
                next = children(of: menuBar as! AXUIElement).compactMap { item in
                    (attribute(kAXTitleAttribute, of: item) as? String).map { AppMenuItem(title: $0, element: item) }
                }
            }
        }
        if next.first != appleMenu { appleMenu = next.first }
        if Array(next.dropFirst()) != items { items = Array(next.dropFirst()) }
    }

    func refresh() {
        read(app)
    }

    func open(_ item: AppMenuItem, at location: NSPoint, in view: NSView?) {
        let menu = NSMenu()
        menu.delegate = self
        menus = [menu: item.element]
        menu.popUp(positioning: nil, at: location, in: view)
        menus = [:]
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let element = menus[menu], let source = children(of: element).first else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        for child in children(of: source) {
            guard let title = attribute(kAXTitleAttribute, of: child) as? String, !title.isEmpty else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: #selector(press), keyEquivalent: "")
            item.target = self
            item.representedObject = child
            item.isEnabled = attribute(kAXEnabledAttribute, of: child) as? Bool == true
            item.state = attribute(kAXMenuItemMarkCharAttribute, of: child) as? String == nil ? .off : .on
            if !children(of: child).isEmpty {
                let submenu = NSMenu()
                submenu.delegate = self
                menus[submenu] = child
                item.submenu = submenu
            }
            menu.addItem(item)
        }
    }

    @objc private func press(_ sender: NSMenuItem) {
        let element = sender.representedObject as! AXUIElement
        Task.detached { AXUIElementPerformAction(element, kAXPressAction as CFString) }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }
}

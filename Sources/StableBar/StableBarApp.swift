import AppKit
import SwiftUI

@main
struct StableBarApp {
    @MainActor static func main() {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--trigger" {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(CommandLine.arguments[2]), object: nil, userInfo: nil, deliverImmediately: true)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = BarStore()
    private var panels: [CGDirectDisplayID: BarPanel] = [:]
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "StableBar")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        store.onConfigurationChange = { [weak self] in self?.updatePanels() }
        store.start()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func screensChanged() {
        store.popup.close()
        updatePanels()
        if store.configuration?.widgets.contains(where: { $0.content == .workspaces || $0.display == .active }) == true {
            store.aerospace.start()
        }
    }

    @objc private func woke() {
        screensChanged()
        store.refreshScripts(for: "wake")
    }

    private func updatePanels() {
        guard let config = store.configuration else { return }
        let screens = NSScreen.screens
        let ids = screens.map { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value }
        for (id, panel) in panels where !ids.contains(id) {
            panel.close()
            panels.removeValue(forKey: id)
        }
        for (index, screen) in screens.enumerated() {
            let id = ids[index]
            let panel: BarPanel
            if let existing = panels[id] {
                panel = existing
            } else {
                panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
                panel.title = "StableBar"
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                panel.contentView = NSHostingView(rootView: BarView(store: store, display: BarDisplay(screen: screen)))
                panels[id] = panel
            }
            let host = panel.contentView as! NSHostingView<BarView>
            host.rootView = BarView(store: store, display: BarDisplay(screen: screen))
            let top = screen.frame.maxY
            panel.setFrame(NSRect(x: screen.frame.minX, y: top - config.bar.offset - config.bar.height,
                                  width: screen.frame.width, height: config.bar.height), display: true)
            panel.orderFrontRegardless()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "StableBar", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        addItem("Open configuration…", action: #selector(openConfiguration), to: menu)
        addItem("Reload configuration", action: #selector(reloadConfiguration), to: menu)
        addItem("Reconnect AeroSpace", action: #selector(reconnect), to: menu)
        if let error = store.configurationError ?? store.actionError ?? store.aerospace.error {
            menu.addItem(.separator())
            menu.addItem(withTitle: error, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        addItem("Quit StableBar", action: #selector(quit), to: menu)
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    @objc private func openConfiguration() { store.openConfiguration() }
    @objc private func reloadConfiguration() { store.reloadConfiguration() }
    @objc private func reconnect() { store.aerospace.start() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}

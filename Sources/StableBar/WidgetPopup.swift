import AppKit
import SwiftUI

@MainActor
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WidgetPopup {
    private var panel: PopupPanel?
    private weak var anchor: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func toggle(_ popup: PopupConfiguration, widget: WidgetConfiguration, defaults: WidgetStyle,
                store: BarStore, anchor: NSView) {
        if self.anchor === anchor {
            close()
            return
        }
        close()
        let window = anchor.window!
        let screen = window.screen!
        let frame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let style = popup.style.inheriting(widget.style.inheriting(defaults))
        let appearance = WidgetAppearance(style, defaults: WidgetStyle())
        let shadowInset = appearance.shadowRadius * 2 + 2
        let width = min(popup.style.width ?? 360, screen.visibleFrame.width - shadowInset * 2 - 16)
        let height = min(popup.height, frame.minY - screen.visibleFrame.minY - shadowInset * 2 - 8)
        let x = min(max(frame.midX - width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
        let panel = PopupPanel(contentRect: NSRect(x: x - shadowInset, y: frame.minY - height - 6 - shadowInset,
                                                  width: width + shadowInset * 2, height: height + shadowInset * 2),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "\(widget.id) popup"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.contentView = NSHostingView(rootView: PopupView(popup: popup, style: style, store: store, widget: widget)
            .shadow(color: appearance.shadowColor, radius: appearance.shadowRadius, y: 1)
            .padding(shadowInset))
        self.panel = panel
        self.anchor = anchor
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        self.close()
                        return true
                    }
                } else if event.window !== self.panel {
                    let onAnchor = event.window === anchor.window && anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
                    if !onAnchor { self.close() }
                }
                return false
            }
            return handled ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        panel?.close()
        panel = nil
        anchor = nil
    }

    func removeAnchor(_ view: NSView) {
        if anchor === view { close() }
    }
}

struct PopupAnchor: NSViewRepresentable {
    let view: NSView
    let popup: WidgetPopup

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> WidgetPopup { popup }

    static func dismantleNSView(_ nsView: NSView, coordinator: WidgetPopup) {
        coordinator.removeAnchor(nsView)
    }
}

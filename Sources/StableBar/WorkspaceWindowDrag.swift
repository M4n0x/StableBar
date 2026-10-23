import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class WorkspaceWindowDragSession {
    struct Payload: Equatable {
        let token = UUID()
        let source: WorkspaceSource
        let workspace: String
        let windows: [WorkspaceWindow]
    }

    static let typeIdentifier = "com.stablebar.workspace-window-move"
    static let contentType = UTType(exportedAs: typeIdentifier)
    private(set) var active: Payload?
    var target: String?

    func begin(source: WorkspaceSource, windows: [WorkspaceWindow]) -> Payload? {
        guard source.supportsWindowMoves, let workspace = windows.first?.app.workspace,
              windows.allSatisfy({ $0.app.workspace == workspace }) else { return nil }
        let payload = Payload(source: source, workspace: workspace, windows: windows)
        active = payload
        target = nil
        return payload
    }

    func end(_ payload: Payload) {
        guard active == payload else { return }
        active = nil
        target = nil
    }
}

/// Keep the button's keyboard and accessibility actions, while AppKit distinguishes
/// a click from a drag and reports cancellation, Escape and drops outside the bar.
struct WorkspaceWindowDragSource<Content: View>: NSViewRepresentable {
    let store: WorkspaceStore
    let windows: [WorkspaceWindow]
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> WorkspaceWindowDragSourceView {
        WorkspaceWindowDragSourceView(rootView: AnyView(content()))
    }

    func updateNSView(_ view: WorkspaceWindowDragSourceView, context: Context) {
        view.rootView = AnyView(content().environment(\.self, context.environment))
        view.store = store
        view.windows = windows
        view.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WorkspaceWindowDragSourceView, context: Context) -> CGSize? {
        nsView.fittingSize
    }
}

class WorkspaceWindowDragSourceView: WidgetHostingView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType(WorkspaceWindowDragSession.typeIdentifier)
    weak var store: WorkspaceStore?
    var windows: [WorkspaceWindow] = []
    var action: () -> Void = {}
    private var mouseDownPoint: NSPoint?
    private var drag: (session: WorkspaceWindowDragSession, payload: WorkspaceWindowDragSession.Payload)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if let event = NSApp?.currentEvent, ![NSEvent.EventType.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseUp(with event: NSEvent) {
        let clicked = mouseDownPoint != nil && bounds.contains(convert(event.locationInWindow, from: nil))
        mouseDownPoint = nil
        if clicked { action() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let store,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
        mouseDownPoint = nil
        guard let payload = store.windowDrag.begin(source: store.source, windows: windows) else { return }
        drag = (store.windowDrag, payload)
        let item = NSPasteboardItem()
        item.setString(payload.token.uuidString, forType: Self.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginWindowDrag(with: draggingItem, event: event)
    }

    func beginWindowDrag(with item: NSDraggingItem, event: NSEvent) {
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endWindowDrag()
    }

    func endWindowDrag() {
        if let drag { drag.session.end(drag.payload) }
        drag = nil
        mouseDownPoint = nil
    }
}

struct WorkspaceWindowDrop: ViewModifier, DropDelegate {
    let store: WorkspaceStore
    let workspace: String
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled && store.source.supportsWindowMoves {
            content.onDrop(of: [WorkspaceWindowDragSession.contentType], delegate: self)
        } else {
            content
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        enabled && store.source.supportsWindowMoves
            && info.hasItemsConforming(to: [WorkspaceWindowDragSession.contentType])
            && store.windowDrag.active.map { store.canMoveWindows($0, to: workspace) } == true
    }

    func dropEntered(info: DropInfo) {
        if validateDrop(info: info) { store.windowDrag.target = workspace }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let accepts = validateDrop(info: info)
        if !accepts && store.windowDrag.target == workspace { store.windowDrag.target = nil }
        return DropProposal(operation: accepts ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
        if store.windowDrag.target == workspace { store.windowDrag.target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        // AppKit allows one drag at a time. Only our native source creates this
        // live session; commands use its captured windows, never external data.
        guard validateDrop(info: info), let payload = store.windowDrag.active else { return false }
        return store.moveWindows(payload, to: workspace) != nil
    }
}

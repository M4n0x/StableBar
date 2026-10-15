import SwiftUI

struct BarView: View {
    let store: BarStore
    let monitor: Int

    var body: some View {
        Group {
            if let config = store.configuration {
                ZStack {
                    config.bar.background.color
                    HStack(spacing: config.bar.spacing) {
                        widgets(at: .left, in: config)
                        Spacer(minLength: 20)
                        widgets(at: .right, in: config)
                        if let error = store.configurationError ?? store.actionError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(error)
                        }
                    }
                    .padding(.horizontal, config.bar.inset)
                    HStack(spacing: config.bar.spacing) {
                        widgets(at: .center, in: config)
                    }
                }
            }
        }
        .contextMenu {
            Text("StableBar")
            Button("Open configuration…") { store.openConfiguration() }
            Button("Reload configuration") { store.reloadConfiguration() }
            Button("Reconnect AeroSpace") { store.aerospace.start() }
            if let error = store.configurationError ?? store.actionError ?? store.aerospace.error {
                Divider()
                Text(error)
            }
            Divider()
            Button("Quit StableBar") { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder
    private func widgets(at position: WidgetPosition, in config: Configuration) -> some View {
        ForEach(config.widgets.filter { $0.position == position }) { widget in
            if store.scripts[widget.id]?.output.hidden != true || store.scripts[widget.id]?.error != nil {
                WidgetView(widget: widget, defaults: config.defaults, store: store,
                           monitor: monitor, animationDuration: config.bar.animationDuration)
            }
        }
    }
}

struct WidgetView: View {
    let widget: WidgetConfiguration
    let defaults: WidgetStyle
    let store: BarStore
    let monitor: Int
    let animationDuration: Double
    @State private var hovered = false
    @State private var popupAnchor = NSView()

    private var popup: PopupConfiguration? {
        if let popup = widget.popup { return popup }
        if let menu = store.scripts[widget.id]?.output.menu ?? widget.menu, !menu.isEmpty {
            return PopupConfiguration(
                height: min(Double(menu.count) * 50 + 24, 480),
                style: WidgetStyle(fontSize: 12, paddingHorizontal: 12, paddingVertical: 12, spacing: 4),
                layout: PopupBlock(content: .menu)
            )
        }
        return nil
    }

    var body: some View {
        let appearance = WidgetAppearance(widget.style, defaults: defaults)
        Group {
            if let popup {
                Button {
                    store.popup.toggle(popup, widget: widget, defaults: defaults, store: store, anchor: popupAnchor)
                } label: { content(appearance) }
                .buttonStyle(.plain)
            } else if let command = widget.onClick {
                Button { store.runAction(command, widget: widget) } label: { content(appearance) }
                    .buttonStyle(.plain)
            } else {
                content(appearance)
            }
        }
        .font(appearance.font)
        .foregroundStyle(appearance.foreground)
        .padding(.horizontal, appearance.paddingHorizontal)
        .padding(.vertical, appearance.paddingVertical)
        .frame(width: appearance.width)
        .background(hovered ? appearance.hoverBackground : appearance.background,
                    in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(appearance.borderColor, lineWidth: appearance.borderWidth)
        }
        .shadow(color: appearance.shadowColor, radius: appearance.shadowRadius, y: 1)
        .background(PopupAnchor(view: popupAnchor, popup: store.popup))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: animationDuration), value: hovered)
        .accessibilityIdentifier(widget.id)
    }

    @ViewBuilder
    private func content(_ appearance: WidgetAppearance) -> some View {
        switch widget.content {
        case .workspaces:
            WorkspaceView(aerospace: store.aerospace, monitor: monitor,
                          appearance: appearance, animationDuration: animationDuration)
        case .activeApp:
            HStack(spacing: appearance.spacing) {
                if let icon = store.activeApp?.icon {
                    Image(nsImage: icon).resizable().frame(width: appearance.iconSize, height: appearance.iconSize)
                }
                Text(store.activeApp?.localizedName ?? "Desktop").lineLimit(1)
            }
        case let .clock(format):
            TimelineView(.everyMinute) { context in
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = format
                label(formatter.string(from: context.date), icon: widget.icon, appearance: appearance)
                    .monospacedDigit()
            }
        case let .text(text):
            label(text, icon: widget.icon, appearance: appearance)
        case .script:
            if let script = store.scripts[widget.id] {
                HStack(spacing: appearance.spacing) {
                    if script.output.value != nil {
                        Sparkline(samples: script.samples)
                            .stroke(appearance.accent, lineWidth: 1.2)
                            .frame(width: 40, height: 16)
                    }
                    label(script.output.text, icon: script.output.icon ?? widget.icon, appearance: appearance)
                }
                    .foregroundStyle(script.output.color?.color ?? appearance.foreground)
                    .help(script.error ?? script.output.tooltip ?? "")
                    .overlay(alignment: .topTrailing) {
                        if script.error != nil {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.system(size: 8))
                        }
                    }
            }
        }
    }

    private func label(_ text: String, icon: String?, appearance: WidgetAppearance) -> some View {
        HStack(spacing: appearance.spacing) {
            if let icon { Image(systemName: icon).font(.system(size: appearance.iconSize)) }
            if !text.isEmpty { Text(text).lineLimit(1) }
        }
    }
}

struct Sparkline: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, value) in samples.enumerated() {
            let point = CGPoint(x: rect.width * Double(index) / 59,
                                y: rect.height * (1 - min(max(value, 0), 1)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct WorkspaceView: View {
    let aerospace: AeroSpace
    let monitor: Int
    let appearance: WidgetAppearance
    let animationDuration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        let workspaces = aerospace.workspaces.filter { $0.monitor == monitor && ($0.isVisible || !$0.apps.isEmpty) }
        HStack(spacing: appearance.spacing) {
            ForEach(workspaces) { workspace in
                Button { aerospace.select(workspace) } label: {
                    HStack(spacing: 4) {
                        Text(workspace.name)
                        ForEach(workspace.apps) { app in
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 14, height: 14)
                                    .help(app.name)
                            }
                        }
                    }
                    .foregroundStyle(workspace.isFocused ? appearance.accentText : appearance.foreground)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background {
                        if workspace.isFocused {
                            RoundedRectangle(cornerRadius: max(appearance.cornerRadius - 4, 0))
                                .fill(appearance.accent)
                                .matchedGeometryEffect(id: "focused-workspace", in: selection)
                        } else if workspace.isVisible {
                            RoundedRectangle(cornerRadius: max(appearance.cornerRadius - 4, 0))
                                .strokeBorder(appearance.accent, lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Switch to workspace \(workspace.name)")
                .accessibilityLabel("Workspace \(workspace.name)\(workspace.isFocused ? ", focused" : workspace.isVisible ? ", visible" : "")")
                .accessibilityAddTraits(workspace.isFocused ? .isSelected : [])
            }
            if let error = aerospace.error {
                Image(systemName: "exclamationmark.triangle").help(error)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: animationDuration), value: workspaces)
    }
}

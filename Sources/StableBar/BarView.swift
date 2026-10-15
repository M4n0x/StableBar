import SwiftUI

struct BarView: View {
    let store: BarStore
    let display: BarDisplay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let config = store.configuration {
                let style = config.widgets.reduce(config.bar.style) { style, widget in
                    store.scripts[widget.id]?.output.barStyle?.inheriting(style) ?? style
                }
                let notch = display.notch.map { range in
                    config.bar.notchWidth.map { width in
                        let center = (range.lowerBound + range.upperBound) / 2
                        return (center - width / 2)...(center + width / 2)
                    } ?? range
                }
                ZStack {
                    (style.background ?? config.bar.background).color
                    BarLayout(inset: config.bar.inset, spacing: config.bar.spacing,
                              notchSpacing: config.bar.notchSpacing, notch: notch) {
                        HStack(spacing: config.bar.spacing) { widgets(at: .left, in: config) }.fixedSize()
                        HStack(spacing: config.bar.spacing) { widgets(at: .notchLeft, in: config) }.fixedSize()
                        HStack(spacing: config.bar.spacing) { widgets(at: .center, in: config) }.fixedSize()
                        HStack(spacing: config.bar.spacing) { widgets(at: .notchRight, in: config) }.fixedSize()
                        HStack(spacing: config.bar.spacing) {
                            widgets(at: .right, in: config)
                            if let error = store.configurationError ?? store.actionError {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(error)
                            }
                        }.fixedSize()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius ?? 0))
                .overlay(alignment: .bottom) {
                    (style.borderColor?.color ?? .clear).frame(height: style.borderWidth ?? 0)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: config.bar.animationDuration), value: style)
            }
        }
        .contextMenu {
            Text("StableBar")
            Button("Set up StableBar…") { NSApp.sendAction(#selector(AppDelegate.showSetup), to: NSApp.delegate, from: nil) }
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
            let output = store.scripts[widget.id]?.output
            let activeID = store.aerospace.workspaces.first(where: \.isFocused)?.monitor ?? store.activeDisplayID
            if (output?.display ?? widget.display).includes(display, activeID: activeID) {
                if output?.hidden != true || store.scripts[widget.id]?.error != nil {
                    WidgetView(widget: widget, defaults: config.defaults, store: store,
                               monitor: display.id, animationDuration: config.bar.animationDuration)
                }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: WidgetStyle {
        let output = store.scripts[widget.id]?.output
        var style = widget.style.inheriting(defaults)
        for source in store.configuration?.widgets ?? [] {
            if let override = store.scripts[source.id]?.output.widgetStyles?[widget.id] {
                style = override.inheriting(style)
            }
        }
        style = (output?.style ?? WidgetStyle()).inheriting(style)
        if let color = output?.color { style.foreground = color }
        return style
    }

    private var popup: PopupConfiguration? {
        if let popup = widget.popup { return popup }
        if let name = widget.popupName { return store.configuration!.popups[name]! }
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
        let output = store.scripts[widget.id]?.output
        let appearance = WidgetAppearance(style, defaults: WidgetStyle())
        let animation = output?.animation ?? widget.animation ?? WidgetAnimation(duration: animationDuration)
        Group {
            if let popup {
                Button {
                    store.popup.toggle(popup, widget: widget, defaults: defaults, store: store, anchor: popupAnchor)
                } label: { content(appearance) }
                .buttonStyle(.plain)
            } else if let command = output?.onClick ?? widget.onClick {
                Button { store.runAction(command, widget: widget) } label: { content(appearance) }
                    .buttonStyle(.plain)
            } else {
                content(appearance)
            }
        }
        .font(appearance.font)
        .foregroundStyle(hovered ? appearance.hoverForeground : appearance.foreground)
        .padding(.leading, style.paddingLeading ?? appearance.paddingHorizontal)
        .padding(.trailing, style.paddingTrailing ?? appearance.paddingHorizontal)
        .padding(.top, style.paddingTop ?? appearance.paddingVertical)
        .padding(.bottom, style.paddingBottom ?? appearance.paddingVertical)
        .frame(width: appearance.width, height: style.height.map { CGFloat($0) })
        .background(hovered ? appearance.hoverBackground : appearance.background,
                    in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(appearance.borderColor, lineWidth: appearance.borderWidth)
        }
        .shadow(color: appearance.shadowColor, radius: appearance.shadowRadius, y: 1)
        .overlay(alignment: .bottom) {
            if let overlay = widget.overlay {
                block(overlay, style: style, fillsWidth: true).allowsHitTesting(false)
            }
        }
        .offset(x: style.offsetX ?? 0, y: style.offsetY ?? 0)
        .opacity(style.opacity ?? 1)
        .background(PopupAnchor(view: popupAnchor, popup: store.popup))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : animation.value, value: hovered)
        .animation(reduceMotion ? nil : animation.value, value: style)
        .accessibilityIdentifier(widget.id)
    }

    @ViewBuilder
    private func content(_ appearance: WidgetAppearance) -> some View {
        if let layout = widget.layout {
            block(layout, style: style, fillsWidth: false)
                .help(store.scripts[widget.id]?.error ?? store.scripts[widget.id]?.output.tooltip ?? "")
                .overlay(alignment: .topTrailing) {
                    if store.scripts[widget.id]?.error != nil {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.system(size: 8))
                    }
                }
        } else {
            switch widget.content {
            case .workspaces:
                WorkspaceView(aerospace: store.aerospace, monitor: monitor,
                              appearance: appearance, animationDuration: animationDuration,
                              configuration: widget.workspace, animation: widget.animation, defaults: widget.style.inheriting(defaults))
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
                        .foregroundStyle(hovered ? appearance.hoverForeground : appearance.foreground)
                        .help(script.error ?? script.output.tooltip ?? "")
                        .overlay(alignment: .topTrailing) {
                            if script.error != nil {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.system(size: 8))
                            }
                        }
                }
            }
        }
    }

    private func block(_ block: PopupBlock, style: WidgetStyle, fillsWidth: Bool) -> some View {
        let script = store.scripts[widget.id]
        var fields = script?.output.fields ?? [:]
        switch widget.content {
        case let .text(text): fields["text"] = text
        case .activeApp: fields["text"] = store.activeApp?.localizedName ?? "Desktop"
        case .script:
            fields["text"] = script?.output.text ?? "…"
            fields["icon"] = script?.output.icon ?? widget.icon ?? ""
        default: break
        }
        return PopupBlockView(block: block, inheritedStyle: style, fields: fields,
                              lists: script?.output.lists ?? [:], samples: script?.samples ?? [],
                              menu: script?.output.menu ?? widget.menu ?? [], values: script?.output.values ?? [:],
                              targets: script?.output.targets ?? [:], styles: script?.output.styles ?? [:],
                              series: script?.output.series ?? [:],
                              fillsWidth: fillsWidth) { store.runAction($0, widget: widget) }
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
    var configuration: WorkspaceConfiguration?
    var animation: WidgetAnimation?
    var defaults = WidgetStyle()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var hoveredWorkspace: String?

    var body: some View {
        let workspaces = aerospace.workspaces.filter {
            $0.monitor == monitor && (configuration?.showEmpty == true || $0.isVisible || !$0.apps.isEmpty)
        }
        let indicator = configuration?.indicator ?? .background
        let indicatorStyle = configuration?.indicatorStyle ?? WidgetStyle()
        HStack(spacing: appearance.spacing) {
            ForEach(workspaces) { workspace in
                let base = configuration?.style ?? WidgetStyle()
                let stateStyle = if workspace.isFocused { configuration?.focusedStyle }
                    else if workspace.isVisible { configuration?.visibleStyle }
                    else if workspace.apps.isEmpty { configuration?.emptyStyle }
                    else { nil as WidgetStyle? }
                let style = (stateStyle ?? WidgetStyle()).inheriting(base)
                let appStateStyle = workspace.isFocused ? configuration?.focusedAppStyle : workspace.isVisible ? configuration?.visibleAppStyle : nil
                let appStyle = (appStateStyle ?? WidgetStyle()).inheriting(configuration?.appStyle ?? WidgetStyle())
                Button { aerospace.select(workspace) } label: {
                    HStack(spacing: style.spacing ?? 4) {
                        Text(workspace.name)
                        if configuration?.showApps != false {
                            ForEach(workspace.apps) { app in
                                if let glyph = configuration?.appGlyphs?[app.bundleID] ?? configuration?.appGlyphs?[app.name] ?? configuration?.appGlyphs?["*"] {
                                    Text(glyph)
                                        .font(WidgetAppearance(appStyle, defaults: WidgetStyle()).font)
                                        .foregroundStyle((hoveredWorkspace == workspace.name ? appStyle.hoverForeground?.color : nil)
                                                         ?? appStyle.foreground?.color ?? appearance.foreground)
                                        .help(app.name)
                                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().frame(width: appStyle.width ?? 14, height: appStyle.height ?? 14)
                                        .help(app.name)
                                }
                            }
                        }
                    }
                    .font(WidgetAppearance(style, defaults: defaults).font)
                    .foregroundStyle((hoveredWorkspace == workspace.name ? style.hoverForeground?.color : nil)
                                     ?? style.foreground?.color ?? (workspace.isFocused ? appearance.accentText : appearance.foreground))
                    .padding(.leading, style.paddingLeading ?? style.paddingHorizontal ?? 7)
                    .padding(.trailing, style.paddingTrailing ?? style.paddingHorizontal ?? 7)
                    .frame(width: style.width.map { CGFloat($0) }, height: style.height ?? 22)
                    .background {
                        if indicator == .background && workspace.isFocused {
                            RoundedRectangle(cornerRadius: style.cornerRadius ?? max(appearance.cornerRadius - 4, 0))
                                .fill(style.background?.color ?? appearance.accent)
                                .matchedGeometryEffect(id: "focused-workspace", in: selection)
                        } else if indicator == .background && workspace.isVisible {
                            RoundedRectangle(cornerRadius: style.cornerRadius ?? max(appearance.cornerRadius - 4, 0))
                                .strokeBorder(style.borderColor?.color ?? appearance.accent, lineWidth: style.borderWidth ?? 1)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if indicator == .underline && workspace.isVisible {
                            RoundedRectangle(cornerRadius: indicatorStyle.cornerRadius ?? 0)
                                .fill(indicatorStyle.background?.color ?? appearance.accent)
                                .frame(width: indicatorStyle.width.map { CGFloat($0) }, height: indicatorStyle.height ?? 2)
                                .matchedGeometryEffect(id: "workspace-underline", in: selection)
                                .offset(x: indicatorStyle.offsetX ?? 0, y: indicatorStyle.offsetY ?? 0)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredWorkspace = $0 ? workspace.name : nil }
                .help("Switch to workspace \(workspace.name)")
                .accessibilityLabel("Workspace \(workspace.name)\(workspace.isFocused ? ", focused" : workspace.isVisible ? ", visible" : "")")
                .accessibilityAddTraits(workspace.isFocused ? .isSelected : [])
            }
            if let error = aerospace.error {
                Image(systemName: "exclamationmark.triangle").help(error)
            }
        }
        .animation(reduceMotion ? nil : (animation?.value ?? .smooth(duration: animationDuration)), value: workspaces)
    }
}

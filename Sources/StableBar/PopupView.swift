import SwiftUI

struct PopupView: View {
    let popup: PopupConfiguration
    let style: WidgetStyle
    let store: BarStore
    let widget: WidgetConfiguration

    var body: some View {
        let appearance = WidgetAppearance(style, defaults: WidgetStyle())
        let script = store.scripts[widget.id]
        let fields = script?.output.fields ?? [:]
        let lists = script?.output.lists ?? [:]
        let samples = script?.samples ?? []
        let menu = script?.output.menu ?? widget.menu ?? []
        let error = script?.error ?? store.actionError
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.spacing) {
                PopupBlockView(block: popup.layout, inheritedStyle: style,
                               fields: fields, lists: lists, samples: samples, menu: menu,
                               values: script?.output.values ?? [:], targets: script?.output.targets ?? [:],
                               styles: script?.output.styles ?? [:], series: script?.output.series ?? [:]) { command in
                    if popup.dismissOnAction { store.popup.close() }
                    store.runAction(command, widget: widget)
                }
                if let error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(.horizontal, appearance.paddingHorizontal)
            .padding(.vertical, appearance.paddingVertical)
        }
        .background(appearance.background, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(appearance.borderColor, lineWidth: appearance.borderWidth)
        }
        .accessibilityIdentifier("\(widget.id)-popup")
    }
}

struct PopupBlockView: View {
    let block: PopupBlock
    let inheritedStyle: WidgetStyle
    let fields: [String: String]
    let lists: [String: [[String: String]]]
    let samples: [Double]
    let menu: [WidgetMenuItem]
    var values: [String: Double] = [:]
    var targets: [String: Double] = [:]
    var styles: [String: WidgetStyle] = [:]
    var series: [String: [Double]] = [:]
    var fillsWidth = true
    let runAction: (String) -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        if let field = block.hideWhenEmpty, fields[field, default: ""].isEmpty {
            EmptyView()
        } else {
            styledContent
        }
    }

    private var styledContent: some View {
        let styleName = block.styleField.flatMap { fields[$0] } ?? block.styleSource
        let ownStyle = (styleName.flatMap { styles[$0] } ?? WidgetStyle()).inheriting(block.style)
        let style = ownStyle.inheriting(inheritedStyle)
        let appearance = WidgetAppearance(style, defaults: WidgetStyle())
        let alignment: Alignment = switch block.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        return Group {
            if case .button = block.content {
                content(style, ownStyle: ownStyle, appearance: appearance)
            } else if let command = block.onClickField.flatMap({ fields[$0] }) ?? block.onClick {
                Button { runAction(command) } label: { content(style, ownStyle: ownStyle, appearance: appearance) }
                    .buttonStyle(.plain)
            } else {
                content(style, ownStyle: ownStyle, appearance: appearance)
            }
        }
            .font(appearance.font)
            .foregroundStyle(hovered ? appearance.hoverForeground : appearance.foreground)
            .padding(.leading, ownStyle.paddingLeading ?? ownStyle.paddingHorizontal ?? 0)
            .padding(.trailing, ownStyle.paddingTrailing ?? ownStyle.paddingHorizontal ?? 0)
            .padding(.top, ownStyle.paddingTop ?? ownStyle.paddingVertical ?? 0)
            .padding(.bottom, ownStyle.paddingBottom ?? ownStyle.paddingVertical ?? 0)
            .frame(width: ownStyle.width.map { CGFloat($0) }, height: ownStyle.height.map { CGFloat($0) }, alignment: alignment)
            .frame(maxWidth: fillsWidth && ownStyle.width == nil ? .infinity : nil, alignment: alignment)
            .background((hovered ? ownStyle.hoverBackground ?? ownStyle.background : ownStyle.background)?.color ?? .clear,
                        in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: appearance.cornerRadius)
                    .strokeBorder(ownStyle.borderColor?.color ?? .clear, lineWidth: ownStyle.borderWidth ?? 0)
            }
            .offset(x: ownStyle.offsetX ?? 0, y: ownStyle.offsetY ?? 0)
            .opacity(ownStyle.opacity ?? 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : block.animation?.value, value: ownStyle)
            .animation(reduceMotion ? nil : block.animation?.value, value: hovered)
    }

    @ViewBuilder
    private func content(_ style: WidgetStyle, ownStyle: WidgetStyle, appearance: WidgetAppearance) -> some View {
        switch block.content {
        case let .row(children):
            HStack(spacing: appearance.spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    AnyView(PopupBlockView(block: child, inheritedStyle: style, fields: fields,
                                          lists: lists, samples: samples, menu: menu, values: values,
                                          targets: targets, styles: styles, series: series, fillsWidth: fillsWidth, runAction: runAction))
                }
            }
        case let .column(children):
            VStack(alignment: .leading, spacing: appearance.spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    AnyView(PopupBlockView(block: child, inheritedStyle: style, fields: fields,
                                          lists: lists, samples: samples, menu: menu, values: values,
                                          targets: targets, styles: styles, series: series, fillsWidth: fillsWidth, runAction: runAction))
                }
            }
        case let .text(text):
            if let speed = block.scrollSpeed {
                ScrollingText(text: text, font: appearance.font, fontSize: style.fontSize ?? 12, speed: speed)
            } else {
                Text(text)
            }
        case let .field(name):
            if let speed = block.scrollSpeed {
                ScrollingText(text: fields[name] ?? "", font: appearance.font, fontSize: style.fontSize ?? 12, speed: speed)
            } else {
                Text(fields[name] ?? "—").lineLimit(1).monospacedDigit()
            }
        case let .graph(height, source, lineWidth):
            Sparkline(samples: source.flatMap { series[$0] } ?? samples)
                .stroke(appearance.accent, lineWidth: lineWidth)
                .frame(height: height)
                .accessibilityLabel("History graph")
        case let .list(source, row):
            VStack(spacing: appearance.spacing) {
                ForEach(Array((lists[source] ?? []).enumerated()), id: \.offset) { _, fields in
                    AnyView(PopupBlockView(block: row, inheritedStyle: style, fields: fields,
                                          lists: lists, samples: samples, menu: menu, values: values,
                                          targets: targets, styles: styles, series: series, fillsWidth: fillsWidth, runAction: runAction))
                }
            }
        case let .button(title, command):
            Button { runAction(command) } label: {
                Text(title).frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .menu:
            VStack(spacing: appearance.spacing) {
                ForEach(Array(menu.enumerated()), id: \.offset) { _, item in
                    PopupMenuRow(item: item, appearance: appearance, runAction: runAction)
                }
            }
        case .divider:
            Rectangle().fill(appearance.foreground.opacity(0.12)).frame(height: 1)
        case let .symbol(name, source):
            Image(systemName: source.flatMap { fields[$0] } ?? name)
                .font(.system(size: appearance.iconSize))
        case let .image(path, source, fit):
            WidgetImage(path: source.flatMap { fields[$0] } ?? path, fit: fit)
                .frame(width: ownStyle.width ?? 52, height: ownStyle.height ?? 52)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
        case let .progress(source, height):
            ProgressRule(value: values[source] ?? Double(fields[source] ?? "") ?? 0, target: targets[source],
                         animation: block.animation ?? WidgetAnimation(), color: appearance.accent,
                         track: style.background?.color ?? .clear, cornerRadius: appearance.cornerRadius)
                .frame(height: height)
        }
    }
}

struct ProgressRule: View {
    let value: Double
    let target: Double?
    let animation: WidgetAnimation
    let color: Color
    let track: Color
    let cornerRadius: Double
    @State private var fraction = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius).fill(track)
                RoundedRectangle(cornerRadius: cornerRadius).fill(color)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .task(id: ProgressUpdate(value: value, target: target, animation: animation, reduceMotion: reduceMotion)) {
            if let target, !reduceMotion {
                withAnimation(nil) { fraction = value }
                await Task.yield()
                if !Task.isCancelled { withAnimation(animation.value) { fraction = target } }
            } else {
                withAnimation(reduceMotion ? nil : animation.value) { fraction = value }
            }
        }
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

private struct ProgressUpdate: Equatable {
    let value: Double
    let target: Double?
    let animation: WidgetAnimation
    let reduceMotion: Bool
}

struct WidgetImage: View {
    let path: String
    let fit: ImageFit
    @State private var image: NSImage?
    @State private var error = ""

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fit == .fill ? .fill : .fit)
            } else {
                Color.clear
            }
        }
        .help(error)
        .task(id: path) {
            image = nil
            error = ""
            if path.isEmpty { return }
            do {
                let data: Data
                if path.hasPrefix("https://") || path.hasPrefix("http://") {
                    data = try await URLSession.shared.data(from: URL(string: path)!).0
                } else {
                    let url = path.hasPrefix("file://") ? URL(string: path)! : URL(filePath: NSString(string: path).expandingTildeInPath)
                    data = try await Task.detached { try Data(contentsOf: url) }.value
                }
                try Task.checkCancellation()
                image = NSImage(data: data)
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

struct PopupMenuRow: View {
    let item: WidgetMenuItem
    let appearance: WidgetAppearance
    let runAction: (String) -> Void
    @State private var hovered = false

    var body: some View {
        Group {
            if let command = item.onClick {
                Button { runAction(command) } label: { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
        .background(hovered && item.onClick != nil ? appearance.hoverBackground : .clear,
                    in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .onHover { hovered = $0 }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(item.onClick == nil ? appearance.font.weight(.semibold) : appearance.font)
            if let detail = item.detail {
                Text(detail).foregroundStyle(appearance.foreground.opacity(0.7))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .contentShape(Rectangle())
    }
}

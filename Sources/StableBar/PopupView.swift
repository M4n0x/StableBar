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
                               fields: fields, lists: lists, samples: samples, menu: menu) { command in
                    store.popup.close()
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
    let runAction: (String) -> Void
    @State private var hovered = false

    var body: some View {
        let style = block.style.inheriting(inheritedStyle)
        let appearance = WidgetAppearance(style, defaults: WidgetStyle())
        let alignment: Alignment = switch block.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        content(style, appearance: appearance)
            .font(appearance.font)
            .foregroundStyle(appearance.foreground)
            .padding(.horizontal, block.style.paddingHorizontal ?? 0)
            .padding(.vertical, block.style.paddingVertical ?? 0)
            .frame(width: block.style.width.map { CGFloat($0) }, alignment: alignment)
            .frame(maxWidth: block.style.width == nil ? .infinity : nil, alignment: alignment)
            .background((hovered ? block.style.hoverBackground ?? block.style.background : block.style.background)?.color ?? .clear,
                        in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: appearance.cornerRadius)
                    .strokeBorder(block.style.borderColor?.color ?? .clear, lineWidth: block.style.borderWidth ?? 0)
            }
            .onHover { hovered = $0 }
    }

    @ViewBuilder
    private func content(_ style: WidgetStyle, appearance: WidgetAppearance) -> some View {
        switch block.content {
        case let .row(children):
            HStack(spacing: appearance.spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    AnyView(PopupBlockView(block: child, inheritedStyle: style, fields: fields,
                                          lists: lists, samples: samples, menu: menu, runAction: runAction))
                }
            }
        case let .column(children):
            VStack(alignment: .leading, spacing: appearance.spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    AnyView(PopupBlockView(block: child, inheritedStyle: style, fields: fields,
                                          lists: lists, samples: samples, menu: menu, runAction: runAction))
                }
            }
        case let .text(text):
            Text(text)
        case let .field(name):
            Text(fields[name] ?? "—").lineLimit(1).monospacedDigit()
        case let .graph(height):
            Sparkline(samples: samples)
                .stroke(appearance.accent, lineWidth: 1.5)
                .frame(height: height)
                .accessibilityLabel("History graph")
        case let .list(source, row):
            VStack(spacing: appearance.spacing) {
                ForEach(Array((lists[source] ?? []).enumerated()), id: \.offset) { _, fields in
                    AnyView(PopupBlockView(block: row, inheritedStyle: style, fields: fields,
                                          lists: lists, samples: samples, menu: menu, runAction: runAction))
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

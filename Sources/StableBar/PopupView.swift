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
        let error = script?.error ?? store.actionErrors[widget.id]
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.spacing) {
                PopupBlockView(block: popup.layout, inheritedStyle: style, fields: fields,
                               context: BlockContext(lists: lists, samples: samples, menu: menu,
                                                     values: script?.output.values ?? [:], targets: script?.output.targets ?? [:],
                                                     styles: script?.output.styles ?? [:], series: script?.output.series ?? [:], open: { target in
                    if popup.dismissOnAction { store.popup.close() }
                    target.open()
                }) { command, environment in
                    if environment.isEmpty ? popup.dismissOnAction : popup.dismissOnControl { store.popup.close() }
                    store.runAction(command, widget: widget,
                                    event: ScriptEvent(sender: environment.isEmpty ? "mouse.clicked" : "control.changed", environment: environment))
                })
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

/// What every block of one layout shares: the widget's data, the states it applies and the action
/// its controls run.
struct BlockContext {
    var lists: [String: [[String: String]]] = [:]
    var samples: [Double] = []
    var menu: [WidgetMenuItem] = []
    var values: [String: Double] = [:]
    var targets: [String: Double] = [:]
    var styles: [String: WidgetStyle] = [:]
    var series: [String: [Double]] = [:]
    /// Popup layouts fill their width; bar layouts take their content's width.
    var fillsWidth = true
    /// Opens an `open` or `openField` block's target; a popup's also closes the popup when its actions dismiss it.
    let open: (OpenTarget) -> Void
    /// The widget's states, such as `open`; each block adds its own hover.
    var states = StyleStates()
    let runAction: (String, [String: String]) -> Void
}

struct PopupBlockView: View {
    let block: PopupBlock
    let inheritedStyle: WidgetStyle
    let fields: [String: String]
    let context: BlockContext
    @State private var hovered = false
    @State private var query = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        if let field = block.hideWhenEmpty, fields[field, default: ""].isEmpty {
            EmptyView()
        } else {
            styledContent
        }
    }

    private var handlesInteraction: Bool {
        switch block.content {
        case .button, .slider, .toggle, .segmented, .search: true
        default: false
        }
    }

    private var styledContent: some View {
        let resting = block.resolvedStyle(inherited: inheritedStyle, styles: context.styles, fields: fields, states: context.states)
        var hovering = context.states
        hovering.hover = true
        let current = hovered ? block.resolvedStyle(inherited: inheritedStyle, styles: context.styles, fields: fields, states: hovering) : resting
        let appearance = WidgetAppearance(resting.text, defaults: WidgetStyle())
        let box = current.box
        let alignment: Alignment = switch block.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        return Group {
            if handlesInteraction {
                content(resting, appearance: appearance)
            } else if let command = block.onClickField.flatMap({ fields[$0] }) ?? block.onClick {
                Button { context.runAction(command, [:]) } label: { content(resting, appearance: appearance) }
                    .buttonStyle(.plain)
            } else if let value = block.openField.flatMap({ fields[$0] }) ?? block.open {
                Button { if let target = OpenTarget(value) { context.open(target) } } label: { content(resting, appearance: appearance) }
                    .buttonStyle(.plain)
            } else {
                content(resting, appearance: appearance)
            }
        }
            .font(appearance.font)
            .foregroundStyle(current.text.foreground?.color ?? appearance.foreground)
            .tint(appearance.accent)
            .padding(.leading, box.paddingLeading ?? box.paddingHorizontal ?? 0)
            .padding(.trailing, box.paddingTrailing ?? box.paddingHorizontal ?? 0)
            .padding(.top, box.paddingTop ?? box.paddingVertical ?? 0)
            .padding(.bottom, box.paddingBottom ?? box.paddingVertical ?? 0)
            .frame(width: box.width.map { CGFloat($0) }, height: box.height.map { CGFloat($0) }, alignment: alignment)
            .frame(maxWidth: context.fillsWidth && box.width == nil ? .infinity : nil, alignment: alignment)
            .background(box.background?.color ?? .clear, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: appearance.cornerRadius)
                    .strokeBorder(box.borderColor?.color ?? .clear, lineWidth: box.borderWidth ?? 0)
            }
            .offset(x: box.offsetX ?? 0, y: box.offsetY ?? 0)
            .opacity(box.opacity ?? 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : block.animation?.value, value: box)
            .animation(reduceMotion ? nil : block.animation?.value, value: hovered)
    }

    /// A child block, built as a concrete view so SwiftUI diffs it without type erasure.
    private func child(_ block: PopupBlock, of style: BlockStyle, fields: [String: String]) -> PopupBlockView {
        PopupBlockView(block: block, inheritedStyle: style.inherited, fields: fields, context: context)
    }

    @ViewBuilder
    private func content(_ style: BlockStyle, appearance: WidgetAppearance) -> some View {
        switch block.content {
        case let .row(children):
            HStack(spacing: appearance.spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, item in child(item, of: style, fields: fields) }
            }
        case let .column(children):
            VStack(alignment: .leading, spacing: appearance.spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, item in child(item, of: style, fields: fields) }
            }
        case let .text(text):
            if let speed = block.scrollSpeed {
                ScrollingText(text: text, font: appearance.font, fontSize: style.text.fontSize ?? 12, speed: speed)
            } else {
                Text(text)
            }
        case let .field(name):
            if let speed = block.scrollSpeed {
                ScrollingText(text: fields[name] ?? "", font: appearance.font, fontSize: style.text.fontSize ?? 12, speed: speed)
            } else {
                Text(fields[name] ?? "—").lineLimit(1).monospacedDigit()
            }
        case let .graph(height, source, lineWidth):
            Sparkline(samples: source.flatMap { context.series[$0] } ?? context.samples)
                .stroke(appearance.accent, lineWidth: lineWidth)
                .frame(height: height)
                .accessibilityLabel("History graph")
        case let .list(source, row):
            VStack(spacing: appearance.spacing) {
                ForEach(Array((context.lists[source] ?? []).enumerated()), id: \.offset) { _, fields in
                    child(row, of: style, fields: fields)
                }
            }
        case let .button(title, command):
            Button { context.runAction(command, [:]) } label: {
                Text(title).frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case let .slider(title, source, minimum, maximum, step, command):
            PopupSlider(title: title, value: context.values[source] ?? Double(fields[source] ?? "") ?? minimum,
                        minimum: minimum, maximum: maximum, step: step) { context.runAction(command, ["VALUE": String($0)]) }
        case let .toggle(title, source, command):
            PopupToggle(title: title, value: fields[source] == "true" || fields[source] == "1" || context.values[source] == 1) {
                context.runAction(command, ["VALUE": $0 ? "true" : "false"])
            }
        case let .segmented(title, source, options, command):
            PopupSegmented(title: title, value: fields[source] ?? options[0].value, options: options) {
                context.runAction(command, ["VALUE": $0])
            }
        case let .search(title, source, searchFields, row):
            VStack(alignment: .leading, spacing: appearance.spacing) {
                TextField(title, text: $query).textFieldStyle(.roundedBorder).accessibilityLabel(title)
                ForEach(Array(searchPopupRows(context.lists[source] ?? [], query: query, fields: searchFields).enumerated()), id: \.offset) { _, fields in
                    child(row, of: style, fields: fields)
                }
            }
        case .menu:
            VStack(spacing: appearance.spacing) {
                ForEach(Array(context.menu.enumerated()), id: \.offset) { _, item in
                    PopupMenuRow(item: item, appearance: appearance) { context.runAction($0, [:]) }
                }
            }
        case .divider:
            Rectangle().fill(appearance.foreground.opacity(0.12)).frame(height: 1)
        case let .symbol(name, source):
            Image(systemName: source.flatMap { fields[$0] } ?? name)
                .font(.system(size: appearance.iconSize))
        case let .image(path, source, fit):
            WidgetImage(path: source.flatMap { fields[$0] } ?? path, fit: fit)
                .frame(width: style.box.width ?? 52, height: style.box.height ?? 52)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
        case let .progress(source, height):
            ProgressRule(value: context.values[source] ?? Double(fields[source] ?? "") ?? 0, target: context.targets[source],
                         animation: block.animation ?? WidgetAnimation(), color: appearance.accent,
                         track: style.text.background?.color ?? .clear, cornerRadius: appearance.cornerRadius)
                .frame(height: height)
        }
    }
}

private struct PopupSlider: View {
    let title: String
    let value: Double
    let minimum: Double
    let maximum: Double
    let step: Double
    let onChange: (Double) -> Void
    @State private var localValue: Double?
    @State private var editing = false

    var body: some View {
        Slider(value: Binding(get: { localValue ?? min(max(value, minimum), maximum) }, set: { localValue = $0 }),
               in: minimum...maximum, step: step) {
            Text(title)
        } onEditingChanged: { editing in
            self.editing = editing
            if !editing, let localValue { onChange(localValue) }
        }
        .accessibilityLabel(title)
        .onChange(of: value) { if !editing { localValue = nil } }
    }
}

private struct PopupToggle: View {
    let title: String
    let value: Bool
    let onChange: (Bool) -> Void
    @State private var localValue: Bool?

    var body: some View {
        Toggle(title, isOn: Binding(get: { localValue ?? value }, set: {
            localValue = $0
            onChange($0)
        }))
        .onChange(of: value) { localValue = nil }
    }
}

private struct PopupSegmented: View {
    let title: String
    let value: String
    let options: [PopupControlOption]
    let onChange: (String) -> Void
    @State private var localValue: String?

    var body: some View {
        Picker(title, selection: Binding(get: { localValue ?? value }, set: {
            localValue = $0
            onChange($0)
        })) {
            ForEach(options, id: \.value) { option in Text(option.title).tag(option.value) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(title)
        .onChange(of: value) { localValue = nil }
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
    @Environment(\.measuringBarWidths) private var measuring

    var body: some View {
        let still = reduceMotion || measuring
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius).fill(track)
                RoundedRectangle(cornerRadius: cornerRadius).fill(color)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .task(id: ProgressUpdate(value: value, target: target, animation: animation, reduceMotion: still)) {
            if let target, !still {
                withAnimation(nil) { fraction = progressFraction(value) }
                await Task.yield()
                if !Task.isCancelled { withAnimation(animation.value) { fraction = progressFraction(target) } }
            } else {
                withAnimation(still ? nil : animation.value) { fraction = progressFraction(value) }
            }
        }
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progressFraction(value) * 100)) percent")
    }
}

func progressFraction(_ value: Double) -> Double {
    value.isFinite ? min(max(value, 0), 1) : 0
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
                let url: URL
                if path.hasPrefix("https://") || path.hasPrefix("http://") || path.hasPrefix("file://") {
                    guard let source = URL(string: path) else { throw URLError(.badURL) }
                    url = source
                } else {
                    url = URL(filePath: NSString(string: path).expandingTildeInPath)
                }
                let data: Data
                if url.isFileURL {
                    data = try await Task.detached { try Data(contentsOf: url) }.value
                } else {
                    data = try await URLSession.shared.data(from: url).0
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

import Foundation

/// The states active for one drawn element. Their styles apply over the base style in the order
/// of `names`, later ones winning: the data state, the workspace state, `hover`, then `open`.
struct StyleStates: Equatable, Sendable {
    var data: String?
    var workspace: WorkspaceState?
    var hover = false
    var open = false

    /// The states StableBar sets itself, which output `state` and rules can't use.
    static let reservedNames: Set<String> = ["hover", "open", "focused", "visible", "empty"]

    var names: [String] { [data, workspace?.rawValue, hover ? "hover" : nil, open ? "open" : nil].compactMap { $0 } }
}

/// A workspace cell's state. A cell has at most one: focused, else visible, else empty.
enum WorkspaceState: String, CaseIterable, Sendable {
    case focused, visible, empty

    init?(_ workspace: Workspace) {
        if workspace.isFocused { self = .focused }
        else if workspace.isVisible { self = .visible }
        else if workspace.apps.isEmpty { self = .empty }
        else { return nil }
    }
}

extension WidgetStyle {
    /// This style with the style of each active state applied over it, in `states.names` order.
    /// A state's style merges with `inheriting`, so its own `states` refine the states after it, and
    /// a state that sets no background keeps the background.
    func resolved(for states: StyleStates) -> WidgetStyle {
        var style = self
        for name in states.names {
            style = (style.states?[name] ?? WidgetStyle()).inheriting(style)
        }
        return style
    }
}

/// The style an element draws: `layers` from lowest to highest precedence, such as the defaults,
/// the configured style and script overrides, merged with `inheriting`, then the active `states`.
func resolveStyle(_ layers: [WidgetStyle], states: StyleStates = StyleStates()) -> WidgetStyle {
    layers.reduce(WidgetStyle()) { $1.inheriting($0) }.resolved(for: states)
}

/// A bar widget's style layers, lowest precedence first: the defaults, its configured style, the
/// `widgetStyles` each widget's output sets for it in configuration order, then its own output's
/// `style` and `color`.
func widgetStyleLayers(_ widget: WidgetConfiguration, defaults: WidgetStyle, widgets: [WidgetConfiguration],
                       output: (String) -> ScriptOutput?) -> [WidgetStyle] {
    let own = output(widget.id)
    var layers = [defaults, widget.style]
    layers += widgets.compactMap { output($0.id)?.widgetStyles?[widget.id] }
    layers += [own?.style ?? WidgetStyle(), WidgetStyle(foreground: own?.color)]
    return layers
}

/// The bar's style layers: `bar.style`, then each widget's output `barStyle` in configuration order.
func barStyleLayers(_ style: WidgetStyle, widgets: [WidgetConfiguration], output: (String) -> ScriptOutput?) -> [WidgetStyle] {
    [style] + widgets.compactMap { output($0.id)?.barStyle }
}

/// A bar widget's style for each combination of its interaction states, resolved once so drawing
/// only picks one.
struct ResolvedWidgetStyle: Equatable, Sendable {
    /// The merged layers, with their `states`, that the widget's layout and overlay blocks inherit.
    let base: WidgetStyle
    /// The data state, from the widget's output or its rules.
    let state: String?
    /// `base` resolved at rest, hovered, open, then open and hovered.
    private let variants: [WidgetStyle]

    init(base: WidgetStyle, state: String? = nil) {
        self.base = base
        self.state = state
        variants = [(false, false), (true, false), (false, true), (true, true)].map {
            base.resolved(for: StyleStates(data: state, hover: $0.0, open: $0.1))
        }
    }

    func style(hovered: Bool, open: Bool = false) -> WidgetStyle { variants[(hovered ? 1 : 0) + (open ? 2 : 0)] }

    /// The states the widget's layout and overlay blocks share; each block adds its own hover.
    func blockStates(open: Bool) -> StyleStates { StyleStates(data: state, open: open) }
}

/// A workspace cell's styles in one workspace state, resolved when the configuration loads.
/// Hover changes the label and app glyphs; the indicators follow the workspace state only.
struct WorkspaceCellStyle: Equatable, Sendable {
    /// The label at rest, and the background indicator's fill, border and corners.
    let resting: WidgetStyle
    let hovered: WidgetStyle
    let underline: WidgetStyle
    let app: WidgetStyle
    let hoveredApp: WidgetStyle

    init(state: WorkspaceState? = nil, cell: WidgetStyle = WidgetStyle(), underline: WidgetStyle = WidgetStyle(),
         app: WidgetStyle = WidgetStyle()) {
        let rest = StyleStates(workspace: state)
        let hover = StyleStates(workspace: state, hover: true)
        resting = cell.resolved(for: rest)
        hovered = cell.resolved(for: hover)
        self.underline = underline.resolved(for: rest)
        self.app = app.resolved(for: rest)
        hoveredApp = app.resolved(for: hover)
    }

    func label(hovered isHovered: Bool) -> WidgetStyle { isHovered ? hovered : resting }
    func glyph(hovered isHovered: Bool) -> WidgetStyle { isHovered ? hoveredApp : app }
}

/// A layout block's styles for one draw.
struct BlockStyle: Equatable, Sendable {
    /// The block's style over the inherited one, without states: what its child blocks inherit.
    let inherited: WidgetStyle
    /// Fonts, colors, accent and spacing, inherited and own, with the active states.
    let text: WidgetStyle
    /// Background, border, padding, size, offset and opacity: the block's own, with the active states.
    let box: WidgetStyle
}

extension PopupBlock {
    /// Resolves this block's styles: its `style`, under the named output style that `styleField`
    /// (read from `fields`) or `styleSource` selects, over `inherited`.
    func resolvedStyle(inherited: WidgetStyle, styles: [String: WidgetStyle], fields: [String: String],
                       states: StyleStates) -> BlockStyle {
        let name = styleField.flatMap { fields[$0] } ?? styleSource
        let own = resolveStyle([style, name.flatMap { styles[$0] } ?? WidgetStyle()])
        let merged = resolveStyle([inherited, own])
        return BlockStyle(inherited: merged, text: merged.resolved(for: states), box: own.resolved(for: states))
    }
}

/// A widget's data state: its output's `state` when that is a non-empty string other than a reserved
/// name, otherwise the state of the first rule that matches the output.
func dataState(_ output: ScriptOutput?, rules: [StyleRule] = []) -> String? {
    guard let output else { return nil }
    if case let .string(name)? = output.state, !name.isEmpty, !StyleStates.reservedNames.contains(name) { return name }
    return rules.first { $0.when.matches(output) }?.state
}

/// Sets a widget's data state while its output matches `when`.
struct StyleRule: Decodable, Equatable, Sendable {
    let when: RuleCondition
    let state: String

    enum CodingKeys: String, CodingKey, CaseIterable { case when, state }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        when = try values.decode(RuleCondition.self, forKey: .when)
        state = try values.decode(String.self, forKey: .state)
        guard !state.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .state, in: values,
                                                   debugDescription: "A rule's state must not be empty. Use a data state such as warning.")
        }
        guard !StyleStates.reservedNames.contains(state) else {
            throw DecodingError.dataCorruptedError(forKey: .state, in: values,
                                                   debugDescription: "\(state) is set by StableBar. Use a data state such as warning.")
        }
    }
}

/// Compares one entry of a widget's output: a number in `values` at or below `below` and at or
/// above `above`, or a string in `fields` equal to `equals`. A missing entry never matches.
struct RuleCondition: Decodable, Equatable, Sendable {
    let value: String?
    let field: String?
    let below: Double?
    let above: Double?
    let equals: String?

    enum CodingKeys: String, CodingKey, CaseIterable { case value, field, below, above, equals }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        value = try values.decodeIfPresent(String.self, forKey: .value)
        field = try values.decodeIfPresent(String.self, forKey: .field)
        below = try values.decodeIfPresent(Double.self, forKey: .below)
        above = try values.decodeIfPresent(Double.self, forKey: .above)
        equals = try values.decodeIfPresent(String.self, forKey: .equals)
        let comparesValue = value != nil && field == nil && equals == nil && (below != nil || above != nil)
        let comparesField = field != nil && value == nil && below == nil && above == nil && equals != nil
        guard comparesValue || comparesField else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Compare a value with below or above, or a field with equals."))
        }
    }

    func matches(_ output: ScriptOutput) -> Bool {
        if let field { return output.fields?[field] == equals }
        guard let value, let number = output.values?[value] else { return false }
        return (below.map { number <= $0 } ?? true) && (above.map { number >= $0 } ?? true)
    }
}

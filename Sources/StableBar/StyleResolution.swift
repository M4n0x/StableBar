import Foundation

/// The states active for one drawn element. Their styles apply over the base style in the order
/// of `names`, later ones winning.
struct StyleStates: Equatable, Sendable {
    var hover = false

    var names: [String] { hover ? ["hover"] : [] }
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
    private let rest: WidgetStyle
    private let hovered: WidgetStyle

    init(base: WidgetStyle) {
        self.base = base
        rest = base.resolved(for: StyleStates())
        hovered = base.resolved(for: StyleStates(hover: true))
    }

    func style(hovered isHovered: Bool) -> WidgetStyle { isHovered ? hovered : rest }
}

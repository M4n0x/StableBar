import AppKit
import SwiftUI

struct HexColor: Decodable, Equatable, Sendable {
    let rgba: UInt32

    init(_ rgba: UInt32) {
        self.rgba = rgba
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let hex = string.dropFirst()
        guard string.hasPrefix("#"), [6, 8].contains(hex.count),
              let value = UInt32(hex, radix: 16) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Use #RRGGBB or #RRGGBBAA for colors.")
        }
        rgba = hex.count == 6 ? (value << 8) | 0xff : value
    }

    var color: Color {
        Color(.sRGB, red: Double(rgba >> 24) / 255,
              green: Double((rgba >> 16) & 0xff) / 255,
              blue: Double((rgba >> 8) & 0xff) / 255,
              opacity: Double(rgba & 0xff) / 255)
    }
}

struct WidgetStyle: Decodable, Equatable, Sendable {
    var foreground: HexColor?
    var background: HexColor?
    var hoverBackground: HexColor?
    var borderColor: HexColor?
    var accent: HexColor?
    var accentText: HexColor?
    var borderWidth: Double?
    var cornerRadius: Double?
    var fontName: String?
    var fontSize: Double?
    var fontWeight: String?
    var iconSize: Double?
    var paddingHorizontal: Double?
    var paddingVertical: Double?
    var spacing: Double?
    var width: Double?
    var shadowRadius: Double?
    var shadowColor: HexColor?
    var height: Double?
    var paddingLeading: Double?
    var paddingTrailing: Double?
    var paddingTop: Double?
    var paddingBottom: Double?
    var offsetX: Double?
    var offsetY: Double?
    var opacity: Double?
    var hoverForeground: HexColor?

    func inheriting(_ defaults: WidgetStyle) -> WidgetStyle {
        WidgetStyle(
            foreground: foreground ?? defaults.foreground,
            background: background ?? defaults.background,
            hoverBackground: hoverBackground ?? defaults.hoverBackground,
            borderColor: borderColor ?? defaults.borderColor,
            accent: accent ?? defaults.accent,
            accentText: accentText ?? defaults.accentText,
            borderWidth: borderWidth ?? defaults.borderWidth,
            cornerRadius: cornerRadius ?? defaults.cornerRadius,
            fontName: fontName ?? defaults.fontName,
            fontSize: fontSize ?? defaults.fontSize,
            fontWeight: fontWeight ?? defaults.fontWeight,
            iconSize: iconSize ?? defaults.iconSize,
            paddingHorizontal: paddingHorizontal ?? defaults.paddingHorizontal,
            paddingVertical: paddingVertical ?? defaults.paddingVertical,
            spacing: spacing ?? defaults.spacing,
            width: width ?? defaults.width,
            shadowRadius: shadowRadius ?? defaults.shadowRadius,
            shadowColor: shadowColor ?? defaults.shadowColor,
            height: height ?? defaults.height,
            paddingLeading: paddingLeading ?? defaults.paddingLeading,
            paddingTrailing: paddingTrailing ?? defaults.paddingTrailing,
            paddingTop: paddingTop ?? defaults.paddingTop,
            paddingBottom: paddingBottom ?? defaults.paddingBottom,
            offsetX: offsetX ?? defaults.offsetX,
            offsetY: offsetY ?? defaults.offsetY,
            opacity: opacity ?? defaults.opacity,
            hoverForeground: hoverForeground ?? defaults.hoverForeground
        )
    }
}

struct WidgetAppearance {
    let foreground: Color
    let hoverForeground: Color
    let background: Color
    let hoverBackground: Color
    let borderColor: Color
    let accent: Color
    let accentText: Color
    let borderWidth: Double
    let cornerRadius: Double
    let font: Font
    let iconSize: Double
    let paddingHorizontal: Double
    let paddingVertical: Double
    let spacing: Double
    let width: CGFloat?
    let shadowRadius: Double
    let shadowColor: Color

    init(_ style: WidgetStyle, defaults: WidgetStyle) {
        foreground = (style.foreground ?? defaults.foreground ?? HexColor(0x1d1d1fff)).color
        hoverForeground = (style.hoverForeground ?? defaults.hoverForeground)?.color ?? foreground
        background = (style.background ?? defaults.background ?? HexColor(0xf8f8faed)).color
        hoverBackground = (style.hoverBackground ?? defaults.hoverBackground ?? HexColor(0xffffffff)).color
        borderColor = (style.borderColor ?? defaults.borderColor ?? HexColor(0xffffffb3)).color
        accent = (style.accent ?? defaults.accent ?? HexColor(0xf7821bff)).color
        accentText = (style.accentText ?? defaults.accentText ?? HexColor(0xffffffff)).color
        borderWidth = style.borderWidth ?? defaults.borderWidth ?? 1
        cornerRadius = style.cornerRadius ?? defaults.cornerRadius ?? 14
        iconSize = style.iconSize ?? defaults.iconSize ?? 13
        paddingHorizontal = style.paddingHorizontal ?? defaults.paddingHorizontal ?? 10
        paddingVertical = style.paddingVertical ?? defaults.paddingVertical ?? 6
        spacing = style.spacing ?? defaults.spacing ?? 6
        width = (style.width ?? defaults.width).map { CGFloat($0) }
        shadowRadius = style.shadowRadius ?? defaults.shadowRadius ?? 2
        shadowColor = (style.shadowColor ?? defaults.shadowColor ?? HexColor(0x00000014)).color
        let size = style.fontSize ?? defaults.fontSize ?? 12
        let name = style.fontName ?? defaults.fontName ?? "system"
        let weight: Font.Weight
        switch style.fontWeight ?? defaults.fontWeight ?? "medium" {
        case "ultralight": weight = .ultraLight
        case "thin": weight = .thin
        case "light": weight = .light
        case "regular": weight = .regular
        case "semibold": weight = .semibold
        case "bold": weight = .bold
        default: weight = .medium
        }
        font = name == "system" ? .system(size: size, weight: weight) : .custom(name, size: size).weight(weight)
    }
}

enum WidgetPosition: String, Decodable, Sendable {
    case left, notchLeft, center, notchRight, right
}

enum WidgetContent: Equatable, Sendable {
    case workspaces
    case activeApp
    case clock(format: String)
    case text(String)
    case script(command: String, interval: Double?)
}

struct WidgetConfiguration: Decodable, Identifiable, Sendable {
    let id: String
    let position: WidgetPosition
    let content: WidgetContent
    let icon: String?
    let onClick: String?
    let menu: [WidgetMenuItem]?
    let popup: PopupConfiguration?
    let popupName: String?
    let style: WidgetStyle
    let display: DisplaySelection
    let layout: PopupBlock?
    let overlay: PopupBlock?
    let animation: WidgetAnimation?
    let workspace: WorkspaceConfiguration?
    let events: [String]
    let environment: [String: String]
    let timeout: Double
    let actions: WidgetActions?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, position, type, icon, onClick, menu, popup, popupName, style, format, text, command, interval
        case display, layout, overlay, animation, workspace, events, environment, timeout, actions, enabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        position = try values.decode(WidgetPosition.self, forKey: .position)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        onClick = try values.decodeIfPresent(String.self, forKey: .onClick)
        menu = try values.decodeIfPresent([WidgetMenuItem].self, forKey: .menu)
        popup = try values.decodeIfPresent(PopupConfiguration.self, forKey: .popup)
        popupName = try values.decodeIfPresent(String.self, forKey: .popupName)
        style = try values.decodeIfPresent(WidgetStyle.self, forKey: .style) ?? WidgetStyle()
        display = try values.decodeIfPresent(DisplaySelection.self, forKey: .display) ?? .all
        layout = try values.decodeIfPresent(PopupBlock.self, forKey: .layout)
        overlay = try values.decodeIfPresent(PopupBlock.self, forKey: .overlay)
        animation = try values.decodeIfPresent(WidgetAnimation.self, forKey: .animation)
        workspace = try values.decodeIfPresent(WorkspaceConfiguration.self, forKey: .workspace)
        events = try values.decodeIfPresent([String].self, forKey: .events) ?? []
        environment = try values.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        timeout = try values.decodeIfPresent(Double.self, forKey: .timeout) ?? 10
        guard timeout > 0, timeout.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .timeout, in: values, debugDescription: "A command timeout must be greater than zero and finite.")
        }
        actions = try values.decodeIfPresent(WidgetActions.self, forKey: .actions)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        switch try values.decode(String.self, forKey: .type) {
        case "aerospace": content = .workspaces
        case "activeApp": content = .activeApp
        case "clock": content = .clock(format: try values.decodeIfPresent(String.self, forKey: .format) ?? "EEE d MMM  HH:mm")
        case "text": content = .text(try values.decode(String.self, forKey: .text))
        case "script":
            let interval = try values.contains(.interval) ? values.decodeIfPresent(Double.self, forKey: .interval) : 30
            if let interval, interval <= 0 {
                throw DecodingError.dataCorruptedError(forKey: .interval, in: values, debugDescription: "A script interval must be greater than zero.")
            }
            content = .script(command: try values.decode(String.self, forKey: .command), interval: interval)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: values, debugDescription: "Unknown widget type.")
        }
    }
}

struct BarSettings: Decodable, Sendable {
    var height = 40.0
    var offset = 0.0
    var inset = 12.0
    var spacing = 8.0
    var background = HexColor(0x00000000)
    var animationDuration = 0.22
    var notchWidth: Double?
    var notchSpacing = 16.0
    var style = WidgetStyle()

    enum CodingKeys: String, CodingKey {
        case height, offset, inset, spacing, background, animationDuration, notchWidth, notchSpacing, style
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        height = try values.decodeIfPresent(Double.self, forKey: .height) ?? height
        offset = try values.decodeIfPresent(Double.self, forKey: .offset) ?? offset
        inset = try values.decodeIfPresent(Double.self, forKey: .inset) ?? inset
        spacing = try values.decodeIfPresent(Double.self, forKey: .spacing) ?? spacing
        background = try values.decodeIfPresent(HexColor.self, forKey: .background) ?? background
        animationDuration = try values.decodeIfPresent(Double.self, forKey: .animationDuration) ?? animationDuration
        notchWidth = try values.decodeIfPresent(Double.self, forKey: .notchWidth)
        notchSpacing = try values.decodeIfPresent(Double.self, forKey: .notchSpacing) ?? notchSpacing
        style = try values.decodeIfPresent(WidgetStyle.self, forKey: .style) ?? style
    }
}

struct Configuration: Decodable, Sendable {
    let bar: BarSettings
    let defaults: WidgetStyle
    let widgets: [WidgetConfiguration]
    let popups: [String: PopupConfiguration]
    let environment: [String: String]

    enum CodingKeys: String, CodingKey { case bar, defaults, widgets, popups, templates, widgetOverrides, environment }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bar = try values.decodeIfPresent(BarSettings.self, forKey: .bar) ?? BarSettings()
        defaults = try values.decodeIfPresent(WidgetStyle.self, forKey: .defaults) ?? WidgetStyle()
        let templates = try values.decodeIfPresent([String: [String: ConfigurationValue]].self, forKey: .templates) ?? [:]
        let overrides = try values.decodeIfPresent([String: [String: ConfigurationValue]].self, forKey: .widgetOverrides) ?? [:]
        for (id, properties) in overrides where properties["id"] != nil {
            throw ConfigurationCompositionError.widgetOverrideID(id)
        }
        let definitions = try values.decode([[String: ConfigurationValue]].self, forKey: .widgets)
        widgets = try definitions.map { definition in
            var expanded = try expandWidgetTemplate(definition, templates: templates)
            if let id = expanded["id"], let properties = overrides[try id.decoded(String.self)] {
                expanded.merge(properties) { $1.overriding($0) }
            }
            return try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(expanded))
        }
        environment = try values.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        popups = try values.decodeIfPresent([String: PopupConfiguration].self, forKey: .popups) ?? [:]
        var ids = Set<String>()
        for widget in widgets {
            if let name = widget.popupName, popups[name] == nil {
                throw DecodingError.dataCorruptedError(forKey: .popups, in: values, debugDescription: "Unknown popup: \(name).")
            }
            guard ids.insert(widget.id).inserted else {
                throw DecodingError.dataCorruptedError(forKey: .widgets, in: values, debugDescription: "Duplicate widget id: \(widget.id). Each widget needs a stable, unique id.")
            }
        }
        for id in overrides.keys where !ids.contains(id) {
            throw ConfigurationCompositionError.unknownWidgetOverride(id)
        }
    }
}

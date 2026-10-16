import AppKit
import SwiftUI

let themeTokens: [(name: String, title: String)] = [
    ("surface", "Surface"), ("surfaceRaised", "Raised surface"), ("text", "Text"), ("textMuted", "Muted text"),
    ("accent", "Accent"), ("track", "Track"), ("hairline", "Hairline"), ("warning", "Warning"), ("critical", "Critical")
]

struct AppearanceView: View {
    let editor: ConfigurationEditor
    @State private var themes: [ThemeChoice] = []
    @State private var looks: [String: Configuration] = [:]
    @State private var fontFamilies = NSFontManager.shared.availableFontFamilies

    private var store: BarStore { editor.store }

    var body: some View {
        let theme = try? store.effectiveDocument["theme"]?.decoded(WidgetPackageSelection.self)
        let selected = theme?.enabled == true ? theme?.key : nil
        let tokens = document("tokens")
        let defaults = StyleFields(store: store, path: "defaults", values: document("defaults"),
                                   set: { editor.change(ConfigurationEdit(action: .defaults, properties: [$0: $1])) },
                                   unset: { unset(["defaults": .object([$0: .null])]) })
        let bar = StyleFields(store: store, path: "bar", values: document("bar"),
                              set: { editor.change(ConfigurationEdit(action: .bar, properties: [$0: $1])) },
                              unset: { unset(["bar": .object([$0: .null])]) })
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ThemeCard(title: "Built-in", look: looks[""], isSelected: selected == nil) {
                        editor.change(ConfigurationEdit(action: .theme))
                    }
                    ForEach(themes, id: \.key) { choice in
                        ThemeCard(title: choice.title, look: looks[choice.key], isSelected: selected == choice.key) {
                            editor.change(ConfigurationEdit(action: .theme, properties: choice.selection))
                        }
                    }
                }
                .padding(.vertical, 4)
                Picker("Appearance", selection: Binding(get: { store.configuration?.bar.appearance }, set: {
                    editor.change(ConfigurationEdit(action: .bar, properties: ["appearance": $0.map { .string($0.rawValue) } ?? .null]))
                })) {
                    Text("Automatic").tag(BarAppearance?.none)
                    Text("Light").tag(BarAppearance?.some(.light))
                    Text("Dark").tag(BarAppearance?.some(.dark))
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Theme")
            } footer: {
                Text("Automatic follows the system’s light or dark mode. Install other themes in Packages.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ForEach(themeTokens, id: \.name) { token in
                    if let color = try? tokens[token.name]?.decoded(HexColor.self) {
                        let origin = store.origins["tokens.\(token.name)"]
                        OverrideRow(title: token.title, source: origin.map { "From \(store.sourceText($0))" },
                                    reset: origin.map(store.setsInMainFile) == true ? { unset(["tokens": .object([token.name: .null])]) } : nil) {
                            ColorWells(color: color) { editor.change(ConfigurationEdit(action: .tokens, properties: [token.name: $0])) }
                        }
                    }
                }
            } header: {
                Text("Theme colors")
            } footer: {
                Text("Changes are saved in your configuration’s tokens, so every widget, popup and package that uses a color follows.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("All widgets") {
                defaults.color("Text", "foreground")
                defaults.color("Background", "background")
                defaults.color("Hover background", "hoverBackground")
                defaults.color("Border", "borderColor")
                defaults.color("Accent", "accent")
                defaults.font(fontFamilies)
                defaults.weight()
                defaults.number("Font size", "fontSize", default: 12)
                defaults.number("Horizontal padding", "paddingHorizontal", default: 10)
                defaults.number("Corner radius", "cornerRadius", default: 14)
            }
            Section("Bar") {
                bar.number("Height", "height", default: 40)
                bar.number("Offset from top", "offset", default: 0)
                bar.number("Margin", "margin", default: 0)
                bar.number("Side inset", "inset", default: 12)
                bar.number("Spacing", "spacing", default: 8)
            }
            Section {
                let origin = store.origins["bar.keepWindowsClear"]
                OverrideRow(title: "Keep windows clear of StableBar", source: origin.map { "From \(store.sourceText($0))" },
                            reset: origin.map(store.setsInMainFile) == true ? { unset(["bar": .object(["keepWindowsClear": .null])]) } : nil) {
                    Toggle("Keep windows clear of StableBar", isOn: Binding(
                        get: { store.configuration?.bar.keepWindowsClear == true },
                        set: { enabled in
                            editor.change(ConfigurationEdit(action: .bar, properties: ["keepWindowsClear": .bool(enabled)]))
                            if enabled && !store.windowClearance.isTrusted { store.windowClearance.requestAccess() }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if store.configuration?.bar.keepWindowsClear == true {
                    LabeledContent("Accessibility", value: store.windowClearance.isTrusted ? "Access granted" : "Access required")
                    if !store.windowClearance.isTrusted {
                        Button("Allow Accessibility Access…") { store.windowClearance.requestAccess() }
                    }
                }
            } header: {
                Text("Windows")
            } footer: {
                Text("Moves ordinary windows below the bar and reduces their height when needed. Fullscreen windows are unchanged. Leave this off if AeroSpace or yabai already manages your window gaps.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadThemes)
    }

    private func document(_ key: String) -> [String: ConfigurationValue] {
        (try? store.effectiveDocument[key]?.decoded([String: ConfigurationValue].self)) ?? [:]
    }

    private func unset(_ properties: [String: ConfigurationValue]) {
        editor.change(ConfigurationEdit(action: .unset, properties: properties))
    }

    private func loadThemes() {
        themes = themeChoices(packages: store.configurationURL.deletingLastPathComponent().appending(path: "packages"))
        var loader = ConfigurationLoader()
        looks = [:]
        looks[""] = try? loader.load(store.configurationURL, data: Data("{}".utf8))
        for theme in themes {
            looks[theme.key] = try? loader.load(store.configurationURL, data: JSONEncoder().encode(["theme": ConfigurationValue.object(theme.selection)]))
        }
    }
}

private struct ThemeCard: View {
    let title: String
    let look: Configuration?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    preview.environment(\.colorScheme, .light)
                    preview.environment(\.colorScheme, .dark)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                }
                HStack(spacing: 4) {
                    Text(title)
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                .font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var preview: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .underPageBackgroundColor)
            if let look {
                let tile = WidgetAppearance(look.defaults, defaults: WidgetStyle())
                let bar = look.bar.style
                HStack(spacing: tile.spacing) {
                    Circle().fill(tile.accent).frame(width: 7, height: 7)
                    Text("9:41")
                }
                .font(tile.font)
                .foregroundStyle(tile.foreground)
                .padding(.horizontal, tile.paddingHorizontal)
                .padding(.vertical, tile.paddingVertical)
                .background(tile.background, in: RoundedRectangle(cornerRadius: tile.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: tile.cornerRadius).strokeBorder(tile.borderColor, lineWidth: tile.borderWidth)
                }
                .shadow(color: tile.shadowColor, radius: tile.shadowRadius, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background((bar.background ?? look.bar.background).color, in: RoundedRectangle(cornerRadius: bar.cornerRadius ?? 0))
                .overlay(alignment: .bottom) {
                    (bar.borderColor?.color ?? .clear).frame(height: bar.borderWidth ?? 0)
                }
                .padding(look.bar.margin)
                .frame(height: look.bar.height)
            }
        }
        .frame(height: 56)
    }
}

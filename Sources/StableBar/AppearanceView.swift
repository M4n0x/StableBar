import AppKit
import SwiftUI

let themeTokens: [(name: String, title: String)] = [
    ("surface", "Surface"), ("surfaceRaised", "Raised surface"), ("text", "Text"), ("textMuted", "Muted text"),
    ("accent", "Accent"), ("track", "Track"), ("hairline", "Hairline"), ("warning", "Warning"), ("critical", "Critical")
]

struct AppearanceView: View {
    let editor: ConfigurationEditor
    @State private var themes: [ThemeChoice] = []
    @State private var swatches: [String: [String: HexColor]] = [:]
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
                    ThemeCard(title: "Built-in", colors: swatches[""] ?? [:], isSelected: selected == nil) {
                        editor.change(ConfigurationEdit(action: .theme))
                    }
                    ForEach(themes, id: \.key) { choice in
                        ThemeCard(title: choice.title, colors: swatches[choice.key] ?? [:], isSelected: selected == choice.key) {
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
        let builtIn = bundledThemesDirectory.map { tokenColors(at: $0.appending(path: "built-in")) } ?? [:]
        swatches = [:]
        swatches[""] = builtIn
        for theme in themes { swatches[theme.key] = builtIn.merging(tokenColors(at: theme.directory)) { $1 } }
    }
}

private func tokenColors(at directory: URL) -> [String: HexColor] {
    var loader = ConfigurationLoader()
    guard let manifest = try? WidgetPackageStore(directory: directory).manifest(at: directory),
          let layer = try? loader.readPackage(at: directory, manifest: manifest, settings: [:]),
          case let .object(tokens) = layer.values["tokens"] else { return [:] }
    return tokens.compactMapValues { try? substituteConfigurationReferences($0, prefix: "@token.", values: tokens).decoded(HexColor.self) }
}

private struct ThemeCard: View {
    let title: String
    let colors: [String: HexColor]
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
        HStack(spacing: 5) {
            Circle().fill(colors["accent"]?.color ?? .clear).frame(width: 7, height: 7)
            Text("Mon 9:41").font(.system(size: 11, weight: .medium)).foregroundStyle(colors["text"]?.color ?? .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colors["surface"]?.color ?? .clear, in: Capsule())
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

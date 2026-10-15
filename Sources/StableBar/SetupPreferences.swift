import Foundation

struct SetupPreferences: Equatable {
    enum Appearance: String, CaseIterable {
        case current = "Keep current", light = "Light", dark = "Dark"
    }

    enum Placement: String, CaseIterable {
        case current = "Keep current", top = "Top edge", belowMenuBar = "Below menu bar"
    }

    enum Clock: String, CaseIterable {
        case current = "Keep current", twentyFourHour = "24-hour", twelveHour = "12-hour"
    }

    var appearance = Appearance.current
    var placement = Placement.current
    var clock = Clock.current

    func applying(to data: Data, menuBarHeight: Double, configurationURL: URL? = nil,
                  context: ConfigurationContext = ConfigurationContext()) throws -> Data {
        let configuration: Configuration
        if let configurationURL {
            var loader = ConfigurationLoader()
            configuration = try loader.load(configurationURL, data: data, context: context)
        } else {
            configuration = try JSONDecoder().decode(Configuration.self, from: data)
        }
        if self == SetupPreferences() { return data }
        var document = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var settings = configurationURL == nil ? document : document["customization"] as? [String: Any] ?? [:]
        if appearance != .current {
            var defaults = settings["defaults"] as? [String: Any] ?? [:]
            let dark = appearance == .dark
            defaults["foreground"] = dark ? "#f5f5f7" : "#1d1d1f"
            defaults["background"] = dark ? "#242629ee" : "#f8f8faed"
            defaults["hoverBackground"] = dark ? "#36383c" : "#ffffff"
            defaults["borderColor"] = dark ? "#ffffff1f" : "#ffffffb3"
            defaults["shadowColor"] = dark ? "#00000040" : "#00000014"
            settings["defaults"] = defaults
        }
        if placement != .current {
            var bar = settings["bar"] as? [String: Any] ?? [:]
            bar["offset"] = placement == .top ? 0 : menuBarHeight
            settings["bar"] = bar
        }
        if clock != .current {
            var overrides = settings["widgetOverrides"] as? [String: [String: Any]] ?? [:]
            for widget in configuration.widgets {
                if case .clock = widget.content {
                    overrides[widget.id, default: [:]]["format"] = clock == .twentyFourHour ? "EEE d MMM  HH:mm" : "EEE d MMM  h:mm a"
                }
            }
            settings["widgetOverrides"] = overrides
        }
        if configurationURL == nil { document = settings }
        else { document["customization"] = settings }
        let edited = try JSONDecoder().decode([String: ConfigurationValue].self, from: JSONSerialization.data(withJSONObject: document))
        return try configurationData(edited, editing: data)
    }
}

import Foundation

struct SetupPreferences: Equatable {
    enum Appearance: String, CaseIterable {
        case current = "Keep current", automatic = "Automatic", light = "Light", dark = "Dark"
    }

    enum Placement: String, CaseIterable {
        case current = "Keep current", top = "Top edge", belowMenuBar = "Below menu bar"
    }

    enum Clock: String, CaseIterable {
        case current = "Keep current", twentyFourHour = "24-hour", twelveHour = "12-hour"
    }

    enum Theme: Hashable {
        case current, builtIn, package(id: String, version: String?)
    }

    /// Built-in widgets that setup adds together. They read native providers, so they run no commands.
    enum WidgetSet: Hashable {
        case system, meetings, workspaces(WorkspaceSource)

        var title: String {
            switch self {
            case .system: "System"
            case .meetings: "Meetings"
            case .workspaces: "Workspaces"
            }
        }

        var symbol: String {
            switch self {
            case .system: "cpu"
            case .meetings: "calendar"
            case .workspaces: "rectangle.3.group"
            }
        }

        var detail: String {
            switch self {
            case .system: "CPU and memory, network traffic and battery charge."
            case .meetings: "Your next meeting, with today's agenda when you click it. Needs Calendars access."
            case let .workspaces(source): "Your \(source.title) workspaces and their apps. Click one to switch to it."
            }
        }

        var widgets: [[String: ConfigurationValue]] {
            let json = switch self {
            case .system: #"""
                [
                  {
                    "id": "system-monitor", "type": "system", "position": "right",
                    "popup": {
                      "style": { "width": 280 },
                      "layout": {
                        "type": "column",
                        "children": [
                          { "type": "text", "text": "System", "role": "heading" },
                          { "type": "graph", "height": 36 },
                          {
                            "type": "row",
                            "children": [
                              { "type": "text", "text": "CPU", "role": "key" },
                              { "type": "field", "field": "cpu", "alignment": "trailing", "role": "value" },
                              { "type": "text", "text": "%", "role": "value", "style": { "width": 14 } }
                            ]
                          },
                          { "type": "progress", "source": "cpu", "height": 3, "role": "meter" },
                          {
                            "type": "row",
                            "children": [
                              { "type": "text", "text": "Memory", "role": "key" },
                              { "type": "field", "field": "memory", "alignment": "trailing", "role": "value" },
                              { "type": "text", "text": "%", "role": "value", "style": { "width": 14 } }
                            ]
                          },
                          { "type": "progress", "source": "memory", "height": 3, "role": "meter" },
                          { "type": "divider", "role": "separator" },
                          { "type": "text", "text": "Activity Monitor", "open": "com.apple.ActivityMonitor", "role": "button" }
                        ]
                      }
                    }
                  },
                  { "id": "network", "type": "network", "position": "right" },
                  {
                    "id": "battery", "type": "battery", "position": "right",
                    "layout": { "type": "row", "children": [{ "type": "symbol", "source": "icon" }, { "type": "field", "field": "text" }] }
                  }
                ]
                """#
            case .meetings: #"""
                [
                  {
                    "id": "meeting", "type": "calendar", "position": "right",
                    "layout": {
                      "type": "row",
                      "children": [
                        { "type": "symbol", "source": "icon" },
                        { "type": "field", "field": "text" },
                        { "type": "field", "field": "start", "hideWhenEmpty": "start", "role": "secondary" }
                      ]
                    },
                    "popup": {
                      "style": { "width": 320 },
                      "layout": {
                        "type": "column",
                        "children": [
                          { "type": "text", "text": "Today", "role": "heading" },
                          {
                            "type": "list", "source": "today",
                            "row": {
                              "type": "row", "openField": "link",
                              "children": [
                                { "type": "field", "field": "start", "role": "key", "style": { "width": 56 } },
                                { "type": "field", "field": "title", "role": "primary" }
                              ]
                            }
                          },
                          { "type": "divider", "role": "separator" },
                          { "type": "text", "text": "Calendar", "open": "com.apple.iCal", "role": "button" }
                        ]
                      }
                    }
                  }
                ]
                """#
            case .workspaces: #"[{ "id": "workspaces", "type": "workspaces", "position": "left" }]"#
            }
            return try! JSONDecoder().decode([[String: ConfigurationValue]].self, from: Data(json.utf8))
        }

        /// What setup's preview shows for each widget, since its provider starts only once setup
        /// finishes.
        var preview: [String: ScriptOutput] {
            switch self {
            case .system: [
                "system-monitor": ScriptOutput(text: "12%", icon: "cpu", value: 0.12),
                "network": ScriptOutput(text: "↓24 ↑3 KiB/s", icon: "network"),
                "battery": ScriptOutput(text: "82%", icon: "battery.100percent")
            ]
            case .meetings: ["meeting": ScriptOutput(text: "Design review", icon: "calendar", fields: ["start": "10:30"])]
            case .workspaces: [:]
            }
        }
    }

    var appearance = Appearance.current
    var placement = Placement.current
    var clock = Clock.current
    var theme = Theme.current
    var widgetSets: [WidgetSet] = []

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
        var edits: [ConfigurationEdit] = []
        switch theme {
        case .current: break
        case .builtIn: edits.append(ConfigurationEdit(action: .theme))
        case let .package(id, version):
            var properties: [String: ConfigurationValue] = ["id": .string(id)]
            if let version { properties["version"] = .string(version) }
            edits.append(ConfigurationEdit(action: .theme, properties: properties))
        }
        if appearance != .current {
            let value: ConfigurationValue = switch appearance {
            case .light: .string("light")
            case .dark: .string("dark")
            default: .null
            }
            edits.append(ConfigurationEdit(action: .bar, properties: ["appearance": value]))
        }
        if placement != .current {
            edits.append(ConfigurationEdit(action: .bar, properties: ["offset": .number(placement == .top ? 0 : menuBarHeight)]))
        }
        if clock != .current {
            for widget in configuration.widgets {
                if case .clock = widget.content {
                    edits.append(ConfigurationEdit(action: .set, id: widget.id, properties: [
                        "format": .string(clock == .twentyFourHour ? "EEE d MMM  HH:mm" : "EEE d MMM  h:mm a")
                    ]))
                }
            }
        }
        for set in widgetSets {
            for widget in set.widgets where !configuration.widgets.contains(where: { widget["id"] == .string($0.id) }) {
                edits.append(ConfigurationEdit(action: .add, properties: widget))
            }
        }
        var document = try JSONDecoder().decode([String: ConfigurationValue].self, from: data)
        var ids = configuration.widgets.map(\.id)
        for edit in edits { document = try edit.applying(to: document, widgetIDs: &ids) }
        for case let .workspaces(source) in widgetSets where source != configuration.workspaceSource {
            document["workspaceSource"] = .string(source.rawValue)
        }
        return try configurationData(document, editing: data)
    }
}

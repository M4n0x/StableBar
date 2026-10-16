/// The events StableBar knows. Widgets and providers subscribe to them with `events`, beside
/// distributed notification names. README.md lists the same events, in the same order, in the
/// table under "Script events"; `builtInEventsMatchTheReadmeTable` checks it.
enum BuiltInEvent: String, CaseIterable, Sendable {
    case frontApp, workspace, aerospaceMode, wake, yabai, powerSourceChange

    /// When StableBar sends the event: the table's "Sent when" column.
    var trigger: String {
        switch self {
        case .frontApp: "The frontmost app changes"
        case .workspace: "The focused workspace changes"
        case .aerospaceMode: "AeroSpace switches binding mode"
        case .wake: "The Mac wakes from sleep"
        case .yabai: "`StableBar --trigger yabai` runs, usually from a yabai signal; StableBar also refreshes its workspaces"
        case .powerSourceChange: "The Mac switches between its power adapter and battery"
        }
    }

    /// What `INFO` holds: the table's `INFO` column.
    var info: String {
        switch self {
        case .frontApp: "The app's name, or `Desktop`"
        case .workspace: "The workspace's name; `SID` is its display number"
        case .aerospaceMode: "The mode's name"
        case .wake: "Not set"
        case .yabai: "The trigger's `INFO`, if any"
        case .powerSourceChange: "`ac` or `battery`"
        }
    }

    /// For an event a data source sends: the event's variables when that source's output changes
    /// from `previous` to `output`, or `nil` when the change doesn't send it.
    func variables(from previous: ScriptOutput, to output: ScriptOutput) -> [String: String]? {
        switch self {
        case .powerSourceChange:
            func source(_ output: ScriptOutput) -> String { output.fields?["state"] == "battery" ? "battery" : "ac" }
            return source(previous) == source(output) ? nil : ["INFO": source(output)]
        default:
            return nil
        }
    }
}

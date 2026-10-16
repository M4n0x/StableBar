import Foundation

/// The events StableBar sends itself. Widgets and providers subscribe to them with `events`, beside
/// distributed notification names. README.md lists the same events, in the same order, in the
/// table under "Script events"; `builtInEventsMatchTheReadmeTable` checks it.
enum BuiltInEvent: String, CaseIterable, Sendable {
    case frontApp, workspace, aerospaceMode, wake, yabai

    /// When StableBar sends the event: the table's "Sent when" column.
    var trigger: String {
        switch self {
        case .frontApp: "The frontmost app changes"
        case .workspace: "The focused workspace changes"
        case .aerospaceMode: "AeroSpace switches binding mode"
        case .wake: "The Mac wakes from sleep"
        case .yabai: "`StableBar --trigger yabai` runs, usually from a yabai signal; StableBar also refreshes its workspaces"
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
        }
    }
}

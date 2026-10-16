import AppKit

/// What a widget shows: its text and icon, and the fields its layout blocks read, which add
/// `text` and `icon` to the output's own fields.
struct WidgetLabel: Equatable, Sendable {
    var text: String
    var icon: String?
    var fields: [String: String]
}

extension WidgetConfiguration {
    /// This widget's label: a text widget's text, a clock's time at `date`, the frontmost app's
    /// name (`activeApp`, else Desktop), or its script or provider output. The bar, the More widgets
    /// menu and Diagnostics all read it here. Workspaces and spacers have no text.
    func label(output: ScriptOutput?, activeApp: String?, date: Date) -> WidgetLabel {
        var icon = self.icon
        let text: String
        switch content {
        case let .text(value):
            text = value
        case let .clock(format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            text = formatter.string(from: date)
        case .activeApp:
            text = activeApp ?? "Desktop"
        case .script, .provider:
            text = output?.text ?? "…"
            icon = output?.icon ?? icon
        case .workspaces, .spacer:
            return WidgetLabel(text: "", icon: icon, fields: output?.fields ?? [:])
        }
        var fields = output?.fields ?? [:]
        fields["text"] = text
        fields["icon"] = icon ?? ""
        return WidgetLabel(text: text, icon: icon, fields: fields)
    }
}

extension BarStore {
    /// `widget`'s label from its current output. Only active-app widgets read the frontmost app, so
    /// switching apps redraws no other widget.
    func label(for widget: WidgetConfiguration, date: Date = .now) -> WidgetLabel {
        widget.label(output: scripts[widget.id]?.output,
                     activeApp: widget.content == .activeApp ? activeApp?.localizedName : nil, date: date)
    }
}

import AppKit
import Observation

@MainActor @Observable
final class ConfigurationEditor {
    let store: BarStore
    let preview: BarStore
    var edits: [ConfigurationEdit] = []
    var undoSteps: [[ConfigurationEdit]] = []
    var redoSteps: [[ConfigurationEdit]] = []
    var selectedID: String?
    var error: String?
    var document: [String: ConfigurationValue] = [:]

    init(store: BarStore) {
        self.store = store
        preview = BarStore(configurationURL: store.configurationURL)
        refresh()
        selectedID = preview.configuration?.widgets.first?.id
    }

    var selected: [String: ConfigurationValue] {
        guard let selectedID, case let .array(widgets) = document["widgets"] else { return [:] }
        for case let .object(widget) in widgets where widget["id"] == .string(selectedID) { return widget }
        return [:]
    }

    var selectedStyle: [String: ConfigurationValue] {
        let defaults = document["defaults"] ?? .object([:])
        let style = (selected["style"] ?? .object([:])).overriding(defaults)
        if case let .object(properties) = style { return properties }
        return [:]
    }

    func refresh() {
        do {
            var loader = ConfigurationLoader()
            let root = try store.editedDocument(edits)
            preview.configuration = try loader.load(store.configurationURL, data: configurationData(root), context: store.context)
            preview.scripts = store.scripts
            preview.activeApp = store.activeApp
            preview.activeDisplayID = store.activeDisplayID
            preview.aerospace.workspaces = store.aerospace.workspaces
            if !preview.configuration!.widgets.contains(where: { $0.id == selectedID }) {
                selectedID = preview.configuration!.widgets.first?.id
            }
            document = loader.document
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func change(_ edit: ConfigurationEdit) {
        undoSteps.append(edits)
        redoSteps.removeAll()
        edits.append(edit)
        refresh()
    }

    func set(_ properties: [String: ConfigurationValue]) {
        guard let selectedID else { return }
        var current = selected
        current["style"] = .object(selectedStyle)
        let previous = ConfigurationValue.object(current)
        if error == nil && ConfigurationValue.object(properties).overriding(previous) == previous { return }
        change(ConfigurationEdit(action: .set, id: selectedID, properties: properties))
    }

    func undo() {
        guard let previous = undoSteps.popLast() else { return }
        redoSteps.append(edits)
        edits = previous
        refresh()
    }

    func redo() {
        guard let next = redoSteps.popLast() else { return }
        undoSteps.append(edits)
        edits = next
        refresh()
    }

    func apply() {
        do {
            try store.applyEdits(edits, persist: true)
            discard()
        } catch { self.error = error.localizedDescription }
    }

    func discard() {
        edits = []
        undoSteps = []
        redoSteps = []
        refresh()
    }
}

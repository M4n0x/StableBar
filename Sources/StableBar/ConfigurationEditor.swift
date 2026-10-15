import AppKit
import Observation

@MainActor @Observable
final class ConfigurationEditor {
    let store: BarStore
    var undoSteps: [[ConfigurationEdit]] = []
    var redoSteps: [[ConfigurationEdit]] = []
    var selectedID: String?
    var error: String?

    init(store: BarStore) {
        self.store = store
        selectedID = store.configuration?.widgets.first?.id
    }

    var selected: [String: ConfigurationValue] {
        guard let selectedID, case let .array(widgets) = store.effectiveDocument["widgets"] else { return [:] }
        for case let .object(widget) in widgets where widget["id"] == .string(selectedID) { return widget }
        return [:]
    }

    var selectedStyle: [String: ConfigurationValue] {
        let defaults = store.effectiveDocument["defaults"] ?? .object([:])
        let style = (selected["style"] ?? .object([:])).overriding(defaults)
        if case let .object(properties) = style { return properties }
        return [:]
    }

    func change(_ edit: ConfigurationEdit) {
        let previous = store.sessionEdits
        let merging = [.set, .bar, .defaults].contains(edit.action) && previous.last.map {
            $0.action == edit.action && $0.id == edit.id && propertyPaths($0.properties!) == propertyPaths(edit.properties!)
        } == true
        do {
            if merging { try store.setSessionEdits(previous.dropLast() + [edit]) }
            else { try store.applyEdits([edit], persist: false) }
            if !merging { undoSteps.append(previous) }
            redoSteps.removeAll()
            error = nil
        } catch {
            self.error = errorMessage(error)
        }
        keepSelection()
    }

    func set(_ properties: [String: ConfigurationValue]) {
        guard let selectedID else { return }
        var current = selected
        current["style"] = .object(selectedStyle)
        let previous = ConfigurationValue.object(current)
        if ConfigurationValue.object(properties).overriding(previous) == previous {
            error = nil
            return
        }
        change(ConfigurationEdit(action: .set, id: selectedID, properties: properties))
    }

    func replaceProperties(_ properties: [String: ConfigurationValue]) {
        var current = selected
        current["id"] = nil
        set(changedProperties(from: current, to: properties))
    }

    func undo() {
        guard let previous = undoSteps.popLast() else { return }
        redoSteps.append(store.sessionEdits)
        restore(previous)
    }

    func redo() {
        guard let next = redoSteps.popLast() else { return }
        undoSteps.append(store.sessionEdits)
        restore(next)
    }

    func save() {
        do {
            try store.applyEdits([], persist: true)
            undoSteps = []
            redoSteps = []
            error = nil
        } catch { self.error = errorMessage(error) }
    }

    func discard() {
        undoSteps = []
        redoSteps = []
        restore([])
    }

    private func restore(_ edits: [ConfigurationEdit]) {
        do {
            try store.setSessionEdits(edits)
            error = nil
        } catch { self.error = errorMessage(error) }
        keepSelection()
    }

    private func keepSelection() {
        if store.configuration?.widgets.contains(where: { $0.id == selectedID }) != true {
            selectedID = store.configuration?.widgets.first?.id
        }
    }
}

private func propertyPaths(_ properties: [String: ConfigurationValue], prefix: String = "") -> Set<String> {
    properties.reduce(into: []) { paths, property in
        if case let .object(object) = property.value { paths.formUnion(propertyPaths(object, prefix: prefix + property.key + ".")) }
        else { paths.insert(prefix + property.key) }
    }
}

private func changedProperties(from current: [String: ConfigurationValue], to edited: [String: ConfigurationValue]) -> [String: ConfigurationValue] {
    var changes: [String: ConfigurationValue] = [:]
    for (key, value) in edited where current[key] != value {
        if case let .object(old) = current[key], case let .object(new) = value {
            changes[key] = .object(changedProperties(from: old, to: new))
        } else {
            changes[key] = value
        }
    }
    for key in current.keys where edited[key] == nil { changes[key] = .null }
    return changes
}

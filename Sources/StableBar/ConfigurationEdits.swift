import Foundation

struct ConfigurationEdit: Codable, Sendable {
    enum Action: String, Codable { case set, add, remove, reorder, bar, defaults, profile, package }
    let action: Action
    var id: String?
    var properties: [String: ConfigurationValue]?
    var ids: [String]?
    var name: String?

    func validateTargets(in widgetIDs: [String]) throws {
        switch action {
        case .set, .remove: _ = try target(in: widgetIDs)
        case .add:
            let widget = try requiredProperties()
            guard let id = try widget["id"]?.decoded(String.self), !widgetIDs.contains(id) else {
                throw CommandFailure(message: "Add requires a new, unique widget id.")
            }
        case .reorder:
            guard let ids, Set(ids).count == ids.count, ids.allSatisfy(widgetIDs.contains) else {
                throw CommandFailure(message: "Reorder requires unique existing widget ids.")
            }
        default: break
        }
    }

    func applying(to document: [String: ConfigurationValue], widgetIDs: inout [String]) throws -> [String: ConfigurationValue] {
        var root = document
        var customization = try root["customization"]?.decoded([String: ConfigurationValue].self) ?? [:]
        switch action {
        case .set:
            let id = id!
            let properties = try requiredProperties()
            guard properties["id"] == nil else { throw CommandFailure(message: "Set cannot change a widget id.") }
            var overrides = try customization["widgetOverrides"]?.decoded([String: ConfigurationValue].self) ?? [:]
            overrides[id] = .object(properties).overriding(overrides[id] ?? .object([:]))
            customization["widgetOverrides"] = .object(overrides)
        case .add:
            let widget = try requiredProperties()
            let id = try widget["id"]!.decoded(String.self)
            let removed = try root["removedWidgets"]?.decoded([String].self) ?? []
            if removed.contains(id) {
                var overrides = try customization["widgetOverrides"]?.decoded([String: ConfigurationValue].self) ?? [:]
                var properties = widget
                properties.removeValue(forKey: "id")
                overrides[id] = .object(properties)
                customization["widgetOverrides"] = .object(overrides)
                root["removedWidgets"] = .array(removed.filter { $0 != id }.map(ConfigurationValue.string))
            } else {
                var widgets = try root["widgets"]?.decoded([[String: ConfigurationValue]].self) ?? []
                widgets.append(widget)
                root["widgets"] = .array(widgets.map(ConfigurationValue.object))
            }
            widgetIDs.append(id)
        case .remove:
            let id = id!
            var removed = try root["removedWidgets"]?.decoded([String].self) ?? []
            if !removed.contains(id) { removed.append(id) }
            root["removedWidgets"] = .array(removed.map(ConfigurationValue.string))
            var overrides = try customization["widgetOverrides"]?.decoded([String: ConfigurationValue].self) ?? [:]
            overrides.removeValue(forKey: id)
            customization["widgetOverrides"] = .object(overrides)
            if let order = try customization["widgetOrder"]?.decoded([String].self) {
                customization["widgetOrder"] = .array(order.filter { $0 != id }.map(ConfigurationValue.string))
            }
            widgetIDs.removeAll { $0 == id }
        case .reorder:
            let ids = ids!
            customization["widgetOrder"] = .array(ids.map(ConfigurationValue.string))
            widgetIDs = ids + widgetIDs.filter { !ids.contains($0) }
        case .bar, .defaults:
            let key = action.rawValue
            customization[key] = .object(try requiredProperties()).overriding(customization[key] ?? .object([:]))
        case .profile:
            root["profile"] = name.map(ConfigurationValue.string) ?? .null
        case .package:
            let package = try requiredProperties()
            guard let id = try package["id"]?.decoded(String.self) else {
                throw CommandFailure(message: "A package id is required.")
            }
            var packages = try root["packages"]?.decoded([[String: ConfigurationValue]].self) ?? []
            if let index = packages.firstIndex(where: { $0["id"] == .string(id) }) { packages[index] = package }
            else { packages.append(package) }
            root["packages"] = .array(packages.map(ConfigurationValue.object))
        }
        if !customization.isEmpty { root["customization"] = .object(customization) }
        return root
    }

    private func target(in ids: [String]) throws -> String {
        guard let id, ids.contains(id) else { throw CommandFailure(message: "Unknown widget: \(id ?? "(missing id)").") }
        return id
    }

    private func requiredProperties() throws -> [String: ConfigurationValue] {
        guard let properties else { throw CommandFailure(message: "\(action.rawValue) requires properties.") }
        return properties
    }
}

func configurationData(_ document: [String: ConfigurationValue]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(document)
}

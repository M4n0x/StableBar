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

func configurationData(_ document: [String: ConfigurationValue], editing original: Data) throws -> Data {
    let old = try JSONDecoder().decode(ConfigurationValue.self, from: original)
    let text = try ConfigurationText(Array(original))
    let rendered = try text.render(.object(document), old, text.root)
    return Data((text.slice(0..<text.root.start) + rendered + text.slice(text.root.end..<text.bytes.count)).utf8)
}

private struct ConfigurationTextNode {
    let start: Int
    var end = 0
    var members: [(key: Range<Int>, name: String, value: ConfigurationTextNode)] = []
    var elements: [ConfigurationTextNode] = []
}

private struct ConfigurationText {
    let bytes: [UInt8]
    var root = ConfigurationTextNode(start: 0)
    var unit = "  "
    var colon = ": "
    private var index = 0

    init(_ bytes: [UInt8]) throws {
        self.bytes = bytes
        root = try node()
        let open = slice(root.start + 1..<(root.members.first?.key.lowerBound ?? root.start + 1))
        if let newline = open.lastIndex(of: "\n"), newline != open.index(before: open.endIndex) {
            unit = String(open[open.index(after: newline)...])
            colon = slice(root.members[0].key.upperBound..<root.members[0].value.start)
        }
    }

    func slice(_ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    private mutating func node() throws -> ConfigurationTextNode {
        while " \n\r\t".utf8.contains(bytes[index]) { index += 1 }
        var node = ConfigurationTextNode(start: index)
        switch bytes[index] {
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            let isObject = bytes[index] == UInt8(ascii: "{")
            index += 1
            while true {
                while " \n\r\t".utf8.contains(bytes[index]) { index += 1 }
                if "}]".utf8.contains(bytes[index]) { break }
                if isObject {
                    let keyStart = index
                    skipString()
                    let key = keyStart..<index
                    while bytes[index] != UInt8(ascii: ":") { index += 1 }
                    index += 1
                    node.members.append((key, try JSONDecoder().decode(String.self, from: Data(bytes[key])), try self.node()))
                } else {
                    node.elements.append(try self.node())
                }
                while " \n\r\t".utf8.contains(bytes[index]) { index += 1 }
                if bytes[index] == UInt8(ascii: ",") { index += 1 }
            }
            index += 1
        case UInt8(ascii: "\""):
            skipString()
        default:
            while index < bytes.count, !",}] \n\r\t".utf8.contains(bytes[index]) { index += 1 }
        }
        node.end = index
        return node
    }

    private mutating func skipString() {
        index += 1
        while bytes[index] != UInt8(ascii: "\"") { index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1 }
        index += 1
    }

    func render(_ new: ConfigurationValue, _ old: ConfigurationValue, _ node: ConfigurationTextNode) throws -> String {
        if new == old { return slice(node.start..<node.end) }
        switch (new, old) {
        case let (.object(newObject), .object(oldObject)) where !node.members.isEmpty:
            let open = slice(node.start + 1..<node.members[0].key.lowerBound)
            let colon = slice(node.members[0].key.upperBound..<node.members[0].value.start)
            var parts: [String] = []
            for member in node.members {
                if let value = newObject[member.name] {
                    parts.append(slice(member.key) + slice(member.key.upperBound..<member.value.start)
                                 + (try render(value, oldObject[member.name]!, member.value)))
                }
            }
            for key in newObject.keys.sorted() where oldObject[key] == nil {
                parts.append(try fresh(.string(key), indent: nil) + colon + fresh(newObject[key]!, indent: childIndent(open)))
            }
            return wrap(parts, "{", "}", open: open, close: slice(node.members.last!.value.end..<node.end - 1))
        case let (.array(newArray), .array(oldArray)) where !node.elements.isEmpty:
            let open = slice(node.start + 1..<node.elements[0].start)
            var unused = Array(oldArray.indices)
            var parts: [String] = []
            for (index, element) in newArray.enumerated() {
                let match = unused.first { oldArray[$0] == element }
                    ?? unused.first { identifier(oldArray[$0]) != nil && identifier(oldArray[$0]) == identifier(element) }
                    ?? (identifier(element) == nil && unused.contains(index) ? index : nil)
                if let match {
                    unused.removeAll { $0 == match }
                    parts.append(try render(element, oldArray[match], node.elements[match]))
                } else {
                    parts.append(try fresh(element, indent: childIndent(open)))
                }
            }
            return wrap(parts, "[", "]", open: open, close: slice(node.elements.last!.end..<node.end - 1))
        default:
            return try fresh(new, indent: lineIndent(node.start))
        }
    }

    private func wrap(_ parts: [String], _ opening: String, _ closing: String, open: String, close: String) -> String {
        parts.isEmpty ? opening + closing : opening + open + parts.joined(separator: "," + open) + close + closing
    }

    private func wrap(_ parts: [String], _ opening: String, _ closing: String, indent: String?) -> String {
        guard let indent else { return wrap(parts, opening, closing, open: "", close: "") }
        return wrap(parts, opening, closing, open: "\n" + indent + unit, close: "\n" + indent)
    }

    private func childIndent(_ open: String) -> String? {
        open.lastIndex(of: "\n").map { String(open[open.index(after: $0)...]) }
    }

    private func lineIndent(_ position: Int) -> String {
        var start = position
        while start > 0, bytes[start - 1] != UInt8(ascii: "\n") { start -= 1 }
        var end = start
        while " \t".utf8.contains(bytes[end]) { end += 1 }
        return slice(start..<end)
    }

    private func identifier(_ value: ConfigurationValue) -> String? {
        if case let .object(object) = value, case let .string(id) = object["id"] { return id }
        return nil
    }

    private func fresh(_ value: ConfigurationValue, indent: String?) throws -> String {
        let inner = indent.map { $0 + unit }
        switch value {
        case let .object(object) where !object.isEmpty:
            let entries = try object.keys.sorted().map {
                try fresh(.string($0), indent: nil) + (indent == nil ? ":" : colon) + fresh(object[$0]!, indent: inner)
            }
            return wrap(entries, "{", "}", indent: indent)
        case let .array(array) where !array.isEmpty:
            return wrap(try array.map { try fresh($0, indent: inner) }, "[", "]", indent: indent)
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
    }
}

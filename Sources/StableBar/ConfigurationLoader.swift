import Foundation

indirect enum ConfigurationValue: Codable {
    case object([String: ConfigurationValue])
    case array([ConfigurationValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let object = try? value.decode([String: ConfigurationValue].self) { self = .object(object) }
        else if let array = try? value.decode([ConfigurationValue].self) { self = .array(array) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else { self = .number(try value.decode(Double.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .object(object): try value.encode(object)
        case let .array(array): try value.encode(array)
        case let .string(string): try value.encode(string)
        case let .number(number): try value.encode(number)
        case let .bool(bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }

    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }

    func overriding(_ earlier: ConfigurationValue) -> ConfigurationValue {
        if case let .object(base) = earlier, case let .object(next) = self {
            return .object(base.merging(next) { $1.overriding($0) })
        }
        return self
    }
}

enum ConfigurationCompositionError: LocalizedError {
    case includeCycle([URL])
    case unknownTemplate(String)
    case templateCycle([String])
    case unknownWidgetOverride(String)
    case widgetOverrideID(String)

    var errorDescription: String? {
        switch self {
        case let .includeCycle(urls): "Configuration include cycle: \(urls.map(\.path).joined(separator: " → "))."
        case let .unknownTemplate(name): "Unknown widget template: \(name)."
        case let .templateCycle(names): "Widget template cycle: \(names.joined(separator: " → "))."
        case let .unknownWidgetOverride(id): "Unknown widget override target: \(id)."
        case let .widgetOverrideID(id): "Widget override \(id) cannot contain an id field."
        }
    }
}

func expandWidgetTemplate(_ definition: [String: ConfigurationValue],
                          templates: [String: [String: ConfigurationValue]],
                          path: [String] = []) throws -> [String: ConfigurationValue] {
    guard let reference = definition["template"] else { return definition }
    let name = try reference.decoded(String.self)
    guard !path.contains(name) else {
        throw ConfigurationCompositionError.templateCycle(path + [name])
    }
    guard let template = templates[name] else {
        throw ConfigurationCompositionError.unknownTemplate(name)
    }
    let inherited = try expandWidgetTemplate(template, templates: templates, path: path + [name])
    return inherited.merging(definition) { $1.overriding($0) }
}

struct ConfigurationLoader {
    private(set) var dependencies: Set<URL> = []

    mutating func load(_ url: URL, data: Data? = nil) throws -> Configuration {
        dependencies = []
        let document = try read(url.standardizedFileURL, data: data, path: [])
        return try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(document))
    }

    private mutating func read(_ url: URL, data: Data? = nil, path: [URL]) throws -> [String: ConfigurationValue] {
        dependencies.insert(url)
        let canonical = url.resolvingSymlinksInPath()
        guard !path.contains(canonical) else {
            throw ConfigurationCompositionError.includeCycle(path + [canonical])
        }
        var document = try JSONDecoder().decode([String: ConfigurationValue].self, from: data ?? Data(contentsOf: url))
        let includes = try document.removeValue(forKey: "includes")?.decoded([String].self) ?? []
        var merged: [String: ConfigurationValue] = ["widgets": .array([])]
        for include in includes {
            let file = URL(fileURLWithPath: (include as NSString).expandingTildeInPath,
                           relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            let module = try read(file, path: path + [canonical])
            let widgets = try merged["widgets"]!.decoded([ConfigurationValue].self)
                + module["widgets"]!.decoded([ConfigurationValue].self)
            merged.merge(module) { $1.overriding($0) }
            merged["widgets"] = .array(widgets)
        }
        let widgets = try merged["widgets"]!.decoded([ConfigurationValue].self)
            + (document["widgets"]?.decoded([ConfigurationValue].self) ?? [])
        merged.merge(document) { $1.overriding($0) }
        merged["widgets"] = .array(widgets)
        return merged
    }
}

@MainActor
final class ConfigurationWatcher {
    var onChange: (() -> Void)?
    private var sources: [DispatchSourceFileSystemObject] = []

    func watch(_ urls: Set<URL>) {
        stop()
        var targets = urls
        for url in urls {
            var directory = url.deletingLastPathComponent()
            while !FileManager.default.fileExists(atPath: directory.path) {
                directory.deleteLastPathComponent()
            }
            targets.insert(directory)
        }
        for url in targets {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.onChange?() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        for source in sources { source.cancel() }
        sources.removeAll()
    }
}

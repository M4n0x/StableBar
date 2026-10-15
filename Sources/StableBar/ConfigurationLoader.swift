import Foundation

indirect enum ConfigurationValue: Codable, Sendable, Equatable {
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
    case unknownWidgetOrder(String)
    case duplicateWidgetOrder(String)

    var errorDescription: String? {
        switch self {
        case let .includeCycle(urls): "Configuration include cycle: \(urls.map(\.path).joined(separator: " → "))."
        case let .unknownTemplate(name): "Unknown widget template: \(name)."
        case let .templateCycle(names): "Widget template cycle: \(names.joined(separator: " → "))."
        case let .unknownWidgetOverride(id): "Unknown widget override target: \(id)."
        case let .widgetOverrideID(id): "Widget override \(id) cannot contain an id field."
        case let .unknownWidgetOrder(id): "Unknown widget order target: \(id)."
        case let .duplicateWidgetOrder(id): "Duplicate widget order target: \(id)."
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

struct ConfigurationLayer {
    var values: [String: ConfigurationValue]
    var origins: [String: String]

    mutating func merge(_ next: ConfigurationLayer) throws {
        let widgets = try (values["widgets"]?.decoded([ConfigurationValue].self) ?? [])
            + (next.values["widgets"]?.decoded([ConfigurationValue].self) ?? [])
        let previousPackages = values["packages"]
        values.merge(next.values) { $1.overriding($0) }
        if let selections = next.values["packages"] {
            var packages = try previousPackages?.decoded([[String: ConfigurationValue]].self) ?? []
            for selection in try selections.decoded([[String: ConfigurationValue]].self) {
                let id = try (selection["id"] ?? .null).decoded(String.self)
                if let index = packages.firstIndex(where: { $0["id"] == .string(id) }) {
                    packages[index].merge(selection) { $1.overriding($0) }
                } else {
                    packages.append(selection)
                }
            }
            values["packages"] = .array(packages.map(ConfigurationValue.object))
        }
        values["widgets"] = .array(widgets)
        origins.merge(next.origins) { $1 }
    }
}

func configurationOrigins(_ value: ConfigurationValue, source: String, path: String = "") -> [String: String] {
    var origins = path.isEmpty ? [:] : [path: source]
    switch value {
    case let .object(object):
        for (key, value) in object {
            let child = path.isEmpty ? key : "\(path).\(key)"
            origins.merge(configurationOrigins(value, source: source, path: child)) { $1 }
        }
    case let .array(array):
        for (index, value) in array.enumerated() {
            var key = String(index)
            if path == "widgets", case let .object(widget) = value, case let .string(id) = widget["id"] {
                key = id
            }
            origins.merge(configurationOrigins(value, source: source, path: "\(path).\(key)")) { $1 }
        }
    default: break
    }
    return origins
}

struct ConfigurationLoader {
    private(set) var dependencies: Set<URL> = []
    private(set) var document: [String: ConfigurationValue] = [:]
    private(set) var origins: [String: String] = [:]
    private(set) var activeProfiles: [String] = []
    private(set) var templates: [String: [String: ConfigurationValue]] = [:]
    private var packageSources: [String: URL] = [:]

    mutating func load(_ url: URL, data: Data? = nil,
                       context: ConfigurationContext = ConfigurationContext()) throws -> Configuration {
        try ConfigurationValue.object(compose(url, data: data, context: context)).decoded(Configuration.self)
    }

    mutating func compose(_ url: URL, data: Data? = nil,
                          context: ConfigurationContext = ConfigurationContext()) throws -> [String: ConfigurationValue] {
        dependencies = []
        activeProfiles = []
        packageSources = [:]
        let base = try read(url.standardizedFileURL, data: data, path: [])
        let packageStore = WidgetPackageStore(directory: url.deletingLastPathComponent().appending(path: "packages"))
        var layer = ConfigurationLayer(values: ["widgets": .array([])], origins: [:])
        for selection in try base.values["packages"]?.decoded([WidgetPackageSelection].self) ?? [] where selection.enabled {
            let directory = try packageStore.directory(id: selection.id, version: selection.version)
            dependencies.insert(directory.appending(path: "package.json"))
            let manifest = try packageStore.manifest(at: directory)
            guard manifest.id == selection.id, manifest.version == selection.version else {
                throw WidgetPackageError.manifestMismatch
            }
            try packageStore.validateContents(at: directory)
            try layer.merge(readPackage(at: directory, manifest: manifest, settings: selection.settings))
        }
        try layer.merge(base)
        return try finish(layer, context: context)
    }

    mutating func finish(_ input: ConfigurationLayer, context: ConfigurationContext) throws -> [String: ConfigurationValue] {
        var layer = input
        activeProfiles = []
        let profiles = try layer.values["profiles"]?.decoded([ConfigurationProfile].self) ?? []
        let selected = try layer.values["profile"].flatMap { try $0.decoded(String?.self) }
        var names = Set<String>()
        for profile in profiles {
            guard names.insert(profile.name).inserted else { throw ThemeConfigurationError.duplicateProfile(profile.name) }
        }
        if let selected, !names.contains(selected) { throw ThemeConfigurationError.unknownProfile(selected) }
        for (index, profile) in profiles.enumerated() {
            let matches = selected.map { $0 == profile.name } ?? (profile.when?.matches(context) ?? true)
            if matches {
                let source = "\(layer.origins["profiles.\(index).name"]!) (profile \(profile.name))"
                try layer.merge(ConfigurationLayer(values: profile.configuration,
                    origins: configurationOrigins(.object(profile.configuration), source: source)))
                activeProfiles.append(profile.name)
            }
        }
        let strictOverrides = layer.values["widgetOverrides"] ?? .object([:])
        let customization = try input.values["customization"]?.decoded([String: ConfigurationValue].self) ?? [:]
        if !customization.isEmpty {
            let origins = Dictionary(uniqueKeysWithValues: input.origins.compactMap { path, source in
                path.hasPrefix("customization.") ? (String(path.dropFirst(14)), "\(source) (customization)") : nil
            })
            try layer.merge(ConfigurationLayer(values: customization, origins: origins))
        }
        for key in ["profiles", "profile", "customization"] { layer.values.removeValue(forKey: key) }
        let tokens = try layer.values["tokens"]?.decoded([String: ConfigurationValue].self) ?? [:]
        let beforeTokens = layer.values
        layer.values = try substituteConfigurationReferences(.object(layer.values), prefix: "@token.", values: tokens)
            .decoded([String: ConfigurationValue].self)
        layer.origins.merge(try tokenOrigins(.object(beforeTokens), origins: layer.origins, tokens: tokens)) { $1 }
        templates = try layer.values["templates"]?.decoded([String: [String: ConfigurationValue]].self) ?? [:]
        let overrides = try layer.values["widgetOverrides"]?.decoded([String: [String: ConfigurationValue]].self) ?? [:]
        let removed = Set(try layer.values["removedWidgets"]?.decoded([String].self) ?? [])
        let definitions = try layer.values["widgets"]!.decoded([[String: ConfigurationValue]].self)
        var widgets: [[String: ConfigurationValue]] = []
        for definition in definitions {
            var expanded = try expandWidgetTemplate(definition, templates: templates)
            let id = try (expanded["id"] ?? .null).decoded(String.self)
            if removed.contains(id) { continue }
            if let properties = overrides[id] {
                guard properties["id"] == nil else { throw ConfigurationCompositionError.widgetOverrideID(id) }
                expanded.merge(properties) { $1.overriding($0) }
            }
            var propertyOrigins = try templateOrigins(definition, templates: templates, origins: layer.origins)
            let widgetPrefix = "widgets.\(id)"
            for (path, source) in layer.origins where path.hasPrefix(widgetPrefix + ".") {
                propertyOrigins[String(path.dropFirst(widgetPrefix.count + 1))] = source
            }
            let overridePrefix = "widgetOverrides.\(id)."
            for (path, source) in layer.origins where path.hasPrefix(overridePrefix) {
                propertyOrigins[String(path.dropFirst(overridePrefix.count))] = "\(source) (widget override)"
            }
            expanded.removeValue(forKey: "template")
            for (path, source) in propertyOrigins { layer.origins["\(widgetPrefix).\(path)"] = source }
            widgets.append(expanded)
        }
        let ids = try widgets.map { try $0["id"]!.decoded(String.self) }
        var uniqueIDs = Set<String>()
        for id in ids where !uniqueIDs.insert(id).inserted {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Duplicate widget id: \(id). Each widget needs a stable, unique id."))
        }
        let requiredOverrides = try substituteConfigurationReferences(strictOverrides, prefix: "@token.", values: tokens)
            .decoded([String: ConfigurationValue].self)
        for id in requiredOverrides.keys where !ids.contains(id) && !removed.contains(id) {
            throw ConfigurationCompositionError.unknownWidgetOverride(id)
        }
        var order = try layer.values["widgetOrder"]?.decoded([String].self) ?? []
        if customization["widgetOrder"] != nil { order = order.filter(ids.contains) }
        var orderedIDs = Set<String>()
        for id in order {
            guard orderedIDs.insert(id).inserted else { throw ConfigurationCompositionError.duplicateWidgetOrder(id) }
            guard ids.contains(id) else { throw ConfigurationCompositionError.unknownWidgetOrder(id) }
        }
        let ordered = order.compactMap { id in widgets.first { $0["id"] == .string(id) } }
            + zip(ids, widgets).filter { !orderedIDs.contains($0.0) }.map(\.1)
        layer.values["widgets"] = .array(ordered.map { .object($0) })
        for key in ["templates", "widgetOverrides", "includes", "removedWidgets", "widgetOrder"] {
            layer.values.removeValue(forKey: key)
        }
        document = try preparePackageAssets(.object(layer.values), origins: layer.origins, sources: packageSources)
            .decoded([String: ConfigurationValue].self)
        let finalPaths = configurationOrigins(.object(document), source: "")
        origins = layer.origins.filter { finalPaths[$0.key] != nil }
        return document
    }

    private func tokenOrigins(_ value: ConfigurationValue, path: String = "", inheritedSource: String = "",
                              origins: [String: String], tokens: [String: ConfigurationValue]) throws -> [String: String] {
        let source = origins[path] ?? inheritedSource
        switch value {
        case let .string(reference) where reference.hasPrefix("@token."):
            let name = String(reference.dropFirst(7))
            let resolved = try substituteConfigurationReferences(value, prefix: "@token.", values: tokens)
            return configurationOrigins(resolved, source: "\(source) → token \(name) (\(origins["tokens.\(name)"]!))", path: path)
        case let .object(object):
            var result: [String: String] = [:]
            for (key, child) in object {
                result.merge(try tokenOrigins(child, path: path.isEmpty ? key : "\(path).\(key)",
                                              inheritedSource: source, origins: origins, tokens: tokens)) { $1 }
            }
            return result
        case let .array(array):
            var result: [String: String] = [:]
            for (index, child) in array.enumerated() {
                var key = String(index)
                if path == "widgets", case let .object(widget) = child, case let .string(id) = widget["id"] { key = id }
                result.merge(try tokenOrigins(child, path: "\(path).\(key)", inheritedSource: source, origins: origins, tokens: tokens)) { $1 }
            }
            return result
        default: return [:]
        }
    }

    private func templateOrigins(_ definition: [String: ConfigurationValue],
                                 templates: [String: [String: ConfigurationValue]],
                                 origins: [String: String]) throws -> [String: String] {
        guard let reference = definition["template"] else { return [:] }
        let name = try reference.decoded(String.self)
        var inherited = try templateOrigins(templates[name]!, templates: templates, origins: origins)
        let prefix = "templates.\(name)."
        for (path, source) in origins where path.hasPrefix(prefix) {
            inherited[String(path.dropFirst(prefix.count))] = "\(source) (template \(name))"
        }
        return inherited
    }

    private mutating func read(_ url: URL, data: Data? = nil, path: [URL], boundary: URL? = nil) throws -> ConfigurationLayer {
        dependencies.insert(url)
        let canonical = url.resolvingSymlinksInPath()
        if let boundary {
            try validatePackagePath(url, inside: boundary)
            packageSources[url.path] = boundary
        }
        guard !path.contains(canonical) else {
            throw ConfigurationCompositionError.includeCycle(path + [canonical])
        }
        var values = try JSONDecoder().decode([String: ConfigurationValue].self, from: data ?? Data(contentsOf: url))
        let includes = try values.removeValue(forKey: "includes")?.decoded([String].self) ?? []
        var merged = ConfigurationLayer(values: ["widgets": .array([])], origins: [:])
        if boundary != nil, values["packages"] != nil { throw WidgetPackageError.nestedPackages }
        for include in includes {
            let file = URL(fileURLWithPath: (include as NSString).expandingTildeInPath,
                           relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            try merged.merge(read(file, path: path + [canonical], boundary: boundary))
        }
        try merged.merge(ConfigurationLayer(values: values, origins: configurationOrigins(.object(values), source: url.path)))
        return merged
    }

    mutating func readPackage(at directory: URL, manifest: WidgetPackageManifest,
                                      settings: [String: ConfigurationValue]) throws -> ConfigurationLayer {
        dependencies.insert(directory.appending(path: "package.json"))
        let entry = try packageFile(manifest.entry, inside: directory)
        var layer = try read(entry, path: [], boundary: directory)
        let values = try manifest.values(settings)
        layer.values = try substituteConfigurationReferences(.object(layer.values), prefix: "@setting.", values: values)
            .decoded([String: ConfigurationValue].self)
        layer.values = try preparePackageDocument(layer.values, directory: directory)
        return layer
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

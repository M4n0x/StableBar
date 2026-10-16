import Foundation

struct WidgetPackageSetting: Codable, Sendable {
    let type: String
    let title: String?
    let `default`: ConfigurationValue

    enum CodingKeys: String, CodingKey, CaseIterable { case type, title, `default` }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        `default` = try values.decode(ConfigurationValue.self, forKey: .default)
    }

    func accepts(_ value: ConfigurationValue) -> Bool {
        switch (type, value) {
        case ("string", .string), ("number", .number), ("bool", .bool): true
        default: false
        }
    }
}

struct WidgetPackageManifest: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case theme, widgets }

    let id: String
    let name: String
    let version: String
    let kind: Kind?
    let entry: String
    let settings: [String: WidgetPackageSetting]

    enum CodingKeys: String, CodingKey, CaseIterable { case id, name, version, kind, entry, settings }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        version = try values.decode(String.self, forKey: .version)
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind)
        entry = try values.decode(String.self, forKey: .entry)
        settings = try values.decodeIfPresent([String: WidgetPackageSetting].self, forKey: .settings) ?? [:]
        try validatePackageComponent(id)
        try validatePackageComponent(version)
        for (name, setting) in settings where !setting.accepts(setting.default) {
            throw WidgetPackageError.invalidSetting(name)
        }
    }

    func values(_ supplied: [String: ConfigurationValue]) throws -> [String: ConfigurationValue] {
        var values = settings.mapValues(\.default)
        for (name, value) in supplied {
            guard let setting = settings[name] else { throw WidgetPackageError.unknownSetting(name) }
            guard setting.accepts(value) else { throw WidgetPackageError.invalidSetting(name) }
            values[name] = value
        }
        return values
    }
}

struct WidgetPackageSelection: Decodable {
    let id: String
    var version: String?
    var enabled = true
    var settings: [String: ConfigurationValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable { case id, version, enabled, settings }

    init(id: String) {
        self.id = id
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        settings = try values.decodeIfPresent([String: ConfigurationValue].self, forKey: .settings) ?? [:]
        try validatePackageComponent(id)
        if let version { try validatePackageComponent(version) }
    }

    var key: String { version.map { "\(id)/\($0)" } ?? id }
}

struct WidgetPackageInspection: Sendable {
    let manifest: WidgetPackageManifest
    let directory: URL
    let commands: [String]
}

enum WidgetPackageError: LocalizedError {
    case invalidComponent(String)
    case outsidePackage(String)
    case missingFile(String)
    case alreadyInstalled(String, String)
    case unknownSetting(String)
    case invalidSetting(String)
    case nestedPackages
    case manifestMismatch
    case notATheme(String)
    case themeInPackages(String)
    case themeProperty(String)
    case widgetsProperty(String)
    case widgetsCommand(String)
    case missingVersion(String)
    case unknownTheme(String)

    var errorDescription: String? {
        switch self {
        case let .invalidComponent(value): "Invalid package id or version: \(value). Use letters, numbers, dots, dashes, and underscores."
        case let .outsidePackage(path): "Package path escapes its directory: \(path)."
        case let .missingFile(path): "Package file does not exist: \(path)."
        case let .alreadyInstalled(id, version): "Package \(id) \(version) is already installed. Choose a new version to replace it."
        case let .unknownSetting(name): "Unknown package setting: \(name)."
        case let .invalidSetting(name): "Invalid type or default for package setting: \(name)."
        case .nestedPackages: "A widget package cannot activate other packages."
        case .manifestMismatch: "The package manifest does not match its pinned id and version."
        case let .notATheme(id): "Package \(id) is not a theme. Enable it in packages instead."
        case let .themeInPackages(id): "Package \(id) is a theme. Select it with the theme key instead of packages."
        case let .themeProperty(key): "A theme can contain only tokens, defaults, bar, groups and profiles, not \(key)."
        case let .widgetsProperty(key): "A widgets package can contain only tokens, defaults, bar, groups, profiles, widgets, templates, popups and providers, not \(key)."
        case let .widgetsCommand(key): "A widgets package cannot contain \(key)."
        case let .missingVersion(id): "Package \(id) needs a version."
        case let .unknownTheme(id): "No theme named \(id) ships with StableBar. Add a version to select an installed theme package."
        }
    }
}

func validatePackageComponent(_ value: String) throws {
    guard !value.isEmpty, value != ".", value != "..",
          value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }) else {
        throw WidgetPackageError.invalidComponent(value)
    }
}

func validatePackagePath(_ url: URL, inside directory: URL) throws {
    let root = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root) else {
        throw WidgetPackageError.outsidePackage(url.path)
    }
}

func packageFile(_ path: String, inside directory: URL) throws -> URL {
    guard !(path as NSString).isAbsolutePath, !path.hasPrefix("~") else {
        throw WidgetPackageError.outsidePackage(path)
    }
    let url = URL(fileURLWithPath: path, relativeTo: directory.appending(path: "", directoryHint: .isDirectory)).standardizedFileURL
    try validatePackagePath(url, inside: directory)
    guard FileManager.default.fileExists(atPath: url.path) else { throw WidgetPackageError.missingFile(path) }
    return url
}

struct WidgetPackageStore {
    let directory: URL

    func directory(id: String, version: String) throws -> URL {
        try validatePackageComponent(id)
        try validatePackageComponent(version)
        let url = directory.appending(path: id).appending(path: version)
        try validatePackagePath(url, inside: directory)
        return url
    }

    func manifest(at source: URL) throws -> WidgetPackageManifest {
        let file = try packageFile("package.json", inside: source)
        return try JSONDecoder().decode(WidgetPackageManifest.self, from: Data(contentsOf: file))
    }

    func validateContents(at source: URL) throws {
        let files = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey])!
        for case let file as URL in files {
            try validatePackagePath(file, inside: source)
        }
    }

    func inspect(_ source: URL, settings: [String: ConfigurationValue] = [:]) throws -> WidgetPackageInspection {
        let manifest = try manifest(at: source)
        try validateContents(at: source)
        var loader = ConfigurationLoader()
        let layer = try loader.readPackage(at: source, manifest: manifest, settings: settings)
        let profiles = try layer.values["profiles"]?.decoded([ConfigurationProfile].self) ?? []
        var documents = [try loader.finish(layer, context: ConfigurationContext())]
        var commands = Set(packageCommands(.object(loader.templates.mapValues(ConfigurationValue.object))))
        for profile in profiles {
            var selected = layer
            selected.values["profile"] = .string(profile.name)
            documents.append(try loader.finish(selected, context: ConfigurationContext()))
            commands.formUnion(packageCommands(.object(loader.templates.mapValues(ConfigurationValue.object))))
        }
        for document in documents {
            _ = try ConfigurationValue.object(document).decoded(Configuration.self)
            commands.formUnion(packageCommands(.object(document)))
        }
        return WidgetPackageInspection(manifest: manifest, directory: source, commands: commands.sorted())
    }

    func install(_ source: URL) throws -> WidgetPackageInspection {
        let inspection = try inspect(source)
        let destination = try directory(id: inspection.manifest.id, version: inspection.manifest.version)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw WidgetPackageError.alreadyInstalled(inspection.manifest.id, inspection.manifest.version)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appending(path: ".install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        _ = try inspect(staging)
        try FileManager.default.moveItem(at: staging, to: destination)
        return try inspect(destination)
    }

    func list() throws -> [WidgetPackageManifest] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var manifests: [WidgetPackageManifest] = []
        for package in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for version in try FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                try validatePackagePath(version, inside: directory)
                manifests.append(try manifest(at: version))
            }
        }
        return manifests.sorted { ($0.id, $0.version) < ($1.id, $1.version) }
    }
}

struct ThemeChoice {
    let manifest: WidgetPackageManifest
    let directory: URL
    let isBundled: Bool

    var key: String { isBundled ? manifest.id : manifest.versionKey }
    var title: String { isBundled ? manifest.name : "\(manifest.name) · \(manifest.version)" }
    var selection: [String: ConfigurationValue] {
        isBundled ? ["id": .string(manifest.id)] : ["id": .string(manifest.id), "version": .string(manifest.version)]
    }
}

func themeChoices(packages: URL) -> [ThemeChoice] {
    let bundled = ((bundledThemesDirectory.flatMap {
        try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }) ?? []).filter { $0.lastPathComponent != "built-in" }.compactMap { directory in
        (try? WidgetPackageStore(directory: directory).manifest(at: directory)).map { ThemeChoice(manifest: $0, directory: directory, isBundled: true) }
    }
    let installed = ((try? WidgetPackageStore(directory: packages).list()) ?? []).filter { $0.kind == .theme }.map {
        ThemeChoice(manifest: $0, directory: packages.appending(path: $0.id).appending(path: $0.version), isBundled: false)
    }
    return bundled.sorted { $0.manifest.name < $1.manifest.name } + installed
}

func preparePackageDocument(_ document: [String: ConfigurationValue], directory: URL) throws -> [String: ConfigurationValue] {
    var result = document
    if let widgets = result["widgets"] {
        result["widgets"] = .array(try widgets.decoded([[String: ConfigurationValue]].self).map {
            .object(packageEnvironment($0, directory: directory))
        })
    }
    for key in ["templates", "providers"] {
        if let definitions = result[key] {
            result[key] = .object(try definitions.decoded([String: [String: ConfigurationValue]].self).mapValues {
                .object(packageEnvironment($0, directory: directory))
            })
        }
    }
    if let profiles = result["profiles"] {
        result["profiles"] = .array(try profiles.decoded([[String: ConfigurationValue]].self).map { profile in
            var profile = profile
            let configuration = try (profile["configuration"] ?? .null).decoded([String: ConfigurationValue].self)
            profile["configuration"] = .object(try preparePackageDocument(configuration, directory: directory))
            return .object(profile)
        })
    }
    return result
}

func validateThemeDocument(_ document: [String: ConfigurationValue]) throws {
    for key in document.keys.sorted() where !["tokens", "defaults", "bar", "groups", "profiles"].contains(key) {
        guard key == "widgets", document[key] == .array([]) else { throw WidgetPackageError.themeProperty(key) }
    }
    for profile in try document["profiles"]?.decoded([ConfigurationProfile].self) ?? [] {
        try validateThemeDocument(profile.configuration)
    }
}

func validateWidgetsDocument(_ document: [String: ConfigurationValue]) throws {
    for key in document.keys.sorted() where !["tokens", "defaults", "bar", "groups", "profiles", "widgets", "templates", "popups", "providers"].contains(key) {
        throw WidgetPackageError.widgetsProperty(key)
    }
    for profile in try document["profiles"]?.decoded([ConfigurationProfile].self) ?? [] {
        try validateWidgetsDocument(profile.configuration)
    }
    try rejectCommandKeys(.object(document))
}

private func rejectCommandKeys(_ value: ConfigurationValue) throws {
    switch value {
    case let .object(object):
        for key in object.keys.sorted() {
            guard !(commandKeys + ["onClickField", "environment"]).contains(key) else { throw WidgetPackageError.widgetsCommand(key) }
            try rejectCommandKeys(object[key]!)
        }
    case let .array(array): try array.forEach(rejectCommandKeys)
    default: break
    }
}

private func packageEnvironment(_ definition: [String: ConfigurationValue], directory: URL) -> [String: ConfigurationValue] {
    var result = definition
    result["environment"] = .object(["PACKAGE_DIR": .string(directory.path)]).overriding(result["environment"] ?? .object([:]))
    return result
}

func preparePackageAssets(_ value: ConfigurationValue, path: String = "", origins: [String: ConfigurationOrigin],
                          sources: [String: URL]) throws -> ConfigurationValue {
    switch value {
    case let .object(object):
        var result: [String: ConfigurationValue] = [:]
        for (key, child) in object {
            result[key] = try preparePackageAssets(child, path: path.isEmpty ? key : "\(path).\(key)",
                                                  origins: origins, sources: sources)
        }
        if object["type"] == .string("image"), case let .string(file) = object["path"],
           let source = origins["\(path).path"]?.file, let directory = sources[source] {
            result["path"] = .string(try packageFile(file, inside: directory).path)
        }
        return .object(result)
    case let .array(array):
        return .array(try array.enumerated().map { index, child in
            var key = String(index)
            if path == "widgets", case let .object(widget) = child, case let .string(id) = widget["id"] { key = id }
            return try preparePackageAssets(child, path: "\(path).\(key)", origins: origins, sources: sources)
        })
    default: return value
    }
}

private let commandKeys = ["command", "onClick", "rightClick", "middleClick", "scrollUp", "scrollDown", "mouseEntered", "mouseExited", "onChange"]

private func packageCommands(_ value: ConfigurationValue) -> [String] {
    switch value {
    case let .object(object):
        return object.keys.sorted().flatMap { key in
            let value = object[key]!
            if commandKeys.contains(key),
               case let .string(command) = value { return [command] }
            return packageCommands(value)
        }
    case let .array(array): return array.flatMap(packageCommands)
    default: return []
    }
}

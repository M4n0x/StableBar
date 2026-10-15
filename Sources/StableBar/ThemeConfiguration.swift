import Foundation

struct ConfigurationContext: Sendable, Equatable {
    var appearance = "light"
    var onBattery = false
    var displayCount = 1
    var externalDisplay = false
    var app = ""
}

struct ConfigurationProfile: Decodable {
    let name: String
    let when: ProfileConditions?
    let configuration: [String: ConfigurationValue]
}

struct ProfileConditions: Decodable {
    let appearance: String?
    let onBattery: Bool?
    let displayCount: Int?
    let externalDisplay: Bool?
    let app: String?

    func matches(_ context: ConfigurationContext) -> Bool {
        (appearance == nil || appearance == context.appearance)
            && (onBattery == nil || onBattery == context.onBattery)
            && (displayCount == nil || displayCount == context.displayCount)
            && (externalDisplay == nil || externalDisplay == context.externalDisplay)
            && (app == nil || app == context.app)
    }
}

enum ThemeConfigurationError: LocalizedError {
    case unknownReference(String)
    case referenceCycle([String])
    case unknownProfile(String)
    case duplicateProfile(String)

    var errorDescription: String? {
        switch self {
        case let .unknownReference(name): "Unknown configuration reference: \(name)."
        case let .referenceCycle(names): "Configuration reference cycle: \(names.joined(separator: " → "))."
        case let .unknownProfile(name): "Unknown configuration profile: \(name)."
        case let .duplicateProfile(name): "Duplicate configuration profile: \(name)."
        }
    }
}

func substituteConfigurationReferences(_ value: ConfigurationValue, prefix: String,
                                       values: [String: ConfigurationValue],
                                       path: [String] = []) throws -> ConfigurationValue {
    switch value {
    case let .string(string) where string.hasPrefix(prefix):
        let name = String(string.dropFirst(prefix.count))
        guard !path.contains(name) else {
            throw ThemeConfigurationError.referenceCycle(path + [name])
        }
        guard let replacement = values[name] else {
            throw ThemeConfigurationError.unknownReference(string)
        }
        return try substituteConfigurationReferences(replacement, prefix: prefix, values: values, path: path + [name])
    case let .object(object):
        return .object(try object.mapValues {
            try substituteConfigurationReferences($0, prefix: prefix, values: values, path: path)
        })
    case let .array(array):
        return .array(try array.map {
            try substituteConfigurationReferences($0, prefix: prefix, values: values, path: path)
        })
    default:
        return value
    }
}

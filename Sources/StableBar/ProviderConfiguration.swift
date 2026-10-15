import Foundation

enum ProviderType: String, Decodable, Sendable {
    case command, stream, battery, network, system, audio

    var isNative: Bool { self != .command && self != .stream }
}

struct ProviderConfiguration: Decodable, Equatable, Sendable {
    let type: ProviderType
    let command: String?
    let interval: Double
    let timeout: Double
    let environment: [String: String]
    let whenVisible: Bool
    let events: [String]

    enum CodingKeys: String, CodingKey { case type, command, interval, timeout, environment, whenVisible, events }

    init(type: ProviderType) {
        self.type = type
        command = nil
        interval = 5
        timeout = 10
        environment = [:]
        whenVisible = false
        events = []
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(ProviderType.self, forKey: .type)
        switch type {
        case .command, .stream: command = try values.decode(String.self, forKey: .command)
        default: command = nil
        }
        interval = try values.decodeIfPresent(Double.self, forKey: .interval) ?? 5
        timeout = try values.decodeIfPresent(Double.self, forKey: .timeout) ?? 10
        environment = try values.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        whenVisible = try values.decodeIfPresent(Bool.self, forKey: .whenVisible) ?? false
        events = try values.decodeIfPresent([String].self, forKey: .events) ?? []
        guard interval > 0, interval.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .interval, in: values,
                                                  debugDescription: "A provider interval must be greater than zero and finite.")
        }
        guard timeout > 0, timeout.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .timeout, in: values,
                                                  debugDescription: "A provider timeout must be greater than zero and finite.")
        }
    }
}

struct ScriptDiagnostics: Codable, Sendable {
    var running = false
    var suspended = false
    var lastEvent: String?
    var lastStarted: Date?
    var lastUpdated: Date?
    var lastDuration: Double?
    var lastStdout = ""
    var lastStderr = ""
    var executionCount = 0
    var failureCount = 0
    var restartCount = 0
    var consecutiveFailures = 0
    var nextDelay: Double?
    var cpuTime = 0.0
}

func providerRetryDelay(interval: Double, failures: Int) -> Double {
    max(interval, min(300, max(1, interval) * pow(2, Double(min(failures - 1, 9)))))
}

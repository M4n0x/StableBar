import EventKit
import Foundation

/// A kind of data source that providers name in `type`: the settings it reads, how StableBar runs
/// it and the events it sends. Adding a source means adding one entry to `DataSourceRegistry.builtIn`.
struct DataSourceType: Sendable {
    /// The `type` name in provider definitions, such as `battery`.
    var name: String
    /// Whether a widget can name this type directly, sharing a default provider of that name.
    /// `command` and `stream` need a `command`, so widgets reach them through `providers`.
    var isNative: Bool
    /// The SF Symbol the editor shows for widgets of this type.
    var symbol: String
    /// Provider properties this type requires besides the ones every provider has: `type`,
    /// `interval`, `timeout`, `environment`, `whenVisible` and `events`.
    var settings: [ProviderConfiguration.CodingKeys]
    /// Provider properties this type reads when they are set and otherwise gives a default, such as
    /// calendar's `lookahead`. The decoder accepts them on every type; other types ignore them.
    var optionalSettings: [ProviderConfiguration.CodingKeys] = []
    /// Whether runs stay open and the source sends updates as they happen, like a stream or a native
    /// listener; otherwise the runner refreshes it every `interval`.
    var continuous: Bool
    /// The built-in events this source sends when its output changes.
    var events: [BuiltInEvent] = []
    /// A notification macOS posts when the data changes between the runner's refreshes, such as
    /// calendar's `EKEventStoreChanged`. While the source runs, the runner also refreshes it each
    /// time it's posted, with an event named after the type.
    var changeNotification: Notification.Name? = nil
    /// Creates the source for one provider definition, with the provider's environment.
    var makeSource: @MainActor @Sendable (ProviderConfiguration, [String: String]) -> any DataSource
}

struct DataSourceRegistry: Sendable {
    let types: [DataSourceType]

    subscript(name: String) -> DataSourceType? {
        types.first { $0.name == name }
    }

    static let builtIn = DataSourceRegistry(types: [.command, .stream, .battery, .system, .network, .audio, .calendar])
}

extension DataSourceType {
    static let command = DataSourceType(name: "command", isNative: false, symbol: "terminal", settings: [.command],
                                        continuous: false) { provider, environment in
        PollingSource.command(provider.command!, timeout: provider.timeout, environment: environment)
    }

    static let stream = DataSourceType(name: "stream", isNative: false, symbol: "terminal", settings: [.command],
                                       continuous: true) { provider, environment in
        StreamSource(command: provider.command!, environment: environment)
    }

    static let battery = DataSourceType(name: "battery", isNative: true, symbol: "battery.100percent", settings: [], continuous: true) { _, _ in
        PushSource(monitor: PowerMonitor())
    }

    static let system = DataSourceType(name: "system", isNative: true, symbol: "cpu", settings: [], continuous: false) { _, _ in
        let metrics = NativeMetrics()
        return PollingSource { _ in .output(Result { try metrics.system() }) }
    }

    static let network = DataSourceType(name: "network", isNative: true, symbol: "network", settings: [], continuous: false) { _, _ in
        let metrics = NativeMetrics()
        return PollingSource { _ in .output(Result { try metrics.networkRates() }) }
    }

    static let audio = DataSourceType(name: "audio", isNative: true, symbol: "speaker.wave.2", settings: [], continuous: false) { _, _ in
        let metrics = NativeMetrics()
        return PollingSource { _ in .output(Result { try metrics.audio() }) }
    }

    /// Its output sets its own `interval`, so the runner reads it again at the next minute or phase
    /// boundary.
    static let calendar = DataSourceType(name: "calendar", isNative: true, symbol: "calendar", settings: [],
                                         optionalSettings: [.calendars, .lookahead, .soon, .now], continuous: false,
                                         changeNotification: .EKEventStoreChanged) { provider, _ in
        let metrics = NativeMetrics()
        return PollingSource { _ in .output(.success(metrics.calendar(provider))) }
    }
}

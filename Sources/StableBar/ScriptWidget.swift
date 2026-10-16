import Foundation
import Observation

struct ScriptEvent: Sendable {
    var sender: String
    var environment: [String: String] = [:]

    func commandEnvironment(_ configured: [String: String], secret: @Sendable (String) -> String = packageSecret) async -> [String: String] {
        var variables = configured.mapValues { $0.hasPrefix("@secret.") ? secret(String($0.dropFirst("@secret.".count))) : $0 }
            .merging(environment) { _, event in event }
        variables["NAME"] = configured["NAME"]
        variables["CONFIG_DIR"] = configured["CONFIG_DIR"]
        variables["SENDER"] = sender
        return variables
    }
}

struct WidgetMenuItem: Decodable, Equatable, Sendable {
    let title: String
    var detail: String?
    var onClick: String?

    enum CodingKeys: String, CodingKey, CaseIterable { case title, detail, onClick }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        detail = try values.decodeIfPresent(String.self, forKey: .detail)
        onClick = try values.decodeIfPresent(String.self, forKey: .onClick)
    }
}

struct ScriptOutput: Decodable, Equatable, Sendable {
    var text: String
    var icon: String?
    var color: HexColor?
    var tooltip: String?
    var hidden: Bool?
    var menu: [WidgetMenuItem]?
    var value: Double?
    var fields: [String: String]?
    var lists: [String: [[String: String]]]?
    var values: [String: Double]?
    var targets: [String: Double]?
    var style: WidgetStyle?
    var styles: [String: WidgetStyle]?
    var barStyle: WidgetStyle?
    var animation: WidgetAnimation?
    var display: DisplaySelection?
    var series: [String: [Double]]?
    var onClick: String?
    var widgetStyles: [String: WidgetStyle]?
    var interval: Double?
    /// The widget's data state. Earlier versions ignored this field, so any JSON value decodes;
    /// `dataState(_:rules:)` uses only a string.
    var state: ConfigurationValue?
    /// Fields shown over this output's own for a while, such as the volume after a change.
    var temporary: TemporaryOutput?

    static func read(_ data: Data) throws -> ScriptOutput {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") {
            var output = try JSONDecoder().decode(ScriptOutput.self, from: data)
            output.series = output.series?.mapValues { Array($0.suffix(60)) }
            return output
        }
        return ScriptOutput(text: text)
    }
}

/// Fields an output shows over its own for `duration` seconds before the widget returns to it.
struct TemporaryOutput: Decodable, Equatable, Sendable {
    let fields: [String: String]
    let duration: Double

    static let longestDuration = 86_400.0

    enum CodingKeys: String, CodingKey, CaseIterable { case fields, duration }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fields = try values.decode([String: String].self, forKey: .fields)
        duration = try values.decode(Double.self, forKey: .duration)
        guard duration > 0, duration <= Self.longestDuration else {
            throw DecodingError.dataCorruptedError(forKey: .duration, in: values,
                                                   debugDescription: "A temporary duration must be greater than zero and at most one day (86400 seconds).")
        }
    }
}

@MainActor @Observable
final class ScriptWidget {
    var output = ScriptOutput(text: "…")
    var error: String?
    var samples: [Double] = []
    var diagnostics = ScriptDiagnostics()
    /// Called when the output or the error changes, so the store can re-resolve the styles it affects,
    /// and for each output with a `temporary`, which the store shows again after it ran out.
    @ObservationIgnored var onUpdate: (() -> Void)?
    /// Numbers each accepted output, unique across scripts, so the store can tell a new output from
    /// one it applies again. 0 before the first.
    @ObservationIgnored private(set) var outputNumber = 0
    private static var acceptedOutputs = 0
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var events: AsyncStream<ScriptEvent>.Continuation?
    private var makeSource: (@MainActor () -> any DataSource)?
    private var source: (any DataSource)?
    private var schedule = SourceSchedule()

    func start(command: String, interval: Double?, timeout: Double = 10, environment: [String: String] = [:]) {
        start(schedule: SourceSchedule(interval: interval)) {
            PollingSource.command(command, timeout: timeout, environment: environment)
        }
    }

    func start(provider: ProviderConfiguration, environment: [String: String] = [:]) {
        var variables = environment.merging(provider.environment) { _, value in value }
        variables["NAME"] = environment["NAME"]
        variables["CONFIG_DIR"] = environment["CONFIG_DIR"]
        start(schedule: SourceSchedule(interval: provider.interval, continuous: provider.type == .stream)) {
            switch provider.type {
            case .command: return PollingSource.command(provider.command!, timeout: provider.timeout, environment: variables)
            case .stream: return StreamSource(command: provider.command!, environment: variables)
            default:
                let metrics = NativeMetrics()
                return PollingSource { _ in .output(Result { try metrics.sample(provider) }) }
            }
        }
    }

    /// Runs the source that `makeSource` creates. A fresh instance runs at startup, on resume and
    /// when a refresh restarts a continuous source.
    func start(schedule: SourceSchedule, source makeSource: @escaping @MainActor () -> any DataSource) {
        stop()
        self.schedule = schedule
        self.makeSource = makeSource
        begin(ScriptEvent(sender: "startup"))
    }

    private func begin(_ firstEvent: ScriptEvent) {
        guard let makeSource else { return }
        let source = makeSource()
        let schedule = schedule
        self.source = source
        diagnostics.suspended = false
        let (stream, events) = AsyncStream<ScriptEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.events = events
        events.yield(firstEvent)
        task = Task {
            for await event in stream {
                if Task.isCancelled { return }
                timer?.cancel()
                diagnostics.running = true
                diagnostics.nextDelay = nil
                diagnostics.lastEvent = event.sender
                diagnostics.lastStarted = Date()
                diagnostics.executionCount += 1
                let started = ContinuousClock.now
                var delay = schedule.interval
                // The single-slot queue: while an update is being applied, only the newest waits.
                let (updates, queue) = AsyncStream<SourceUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
                source.start { update in
                    if case .finished = update { queue.finish() } else { queue.yield(update) }
                }
                source.refresh(event: event)
                do {
                    for await update in updates {
                        try Task.checkCancellation()
                        guard case let .output(result, process) = update else { continue }
                        if let process { record(process) }
                        try accept(result.get())
                        if schedule.continuous, started.duration(to: .now) >= .seconds(10) { diagnostics.consecutiveFailures = 0 }
                    }
                    try Task.checkCancellation()
                    diagnostics.consecutiveFailures = 0
                    if delay != nil { delay = output.interval ?? delay }
                } catch {
                    if Task.isCancelled { return }
                    let message = error.localizedDescription
                    if self.error != message {
                        self.error = message
                        onUpdate?()
                    }
                    diagnostics.failureCount += 1
                    diagnostics.consecutiveFailures += 1
                    if let failure = error as? CommandFailure {
                        if !failure.stdout.isEmpty { diagnostics.lastStdout = String(decoding: failure.stdout.suffix(16_384), as: UTF8.self) }
                        if !failure.stderr.isEmpty { diagnostics.lastStderr = String(decoding: failure.stderr.suffix(16_384), as: UTF8.self) }
                    }
                    if let interval = delay {
                        delay = providerRetryDelay(interval: interval, failures: diagnostics.consecutiveFailures)
                    }
                }
                source.stop()
                let duration = started.duration(to: .now).components
                diagnostics.lastDuration = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                diagnostics.running = false
                diagnostics.nextDelay = delay
                if let delay {
                    timer = Task {
                        do {
                            try await Task.sleep(for: .seconds(delay))
                            try Task.checkCancellation()
                            if schedule.continuous { diagnostics.restartCount += 1 }
                            events.yield(ScriptEvent(sender: "routine"))
                        } catch {}
                    }
                }
            }
        }
    }

    private func record(_ result: CommandResult) {
        diagnostics.lastStdout = String(decoding: result.stdout.suffix(16_384), as: UTF8.self)
        diagnostics.lastStderr = String(decoding: result.stderr.suffix(16_384), as: UTF8.self)
        diagnostics.cpuTime += result.cpuTime
    }

    /// Applies a source's new output. Only what changed is assigned, so an update that repeats the
    /// current output invalidates no views; its `value` still adds a graph sample, and its `temporary`
    /// still reaches the store, so it can show again after it ran out.
    func accept(_ next: ScriptOutput) throws {
        if let interval = next.interval, !interval.isFinite || interval <= 0 {
            throw CommandFailure(message: "A script interval must be greater than zero.")
        }
        var next = next
        next.series = next.series?.mapValues { Array($0.suffix(60)) }
        let outputChanged = next != output
        let changed = outputChanged || error != nil
        if outputChanged { output = next }
        if let value = next.value {
            let history = Array((samples + [value]).suffix(60))
            if history != samples { samples = history }
        }
        if error != nil { error = nil }
        diagnostics.lastUpdated = Date()
        Self.acceptedOutputs += 1
        outputNumber = Self.acceptedOutputs
        if changed || next.temporary != nil { onUpdate?() }
    }

    func refresh(_ event: ScriptEvent) {
        if makeSource == nil || diagnostics.suspended { return }
        if schedule.continuous {
            cancel()
            diagnostics.restartCount += 1
            begin(event)
        } else {
            timer?.cancel()
            events?.yield(event)
        }
    }

    func suspend() {
        if makeSource == nil || diagnostics.suspended { return }
        cancel()
        diagnostics.suspended = true
    }

    func resume() {
        if !diagnostics.suspended { return }
        begin(ScriptEvent(sender: "resume"))
    }

    private func cancel() {
        task?.cancel()
        timer?.cancel()
        events?.finish()
        source?.stop()
        task = nil
        timer = nil
        events = nil
        source = nil
        diagnostics.running = false
        diagnostics.nextDelay = nil
    }

    func stop() {
        cancel()
        makeSource = nil
        diagnostics.suspended = false
    }
}

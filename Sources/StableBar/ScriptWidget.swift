import Foundation
import Observation

struct ScriptEvent: Sendable {
    var sender: String
    var environment: [String: String] = [:]

    func commandEnvironment(_ configured: [String: String]) -> [String: String] {
        var variables = configured.merging(environment) { _, event in event }
        variables["NAME"] = configured["NAME"]
        variables["CONFIG_DIR"] = configured["CONFIG_DIR"]
        variables["SENDER"] = sender
        return variables
    }
}

struct WidgetMenuItem: Decodable, Sendable {
    let title: String
    var detail: String?
    var onClick: String?
}

struct ScriptOutput: Decodable, Sendable {
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

@MainActor @Observable
final class ScriptWidget {
    var output = ScriptOutput(text: "…")
    var error: String?
    var samples: [Double] = []
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var events: AsyncStream<ScriptEvent>.Continuation?

    func start(command: String, interval: Double?, timeout: Double = 10, environment: [String: String] = [:]) {
        stop()
        let (stream, events) = AsyncStream<ScriptEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.events = events
        events.yield(ScriptEvent(sender: "startup"))
        task = Task {
            for await event in stream {
                timer?.cancel()
                var delay = interval
                do {
                    let data = try await runCommand("/bin/zsh", arguments: ["-lc", command],
                                                    timeout: timeout, environment: event.commandEnvironment(environment))
                    try Task.checkCancellation()
                    let next = try ScriptOutput.read(data)
                    if let interval = next.interval, !interval.isFinite || interval <= 0 {
                        throw CommandFailure(message: "A script interval must be greater than zero.")
                    }
                    output = next
                    if let value = output.value {
                        samples.append(value)
                        if samples.count > 60 { samples.removeFirst() }
                    }
                    error = nil
                    if interval != nil { delay = next.interval ?? interval }
                } catch {
                    if Task.isCancelled { return }
                    self.error = error.localizedDescription
                }
                if let delay {
                    timer = Task {
                        do {
                            try await Task.sleep(for: .seconds(delay))
                            try Task.checkCancellation()
                            events.yield(ScriptEvent(sender: "routine"))
                        } catch {}
                    }
                }
            }
        }
    }

    func refresh(_ event: ScriptEvent) {
        timer?.cancel()
        events?.yield(event)
    }

    func stop() {
        task?.cancel()
        timer?.cancel()
        events?.finish()
        events = nil
    }
}

import Foundation
import Observation

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
            return try JSONDecoder().decode(ScriptOutput.self, from: data)
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

    func start(command: String, interval: Double) {
        task = Task {
            while !Task.isCancelled {
                do {
                    let data = try await runCommand("/bin/zsh", arguments: ["-lc", command])
                    try Task.checkCancellation()
                    let next = try ScriptOutput.read(data)
                    if let interval = next.interval, interval <= 0 {
                        throw CommandFailure(message: "A script interval must be greater than zero.")
                    }
                    output = next
                    if let value = output.value {
                        samples.append(value)
                        if samples.count > 60 { samples.removeFirst() }
                    }
                    error = nil
                } catch {
                    if Task.isCancelled { return }
                    self.error = error.localizedDescription
                }
                do {
                    try await Task.sleep(for: .seconds(output.interval ?? interval))
                } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
    }
}

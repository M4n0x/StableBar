import Foundation

/// Where a widget's output comes from: a command, a stream, a native reading or a native listener.
/// The runner (`ScriptWidget`) drives each run: it calls `start(emit:)`, then `refresh(event:)` with
/// the event that began the run, and `stop()` when the run ends, the widget suspends or it stops.
@MainActor
protocol DataSource: AnyObject {
    /// Connects the source for one run. `emit` hands updates to the runner's single-slot queue and
    /// may be called from any thread: while the runner applies one update, only the newest waits.
    func start(emit: @escaping @Sendable (SourceUpdate) -> Void)
    /// Produces output for `event`: runs a command, reads native data, or launches a stream.
    func refresh(event: ScriptEvent)
    /// Ends the run: cancels work, ends processes and removes listeners. Later updates are ignored,
    /// and stopping a source that has already stopped does nothing.
    func stop()
}

/// What a data source reports to its runner.
enum SourceUpdate: Sendable {
    /// New output, or the reason there is none, with the process output behind it for diagnostics.
    case output(Result<ScriptOutput, any Error>, process: CommandResult? = nil)
    /// The run's work is done, such as a finished command. Sources that stay open never send it.
    case finished
}

/// How the runner paces a source.
struct SourceSchedule: Equatable, Sendable {
    /// Seconds between runs, or for a continuous source the first retry delay after a failure.
    /// `nil` runs only on events.
    var interval: Double?
    /// Runs stay open and the source sends updates as they happen, like a stream or a native
    /// listener. A refresh restarts the run.
    var continuous = false
}

/// Adapts a one-shot reading, such as a command or CPU usage, to a source: each refresh reads once
/// and finishes. The runner refreshes it every `interval`.
@MainActor
final class PollingSource: DataSource {
    private let read: @MainActor (ScriptEvent) async -> SourceUpdate
    private var emit: (@Sendable (SourceUpdate) -> Void)?
    private var task: Task<Void, Never>?

    init(read: @escaping @MainActor (ScriptEvent) async -> SourceUpdate) {
        self.read = read
    }

    func start(emit: @escaping @Sendable (SourceUpdate) -> Void) {
        self.emit = emit
    }

    func refresh(event: ScriptEvent) {
        task?.cancel()
        task = Task { [read, emit] in
            let update = await read(event)
            if Task.isCancelled { return }
            emit?(update)
            emit?(.finished)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        emit = nil
    }
}

extension PollingSource {
    /// A shell command run once per refresh, for script widgets and `command` providers.
    static func command(_ command: String, timeout: Double, environment: [String: String]) -> PollingSource {
        PollingSource { event in
            do {
                let result = try await runCommandResult("/bin/zsh", arguments: ["-c", command], timeout: timeout,
                                                        environment: event.commandEnvironment(environment))
                return .output(Result { try ScriptOutput.read(result.stdout) }, process: result)
            } catch {
                return .output(.failure(error))
            }
        }
    }
}

/// A command that prints one JSON object per line for as long as it runs. Malformed output and
/// exits end the run, and the runner restarts it with backoff.
@MainActor
final class StreamSource: DataSource {
    private let command: String
    private let environment: [String: String]
    private var emit: (@Sendable (SourceUpdate) -> Void)?
    private var task: Task<Void, Never>?

    init(command: String, environment: [String: String]) {
        self.command = command
        self.environment = environment
    }

    func start(emit: @escaping @Sendable (SourceUpdate) -> Void) {
        self.emit = emit
    }

    func refresh(event: ScriptEvent) {
        task?.cancel()
        task = Task { [command, environment, emit] in
            do {
                for try await line in await commandLines("/bin/zsh", arguments: ["-c", command],
                                                         environment: event.commandEnvironment(environment)) {
                    let output = Result { try JSONDecoder().decode(ScriptOutput.self, from: line.stdout) }
                    emit?(.output(output, process: line))
                    if case .failure = output { return }
                }
                if Task.isCancelled { return }
                emit?(.output(.failure(CommandFailure(message: "Streaming provider exited."))))
            } catch {
                if Task.isCancelled { return }
                emit?(.output(.failure(error)))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        emit = nil
    }
}

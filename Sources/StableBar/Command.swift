import Darwin
import Foundation

struct CommandFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func runCommand(_ executable: String, arguments: [String], timeout: Double = 10,
                environment: [String: String] = [:]) async throws -> Data {
    let command = CommandProcess()
    let data = try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            command.start(executable, arguments: arguments, timeout: timeout, environment: environment,
                          continuation: continuation)
        }
    } onCancel: {
        command.cancel()
    }
    try Task.checkCancellation()
    return data
}

private final class CommandProcess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "StableBar.Command")
    private var continuation: CheckedContinuation<Data, Error>?
    private var processGroup: pid_t = 0
    private var processSource: DispatchSourceProcess?
    private var outputSources: [DispatchSourceRead] = []
    private var timer: DispatchSourceTimer?
    private var stdout = Data()
    private var stderr = Data()
    private var closedStreams = 0
    private var exitStatus: Int32?
    private var failure: Error?

    func start(_ executable: String, arguments: [String], timeout: Double, environment: [String: String],
               continuation: CheckedContinuation<Data, Error>) {
        queue.async { [self] in
            self.continuation = continuation
            if let failure {
                self.continuation = nil
                continuation.resume(throwing: failure)
                return
            }
            let output = Pipe()
            let errors = Pipe()
            let pipes = [output, errors]
            var actions: posix_spawn_file_actions_t?
            var attributes: posix_spawnattr_t?
            posix_spawn_file_actions_init(&actions)
            posix_spawnattr_init(&attributes)
            defer {
                posix_spawn_file_actions_destroy(&actions)
                posix_spawnattr_destroy(&attributes)
            }
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT |
                                                       POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
            posix_spawnattr_setpgroup(&attributes, 0)
            var signals = sigset_t()
            sigemptyset(&signals)
            posix_spawnattr_setsigmask(&attributes, &signals)
            sigfillset(&signals)
            posix_spawnattr_setsigdefault(&attributes, &signals)
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            posix_spawn_file_actions_adddup2(&actions, errors.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            var variables = ProcessInfo.processInfo.environment
            variables["STABLEBAR_SCRIPTS"] = Bundle.main.resourceURL!.appending(path: "widgets").path
            variables.merge(environment) { _, value in value }
            var argv = ([executable] + arguments).map { strdup($0) } + [nil]
            var envp = variables.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }
            let result = posix_spawn(&processGroup, executable, &actions, &attributes, &argv, &envp)
            for pipe in pipes { pipe.fileHandleForWriting.closeFile() }
            guard result == 0 else {
                for pipe in pipes { pipe.fileHandleForReading.closeFile() }
                processGroup = 0
                self.continuation = nil
                continuation.resume(throwing: CommandFailure(message: String(cString: strerror(result))))
                return
            }
            for (index, pipe) in pipes.enumerated() {
                let handle = pipe.fileHandleForReading
                let source = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor, queue: queue)
                source.setEventHandler { [self] in
                    var buffer = [UInt8](repeating: 0, count: 8192)
                    let count = read(handle.fileDescriptor, &buffer, buffer.count)
                    if count == -1 && errno == EINTR { return }
                    if count == -1 {
                        terminate(CommandFailure(message: String(cString: strerror(errno))))
                        return
                    }
                    if count == 0 {
                        outputSources[index].cancel()
                        closedStreams += 1
                        finish()
                    } else if failure == nil {
                        let size = index == 0 ? stdout.count : stderr.count
                        if size + count > 1_048_576 {
                            terminate(CommandFailure(message: "Command output exceeded 1 MiB."))
                        } else if index == 0 {
                            stdout.append(buffer, count: count)
                        } else {
                            stderr.append(buffer, count: count)
                        }
                    }
                }
                source.setCancelHandler { handle.closeFile() }
                outputSources.append(source)
                source.resume()
            }
            let process = DispatchSource.makeProcessSource(identifier: processGroup, eventMask: .exit, queue: queue)
            process.setEventHandler { [self] in
                var status: Int32 = 0
                while waitpid(processGroup, &status, 0) == -1 && errno == EINTR {}
                exitStatus = status
                processSource!.cancel()
                finish()
            }
            processSource = process
            process.resume()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { [self] in
                terminate(CommandFailure(message: "Command timed out after \(timeout) seconds."))
            }
            self.timer = timer
            timer.resume()
        }
    }

    func cancel() {
        queue.sync { terminate(CancellationError()) }
    }

    private func terminate(_ error: Error) {
        if failure == nil { failure = error }
        if processGroup != 0 {
            kill(-processGroup, SIGKILL)
            if exitStatus == nil { kill(processGroup, SIGKILL) }
            for source in outputSources { source.cancel() }
            closedStreams = 2
            finish()
        }
    }

    private func finish() {
        guard let exitStatus, closedStreams == 2 else { return }
        let continuation = continuation!
        self.continuation = nil
        processGroup = 0
        timer!.cancel()
        timer = nil
        processSource = nil
        outputSources.removeAll()
        if let failure {
            continuation.resume(throwing: failure)
        } else if exitStatus != 0 {
            let message = String(decoding: stderr.isEmpty ? stdout : stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = exitStatus & 0x7f == 0
                ? "Command exited with status \(exitStatus >> 8)."
                : "Command terminated by signal \(exitStatus & 0x7f)."
            continuation.resume(throwing: CommandFailure(message: message.isEmpty ? status : message))
        } else {
            continuation.resume(returning: stdout)
        }
    }
}

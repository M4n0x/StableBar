import Foundation

enum LaunchCommand {
    case run(URL)
    case trigger(String, [String: String])
    case reload
    case validate(URL)
    case help

    static let configurationURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/stablebar/config.json")
    static let reloadNotification = Notification.Name("com.stablebar.reload")
    static let usage = """
    Usage: StableBar [--config PATH]
           StableBar --validate [PATH]
           StableBar --trigger EVENT [KEY=VALUE ...]
           StableBar --reload
           StableBar --help
    """

    init(arguments: [String]) throws {
        switch arguments.first {
        case nil:
            self = .run(Self.configurationURL)
        case "--config" where arguments.count == 2:
            self = .run(URL(filePath: (arguments[1] as NSString).expandingTildeInPath))
        case "--validate" where arguments.count <= 2:
            let url = arguments.count == 2 ? URL(filePath: (arguments[1] as NSString).expandingTildeInPath) : Self.configurationURL
            self = .validate(url)
        case "--trigger" where arguments.count >= 2:
            guard !arguments[1].isEmpty else { throw CommandFailure(message: "An event name is required.") }
            var environment: [String: String] = [:]
            for argument in arguments.dropFirst(2) {
                let pair = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2, pair[0].range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                    throw CommandFailure(message: "Event data must use KEY=VALUE: \(argument)")
                }
                environment[String(pair[0])] = String(pair[1])
            }
            self = .trigger(arguments[1], environment)
        case "--reload" where arguments.count == 1:
            self = .reload
        case "--help" where arguments.count == 1:
            self = .help
        default:
            throw CommandFailure(message: Self.usage)
        }
    }
}

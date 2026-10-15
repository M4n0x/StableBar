import AppKit
import Observation

@MainActor @Observable
final class BarStore: NSObject {
    var configuration: Configuration?
    var configurationError: String?
    var actionError: String?
    var activeApp = NSWorkspace.shared.frontmostApplication
    var activeDisplayID = 1
    var scripts: [String: ScriptWidget] = [:]
    let aerospace = AeroSpace()
    let popup = WidgetPopup()
    let configurationURL: URL
    var onConfigurationChange: (() -> Void)?
    private var configurationLoader = ConfigurationLoader()
    private let configurationWatcher = ConfigurationWatcher()
    private var reloadTask: Task<Void, Never>?
    private var eventObservers: [NSObjectProtocol] = []
    private var reloadObserver: NSObjectProtocol?
    private var actions: [UUID: Task<Void, Never>] = [:]
    private var actionTails: [String: (id: UUID, task: Task<Void, Never>)] = [:]

    init(configurationURL: URL = LaunchCommand.configurationURL) {
        self.configurationURL = configurationURL
        super.init()
        configurationWatcher.onChange = { [weak self] in self?.scheduleReload() }
    }

    func start() {
        reloadObserver = DistributedNotificationCenter.default().addObserver(
            forName: LaunchCommand.reloadNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadConfiguration() }
            }
        aerospace.onWorkspaceChange = { [weak self] in
            guard let self else { return }
            popup.close()
            let focused = aerospace.workspaces.first(where: \.isFocused)
            refreshScripts(for: "workspace", environment: ["INFO": focused?.name ?? "", "SID": String(focused?.monitor ?? activeDisplayID)])
        }
        do {
            let directory = configurationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configurationURL.path) {
                let template = Bundle.main.url(forResource: "config", withExtension: "json")!
                let data = try SetupPreferences(placement: .belowMenuBar).applying(
                    to: Data(contentsOf: template),
                    menuBarHeight: max(NSStatusBar.system.thickness, NSScreen.main?.safeAreaInsets.top ?? 0))
                try data.write(to: configurationURL, options: .atomic)
            }
            reloadConfiguration()
        } catch {
            configurationError = error.localizedDescription
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(updateActiveApp), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func updateActiveApp() {
        activeApp = NSWorkspace.shared.frontmostApplication
        if let screen = NSScreen.main { activeDisplayID = BarDisplay(screen: screen).id }
        popup.close()
        refreshScripts(for: "frontApp", environment: ["INFO": activeApp?.localizedName ?? "Desktop"])
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                reloadConfiguration()
            } catch {}
        }
    }

    func reloadConfiguration() {
        defer { configurationWatcher.watch(configurationLoader.dependencies) }
        do {
            let next = try configurationLoader.load(configurationURL)
            popup.close()
            let previous = configuration?.widgets ?? []
            for (id, script) in scripts {
                let old = previous.first { $0.id == id }
                let new = next.widgets.first { $0.id == id && $0.enabled }
                if old?.content != new?.content || old?.timeout != new?.timeout
                    || old?.environment != new?.environment || configuration?.environment != next.environment {
                    script.stop()
                    scripts.removeValue(forKey: id)
                }
            }
            for widget in next.widgets where widget.enabled {
                if case let .script(command, interval) = widget.content, scripts[widget.id] == nil {
                    let script = ScriptWidget()
                    scripts[widget.id] = script
                    script.start(command: command, interval: interval, timeout: widget.timeout,
                                 environment: commandEnvironment(widget, configuration: next))
                }
            }
            let needsAeroSpace = next.widgets.contains { $0.enabled && ($0.content == .workspaces || $0.display == .active) }
            let hadAeroSpace = previous.contains { $0.enabled && ($0.content == .workspaces || $0.display == .active) }
            if needsAeroSpace && !hadAeroSpace { aerospace.start() }
            if !needsAeroSpace && hadAeroSpace { aerospace.stop() }
            configuration = next
            configurationError = nil
            let center = DistributedNotificationCenter.default()
            for observer in eventObservers { center.removeObserver(observer) }
            eventObservers = Set(next.widgets.filter(\.enabled).flatMap(\.events)).map { event in
                center.addObserver(forName: Notification.Name(event), object: nil, queue: .main) { [weak self] notification in
                    var environment = notification.userInfo as? [String: String] ?? [:]
                    if environment["INFO"] == nil, let info = notification.userInfo,
                       let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) {
                        environment["INFO"] = String(decoding: data, as: UTF8.self)
                    }
                    MainActor.assumeIsolated {
                        self?.refreshScripts(for: event, environment: environment)
                    }
                }
            }
            onConfigurationChange?()
        } catch {
            configurationError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func commandEnvironment(_ widget: WidgetConfiguration, configuration: Configuration) -> [String: String] {
        var environment = configuration.environment.merging(widget.environment) { _, widget in widget }
        environment["NAME"] = widget.id
        environment["CONFIG_DIR"] = configurationURL.deletingLastPathComponent().path
        return environment
    }

    func refreshScripts(for event: String, environment: [String: String] = [:]) {
        for widget in configuration?.widgets ?? [] where widget.events.contains(event) {
            scripts[widget.id]?.refresh(ScriptEvent(sender: event, environment: environment))
        }
    }

    @discardableResult
    func runAction(_ command: String, widget: WidgetConfiguration,
                   event: ScriptEvent = ScriptEvent(sender: "mouse.clicked")) -> Task<Void, Never> {
        let id = UUID()
        let script = scripts[widget.id]
        let environment = event.commandEnvironment(commandEnvironment(widget, configuration: configuration!))
        let previous = actionTails[widget.id]?.task
        let task = Task {
            await previous?.value
            defer {
                actions.removeValue(forKey: id)
                if actionTails[widget.id]?.id == id { actionTails.removeValue(forKey: widget.id) }
            }
            do {
                try Task.checkCancellation()
                _ = try await runCommand("/bin/zsh", arguments: ["-lc", command],
                                         timeout: widget.timeout, environment: environment)
                if let script, scripts[widget.id] === script {
                    script.refresh(ScriptEvent(sender: "action", environment: event.environment))
                }
                actionError = nil
            } catch {
                if Task.isCancelled { return }
                actionError = error.localizedDescription
            }
        }
        actions[id] = task
        actionTails[widget.id] = (id, task)
        return task
    }

    func openConfiguration() {
        NSWorkspace.shared.open(configurationURL)
    }

    func stop() {
        popup.close()
        reloadTask?.cancel()
        configurationWatcher.stop()
        aerospace.stop()
        for script in scripts.values { script.stop() }
        for action in actions.values { action.cancel() }
        actions.removeAll()
        actionTails.removeAll()
        for observer in eventObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        if let reloadObserver { DistributedNotificationCenter.default().removeObserver(reloadObserver) }
        reloadObserver = nil
        eventObservers.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

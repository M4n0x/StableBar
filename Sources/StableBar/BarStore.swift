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
    let configurationURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/stablebar/config.json")
    var onConfigurationChange: (() -> Void)?
    private var directoryWatch: DispatchSourceFileSystemObject?
    private var fileWatch: DispatchSourceFileSystemObject?
    private var reloadTask: Task<Void, Never>?
    private var eventObservers: [NSObjectProtocol] = []

    func start() {
        aerospace.onWorkspaceChange = { [weak self] in
            self?.popup.close()
            self?.refreshScripts(for: "workspace")
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
            directoryWatch = watch(directory)
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
        refreshScripts(for: "frontApp")
    }

    private func watch(_ url: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
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
        fileWatch?.cancel()
        fileWatch = watch(configurationURL)
        do {
            let data = try Data(contentsOf: configurationURL)
            let next = try JSONDecoder().decode(Configuration.self, from: data)
            popup.close()
            let previous = configuration?.widgets ?? []
            for (id, script) in scripts {
                let oldContent = previous.first { $0.id == id }?.content
                let newContent = next.widgets.first { $0.id == id }?.content
                if oldContent != newContent || script.error != nil {
                    script.stop()
                    scripts.removeValue(forKey: id)
                }
            }
            for widget in next.widgets {
                if case let .script(command, interval) = widget.content, scripts[widget.id] == nil {
                    let script = ScriptWidget()
                    scripts[widget.id] = script
                    script.start(command: command, interval: interval)
                }
            }
            let needsAeroSpace = next.widgets.contains { $0.content == .workspaces || $0.display == .active }
            let hadAeroSpace = previous.contains { $0.content == .workspaces || $0.display == .active }
            if needsAeroSpace && !hadAeroSpace { aerospace.start() }
            if !needsAeroSpace && hadAeroSpace { aerospace.stop() }
            configuration = next
            configurationError = nil
            let center = DistributedNotificationCenter.default()
            for observer in eventObservers { center.removeObserver(observer) }
            eventObservers = Set(next.widgets.flatMap(\.events)).map { event in
                center.addObserver(forName: Notification.Name(event), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshScripts(for: event) }
                }
            }
            onConfigurationChange?()
        } catch {
            configurationError = String(describing: error)
        }
    }

    func refreshScripts(for event: String) {
        for widget in configuration?.widgets ?? [] where widget.events.contains(event) {
            if case let .script(command, interval) = widget.content, let script = scripts[widget.id] {
                script.stop()
                script.start(command: command, interval: interval)
            }
        }
    }

    func runAction(_ command: String, widget: WidgetConfiguration) {
        Task {
            do {
                _ = try await runCommand("/bin/zsh", arguments: ["-lc", command])
                if case let .script(command, interval) = widget.content, let script = scripts[widget.id] {
                    script.stop()
                    script.start(command: command, interval: interval)
                }
                actionError = nil
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func openConfiguration() {
        NSWorkspace.shared.open(configurationURL)
    }

    func stop() {
        popup.close()
        reloadTask?.cancel()
        fileWatch?.cancel()
        directoryWatch?.cancel()
        aerospace.stop()
        for script in scripts.values { script.stop() }
        for observer in eventObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        eventObservers.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

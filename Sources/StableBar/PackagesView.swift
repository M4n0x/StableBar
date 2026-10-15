import AppKit
import SwiftUI

struct PackagesView: View {
    let store: BarStore
    @State private var installed: [WidgetPackageManifest] = []
    @State private var selections: [WidgetPackageSelection] = []
    @State private var inspection: WidgetPackageInspection?
    @State private var settings: [String: ConfigurationValue] = [:]
    @State private var error: String?

    private var packages: WidgetPackageStore {
        WidgetPackageStore(directory: store.configurationURL.deletingLastPathComponent().appending(path: "packages"))
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { inspection?.manifest.versionKey }, set: { key in
                    if let manifest = installed.first(where: { $0.versionKey == key }) {
                        perform { try select(packages.directory(id: manifest.id, version: manifest.version)) }
                    }
                })) {
                    Section("Installed") {
                        ForEach(installed, id: \.versionKey) { manifest in
                            Label {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(manifest.name).lineLimit(1)
                                        Text("\(manifest.id) · \(manifest.version)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selections.contains(where: { $0.id == manifest.id && $0.version == manifest.version && $0.enabled }) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Enabled")
                                    }
                                }
                            } icon: {
                                Image(systemName: "shippingbox")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if installed.isEmpty {
                        Text("No packages installed").foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack {
                    Button("Review Package Folder…", systemImage: "folder.badge.plus", action: chooseFolder)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 220, maxWidth: 300, maxHeight: .infinity)

            VStack(spacing: 0) {
                if let inspection {
                    packageDetails(inspection)
                } else {
                    ContentUnavailableView {
                        Label("Widget packages", systemImage: "shippingbox")
                    } description: {
                        Text("Choose a local package folder to review its settings and commands.")
                    } actions: {
                        Button("Review Package Folder…", action: chooseFolder)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let error {
                    Divider()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.1))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { perform(loadInstalled) }
        .onChange(of: store.effectiveDocument) { _, _ in perform(loadInstalled) }
        .onChange(of: settings) { _, values in
            if let inspection {
                perform { self.inspection = try packages.inspect(inspection.directory, settings: values) }
            }
        }
    }

    private func packageDetails(_ inspection: WidgetPackageInspection) -> some View {
        let manifest = inspection.manifest
        let installedDirectory = packages.directory.appending(path: manifest.id).appending(path: manifest.version)
        let isInstalled = inspection.directory.standardizedFileURL == installedDirectory.standardizedFileURL
        let isEnabled = selections.contains { $0.id == manifest.id && $0.version == manifest.version && $0.enabled }
        return VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manifest.name).font(.title3.weight(.semibold))
                            Text("\(manifest.id) · Version \(manifest.version)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(isEnabled ? "Enabled" : isInstalled ? "Installed" : "Not installed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isEnabled ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isEnabled ? Color.green.opacity(0.15) : Color.primary.opacity(0.06), in: Capsule())
                    }
                    LabeledContent("Location") {
                        HStack {
                            Text(inspection.directory.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(inspection.directory) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Open folder in Finder")
                        }
                    }
                }
                if !manifest.settings.isEmpty {
                    Section("Settings") {
                        ForEach(manifest.settings.keys.sorted(), id: \.self) { name in
                            PackageSettingField(title: manifest.settings[name]!.title ?? name,
                                                value: Binding(get: { settings[name]! }, set: { settings[name] = $0 }))
                        }
                    }
                }
                Section {
                    if inspection.commands.isEmpty {
                        Text("This package declares no commands.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(inspection.commands.enumerated()), id: \.offset) { _, command in
                        Text(command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text("Commands")
                } footer: {
                    Text("Review the commands this package can run, including its profiles. Commands run with your account’s access when the package is enabled.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 10) {
                Text(isInstalled ? "Enabling pins this version. Select an older installed version to roll back." : "Installation copies the package. Enable it separately after review.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if isInstalled {
                    if isEnabled {
                        Button("Disable") { perform { try activate(manifest, enabled: false) } }
                    }
                    Button(isEnabled ? "Save Settings" : "Enable Version \(manifest.version)") {
                        perform { try activate(manifest, enabled: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(error != nil)
                } else {
                    Button("Install Version \(manifest.version)") {
                        perform {
                            let installed = try packages.install(inspection.directory)
                            self.inspection = try packages.inspect(installed.directory, settings: settings)
                            try loadInstalled()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(error != nil)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Review package"
        if panel.runModal() == .OK, let url = panel.url { perform { try select(url) } }
    }

    private func select(_ directory: URL) throws {
        let manifest = try packages.manifest(at: directory)
        let supplied = selections.first { $0.id == manifest.id && $0.version == manifest.version }?.settings ?? [:]
        let values = try manifest.values(supplied)
        let reviewed = try packages.inspect(directory, settings: values)
        settings = values
        inspection = reviewed
    }

    private func loadInstalled() throws {
        installed = try packages.list()
        selections = try store.effectiveDocument["packages"]?.decoded([WidgetPackageSelection].self) ?? []
    }

    private func activate(_ manifest: WidgetPackageManifest, enabled: Bool) throws {
        let edit = ConfigurationEdit(action: .package, properties: [
            "id": .string(manifest.id), "version": .string(manifest.version),
            "enabled": .bool(enabled), "settings": .object(settings)
        ])
        try store.applyEdits([edit], persist: true)
        try loadInstalled()
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = errorMessage(error)
        }
    }
}

private extension WidgetPackageManifest {
    var versionKey: String { "\(id)/\(version)" }
}

private struct PackageSettingField: View {
    let title: String
    @Binding var value: ConfigurationValue

    var body: some View {
        switch value {
        case let .string(text):
            TextField(title, text: Binding(get: { text }, set: { value = .string($0) }))
        case let .number(number):
            TextField(title, value: Binding(get: { number }, set: { value = .number($0) }), format: .number)
        case let .bool(enabled):
            Toggle(title, isOn: Binding(get: { enabled }, set: { value = .bool($0) }))
        default:
            EmptyView()
        }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LocalPluginSettingsView: View {
    @ObservedObject private var store = LocalPluginStore.shared
    @State private var pending: ManifestImport?
    @State private var selected: InstalledLocalPlugin?
    @State private var error: String?
    @State private var showFormat = false
    private struct ManifestImport: Identifiable { let id = UUID(); let manifest: LocalPluginManifest }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) { heading; Spacer(minLength: 16); importButton }
                VStack(alignment: .leading, spacing: 12) { heading; importButton.frame(maxWidth: .infinity, alignment: .trailing) }
            }
            if let error = error ?? store.storageError { Text(error).font(.system(size: 12)).foregroundStyle(.secondary) }
            if store.plugins.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "terminal").font(.system(size: 22)).frame(width: 44, height: 44)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    Text("No local tools yet").font(.system(size: 14, weight: .semibold))
                    Text("Import a manifest to expose an app's CLI or add a dictation hook.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("View manifest format") { showFormat = true }.buttonStyle(.plain).font(.system(size: 12))
                }.padding(20).frame(maxWidth: 300, minHeight: 190, alignment: .topLeading).settingsSurface()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 420), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(store.plugins) { plugin in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "terminal").font(.system(size: 22)).frame(width: 44, height: 44)
                                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                Spacer()
                                Toggle("Enable " + plugin.manifest.name, isOn: Binding(get: { plugin.enabled }, set: { enabled in
                                    perform { try store.setEnabled(id: plugin.id, enabled: enabled) }
                                })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                            }
                            Text(plugin.manifest.name).font(.system(size: 14, weight: .semibold))
                            Text(plugin.manifest.description).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                            Spacer(minLength: 0)
                            HStack {
                                Label(plugin.enabled ? "Enabled" : "Disabled", systemImage: plugin.enabled ? "checkmark.circle.fill" : "minus.circle")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Manage") { selected = plugin }.buttonStyle(SpeekActionButtonStyle())
                            }
                        }.padding(20).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading).settingsSurface()
                    }
                }
            }
        }
        .sheet(item: $pending) { item in
            LocalManifestReview(manifest: item.manifest) {
                do { try store.install(item.manifest); pending = nil; error = nil }
                catch { self.error = LocalPluginStore.safeError(error); pending = nil }
            }
        }
        .sheet(item: $selected) { plugin in LocalPluginDetail(id: plugin.id, store: store) }
        .sheet(isPresented: $showFormat) { LocalManifestFormat() }
    }
    private var heading: some View {
        HStack(spacing: 6) {
            Text("Local tools").font(.system(size: 15, weight: .semibold))
            InfoButton(text: "Expose an app's command-line tool to Speek, or add a dictation hook, by importing a manifest.", subject: "Local tools")
        }
    }
    private var importButton: some View {
        Button { importManifest() } label: { Label("Import plugin", systemImage: "plus") }
            .buttonStyle(SpeekActionButtonStyle()).fixedSize().disabled(store.storageError != nil)
    }
    private func perform(_ work: () throws -> Void) { do { try work(); error = nil } catch { self.error = LocalPluginStore.safeError(error) } }
    private func importManifest() {
        let panel = NSOpenPanel()
        panel.title = "Import local plugin"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            perform { pending = ManifestImport(manifest: try LocalPluginStore.readManifest(from: url)) }
        }
    }
}

private struct LocalManifestReview: View {
    let manifest: LocalPluginManifest
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import " + manifest.name).font(.system(size: 20, weight: .semibold))
            Text(manifest.description).font(.system(size: 13)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Executable", systemImage: "terminal").font(.system(size: 13, weight: .medium))
                        Text(manifest.executable).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        Text("This program will run with your Mac account's access when you approve a tool request.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(16).settingsSurface()
                    ForEach(manifest.tools) { tool in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tool.title ?? tool.name).font(.system(size: 13, weight: .medium))
                            Text(tool.description).font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(tool.arguments.joined(separator: " ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if manifest.dictationHook != nil {
                        Label("Includes an optional dictation hook", systemImage: "waveform").font(.system(size: 13, weight: .medium))
                        Text("Hooks stay off until you explicitly enable them for selected apps.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Importing saves this configuration. Enable the plugin in its card when you are ready.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Import") { onImport() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520, height: 540)
    }
}

private struct LocalPluginDetail: View {
    let id: UUID
    @ObservedObject var store: LocalPluginStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var remove = false
    private var plugin: InstalledLocalPlugin? { store.plugins.first { $0.id == id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(plugin?.manifest.name ?? "Local plugin").font(.system(size: 20, weight: .semibold))
            ScrollView {
                if let plugin {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(plugin.manifest.executable).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        Toggle("Enable plugin", isOn: Binding(get: { plugin.enabled }, set: { enabled in perform { try store.setEnabled(id: id, enabled: enabled) } }))
                            .font(.system(size: 13)).toggleStyle(.switch).controlSize(.small)
                        if !plugin.manifest.tools.isEmpty {
                            Text("Tools").font(.system(size: 13, weight: .semibold))
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(plugin.manifest.tools) { tool in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Toggle(tool.title ?? tool.name, isOn: Binding(get: { !plugin.disabledTools.contains(tool.name) }, set: { enabled in
                                            perform { try store.setToolEnabled(pluginID: id, name: tool.name, enabled: enabled) }
                                        })).font(.system(size: 13, weight: .medium)).toggleStyle(.switch).controlSize(.small)
                                        Text(tool.description).font(.system(size: 12)).foregroundStyle(.secondary)
                                        DisclosureGroup("Input fields and arguments") {
                                            Text(tool.inputSchema.jsonString + "\n\n" + tool.arguments.joined(separator: "\n"))
                                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 6)
                                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(16).settingsSurface()
                        }
                        if plugin.manifest.dictationHook != nil {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Process dictation", isOn: Binding(get: { plugin.hookEnabled }, set: { enabled in perform { try store.setHookEnabled(id: id, enabled: enabled) } }))
                                    .font(.system(size: 13, weight: .medium)).toggleStyle(.switch).controlSize(.small)
                                    .disabled(!plugin.enabled || plugin.hookApplications.isEmpty)
                                Text("When enabled, this program receives and can rewrite dictated text in the apps below. Failed hooks preserve your text.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                ForEach(plugin.hookApplications) { app in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(app.name).font(.system(size: 12))
                                            Text(app.bundleID).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button { perform { try store.removeHookApplication(pluginID: id, bundleID: app.bundleID) } } label: {
                                            Image(systemName: "minus.circle").frame(width: 28, height: 28)
                                        }.buttonStyle(.plain).accessibilityLabel("Remove " + app.name)
                                    }
                                }
                                HStack {
                                    if plugin.hookApplications.isEmpty { Text("Choose an app before enabling this hook.").font(.system(size: 11)).foregroundStyle(.secondary) }
                                    Spacer()
                                    Button { chooseApp() } label: { Label("Add app", systemImage: "plus") }.buttonStyle(SpeekActionButtonStyle())
                                }
                            }.padding(16).settingsSurface()
                        }
                    }
                }
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack {
                Button("Remove") { remove = true }.buttonStyle(SpeekActionButtonStyle())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540, height: 600)
            .alert("Remove local plugin?", isPresented: $remove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { perform { try store.remove(id: id); dismiss() } }
            } message: { Text("This removes Speek's configuration and permissions. The program itself is kept.") }
    }
    private func perform(_ work: () throws -> Void) { do { try work(); error = nil } catch { self.error = LocalPluginStore.safeError(error) } }
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Allow dictation hook in an app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { error = "This application has no bundle identifier."; return }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
            perform { try store.addHookApplication(pluginID: id, bundleID: bundleID, name: name) }
        }
    }
}

private struct LocalManifestFormat: View {
    @Environment(\.dismiss) private var dismiss
    private let example = """
    {
      "schemaVersion": 1,
      "name": "My app",
      "description": "Tools from my local app.",
      "executable": "/absolute/path/to/my-app",
      "tools": [{
        "name": "search",
        "description": "Search my app.",
        "inputSchema": {
          "type": "object",
          "properties": { "query": { "type": "string" } },
          "required": ["query"]
        },
        "arguments": ["search", "{{query}}"],
        "timeoutSeconds": 30
      }],
      "dictationHook": {
        "arguments": ["rewrite-dictation"],
        "timeoutSeconds": 5
      }
    }
    """
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Local plugin manifest").font(.system(size: 20, weight: .semibold))
            ScrollView { Text(example).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Text("Tools receive {tool, arguments} as JSON on stdin. A {{field}} argument inserts one scalar value without shell evaluation. Hooks receive {text, appBundleID} and must return {text} as JSON. The hook is optional.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("Copy example") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(example, forType: .string) }.buttonStyle(SpeekActionButtonStyle())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540, height: 570)
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import InputPilotCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var showingApps = false
    var visibleRules: [AppRule] {
        model.rules.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard").font(.system(size: 25)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("应用输入法").font(.title2.weight(.semibold))
                    Text(model.currentSourceName).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.setPaused(!model.configuration.paused)
                } label: {
                    Label(model.configuration.paused ? "恢复切换" : "暂停切换", systemImage: model.configuration.paused ? "play.fill" : "pause.fill")
                }.controlSize(.large)
            }.padding(22)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("默认输入法").frame(width: 145, alignment: .leading)
                    Picker("默认输入法", selection: Binding(get: { model.configuration.defaultSourceID ?? "" }, set: model.setDefault)) {
                        Text("保持当前输入法").tag("")
                        ForEach(model.sources) { Text($0.name).tag($0.id) }
                        if let id = model.configuration.defaultSourceID, !model.sources.contains(where: { $0.id == id }) {
                            Text("已不可用的输入法").tag(id)
                        }
                    }.labelsHidden().frame(maxWidth: 260)
                    Spacer()
                }
                HStack {
                    Toggle("未预设的应用记住上次输入法", isOn: Binding(get: { model.configuration.rememberUnconfigured }, set: model.setRememberUnconfigured))
                    Spacer()
                    Toggle("开机启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
                }.toggleStyle(.checkbox)
                if model.loginStatus == .requiresApproval {
                    HStack {
                        Text("开机启动等待系统批准").foregroundStyle(.orange)
                        Button("打开登录项") { SMAppService.openSystemSettingsLoginItems() }
                    }.font(.callout)
                }
            }.padding(22).disabled(model.configurationError != nil)
            Divider()
            HStack {
                Text("应用规则").font(.headline)
                Text("\(model.rules.count)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                TextField("搜索应用", text: $search).textFieldStyle(.roundedBorder).frame(width: 170)
                Button { showingApps = true } label: { Image(systemName: "plus") }
                    .help("添加应用").accessibilityLabel("添加应用")
                    .disabled(model.configurationError != nil)
            }.padding(.horizontal, 22).padding(.vertical, 14)
            HStack {
                Text("应用").frame(maxWidth: .infinity, alignment: .leading)
                Text("切换规则").frame(width: 218, alignment: .leading)
                Spacer().frame(width: 28)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 8)
            Divider()
            if visibleRules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: search.isEmpty ? "app.dashed" : "magnifyingglass").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text(search.isEmpty ? "尚未添加应用" : "没有匹配的应用").foregroundStyle(.secondary)
                    if search.isEmpty { Button("添加应用") { showingApps = true }.disabled(model.configurationError != nil) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleRules) { rule in
                            ruleRow(rule)
                            Divider().padding(.leading, 72)
                        }
                    }
                }.disabled(model.configurationError != nil)
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(model.configuration.paused ? Color.orange : Color.green).frame(width: 7, height: 7)
                Text(model.configuration.paused ? "已暂停" : "自动切换已开启")
                Spacer()
                if !model.activeAppName.isEmpty { Text(model.activeAppName).lineLimit(1) }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 12)
            if let error = model.configurationError ?? model.message {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.bottom, 14)
            }
        }
        .frame(minWidth: 650, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingApps) { AppChooser(model: model) }
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: icon(for: rule)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name).font(.body.weight(.medium)).lineLimit(1)
                Text(rule.policy == .remember ? "上次：\(model.sourceName(model.configuration.remembered[rule.id]))" : rule.id)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Picker("\(rule.name) 的输入法", selection: Binding(get: { model.selection(for: rule) }, set: { model.setSelection($0, for: rule.id) })) {
                Text("记住上次输入法").tag("@remember")
                Text("使用全局默认").tag("@default")
                Divider()
                ForEach(model.sources) { Text($0.name).tag($0.id) }
                if rule.policy == .fixed, let id = rule.inputSourceID, !model.sources.contains(where: { $0.id == id }) {
                    Text("已不可用的输入法").tag(id)
                }
            }.labelsHidden().frame(width: 218)
            Button { model.removeApp(rule.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).frame(width: 28)
                .help("移除 \(rule.name) 的规则与记忆").accessibilityLabel("移除 \(rule.name)")
        }.padding(.horizontal, 22).padding(.vertical, 12)
    }

    private func icon(for rule: AppRule) -> NSImage {
        let url = rule.path.map { URL(fileURLWithPath: $0) } ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.id)
        return url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(named: NSImage.applicationIconName)!
    }
}

private struct AppChooser: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    private var apps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleURL != nil
                && (search.isEmpty || ($0.localizedName ?? "").localizedCaseInsensitiveContains(search))
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加应用").font(.title3.weight(.semibold))
            TextField("搜索正在运行的应用", text: $search).textFieldStyle(.roundedBorder)
            List(apps, id: \.processIdentifier) { app in
                HStack {
                    Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 26, height: 26)
                    Text(app.localizedName ?? app.bundleIdentifier ?? "应用")
                    Spacer()
                    if model.configuration.rules.contains(where: { $0.id == app.bundleIdentifier }) {
                        Image(systemName: "checkmark").foregroundStyle(.secondary)
                    } else {
                        Button("添加") {
                            if let url = app.bundleURL { model.addApp(url: url) }
                        }
                    }
                }.padding(.vertical, 3)
            }
            HStack {
                Button("从应用程序中选择…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.applicationBundle]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = false
                    panel.prompt = "添加"
                    if panel.runModal() == .OK { panel.urls.forEach(model.addApp) }
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 450, height: 440)
    }
}

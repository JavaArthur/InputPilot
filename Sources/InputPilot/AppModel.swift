import AppKit
import Carbon
import SwiftUI
import ServiceManagement
import InputPilotCore
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var configuration: Configuration
    @Published private(set) var sources: [InputSource] = []
    @Published private(set) var currentSourceID: String?
    @Published private(set) var activeAppName = ""
    @Published private(set) var activeBundleID: String?
    @Published private(set) var message: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var configurationError: String?

    let configurationURL: URL
    private var state = SwitchState()
    private var switchTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let ownID = Bundle.main.bundleIdentifier ?? "cn.aichanning.InputPilot"
    private let logger = Logger(subsystem: "cn.aichanning.InputPilot", category: "switching")
    var onStatusChange: (() -> Void)?

    init(configurationURL: URL? = nil) {
        self.configurationURL = configurationURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InputPilot/config.json")
        do {
            configuration = try ConfigurationFile.load(self.configurationURL)
        } catch {
            configuration = Configuration()
            configuration.paused = true
            configurationError = "配置读取失败，已暂停。原文件保留：\(error.localizedDescription)"
        }
        sources = InputSources.available()
        currentSourceID = InputSources.currentID()
    }

    var currentSourceName: String {
        sources.first { $0.id == currentSourceID }?.name ?? "未知输入法"
    }
    var menuTitle: String {
        configuration.paused ? "Ⅱ" : (sources.first { $0.id == currentSourceID }?.shortName ?? "键")
    }
    var rules: [AppRule] {
        configuration.rules.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var loginEnabled: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }

    func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in self?.activateFrontmost() }
        observe(workspaceCenter, NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.refreshSources()
            self?.activateFrontmost()
        }
        observe(workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in self?.activateFrontmost() }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { [weak self] _ in
            self?.refreshSources()
            self?.loginStatus = SMAppService.mainApp.status
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)) { [weak self] _ in
            self?.sourceChanged()
        }
        observe(distributed, Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)) { [weak self] _ in
            self?.refreshSources()
            self?.activateFrontmost()
        }
        activateFrontmost()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         handler: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        }
        observers.append((center, token))
    }

    func stop() {
        switchTask?.cancel()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    func refreshSources() {
        sources = InputSources.available()
        currentSourceID = InputSources.currentID()
        onStatusChange?()
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func activateFrontmost() {
        switchTask?.cancel()
        let app = NSWorkspace.shared.frontmostApplication
        let eligible = app?.bundleIdentifier != ownID && app?.activationPolicy == .regular
        let bundleID = eligible ? app?.bundleIdentifier : nil
        if let bundleID {
            activeAppName = app?.localizedName ?? bundleID
            activeBundleID = bundleID
        }
        currentSourceID = InputSources.currentID()
        let request = state.activate(pid: bundleID == nil ? nil : app?.processIdentifier, bundleID: bundleID,
                                     configuration: configuration, currentID: currentSourceID, now: now)
        if let request { schedule(request) }
        onStatusChange?()
    }

    private func schedule(_ first: SwitchRequest) {
        message = nil
        switchTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard let self else { return }
            var request = first
            while !Task.isCancelled {
                guard !self.configuration.paused,
                      self.state.isCurrent(request, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) else { return }
                guard self.sources.contains(where: { $0.id == request.sourceID }) else {
                    self.message = "预设输入法已不可用，请重新选择。"
                    self.state.finish(request, now: self.now)
                    self.onStatusChange?()
                    return
                }
                let status = InputSources.select(request.sourceID)
                self.logger.debug("Select requested, status=\(status), remaining=\(request.retriesLeft)")
                if status != noErr {
                    self.message = "输入法切换失败（\(status)）。"
                    self.state.finish(request, now: self.now)
                    self.onStatusChange?()
                    return
                }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard self.state.isCurrent(request, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) else { return }
                self.currentSourceID = InputSources.currentID()
                if self.currentSourceID == request.sourceID {
                    self.state.finish(request, now: self.now)
                    self.onStatusChange?()
                    return
                }
                guard let retry = self.state.retry(request) else {
                    self.state.finish(request, now: self.now)
                    self.message = "切换未生效。请检查系统的“自动切换到文稿的输入法”设置。"
                    self.onStatusChange?()
                    return
                }
                request = retry
            }
        }
    }

    private func sourceChanged() {
        currentSourceID = InputSources.currentID()
        defer { onStatusChange?() }
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier,
              bundleID != ownID, app.activationPolicy == .regular, let sourceID = currentSourceID,
              state.canRemember(bundleID: bundleID, frontmostPID: app.processIdentifier,
                                now: now, configuration: configuration),
              configuration.remembered[bundleID] != sourceID else { return }
        persist { config in
            config.remembered[bundleID] = sourceID
            if !config.rules.contains(where: { $0.id == bundleID }) {
                config.rules.append(AppRule(id: bundleID, name: app.localizedName ?? bundleID, path: app.bundleURL?.path))
            }
        }
    }

    private func persist(_ edit: (inout Configuration) -> Void) {
        guard configurationError == nil else { return }
        var next = configuration
        edit(&next)
        do {
            try ConfigurationFile.save(next, to: configurationURL)
            configuration = next
        } catch {
            message = "配置保存失败：\(error.localizedDescription)"
        }
        onStatusChange?()
    }

    func setPaused(_ value: Bool) {
        persist { $0.paused = value }
        activateFrontmost()
    }
    func setRememberUnconfigured(_ value: Bool) {
        persist { $0.rememberUnconfigured = value }
        activateFrontmost()
    }
    func setDefault(_ value: String) {
        persist { $0.defaultSourceID = value.isEmpty ? nil : value }
        activateFrontmost()
    }
    func setSelection(_ selection: String, for id: String) {
        persist { config in
            guard let index = config.rules.firstIndex(where: { $0.id == id }) else { return }
            switch selection {
            case "@remember": config.rules[index].policy = .remember; config.rules[index].inputSourceID = nil
            case "@default": config.rules[index].policy = .globalDefault; config.rules[index].inputSourceID = nil
            default: config.rules[index].policy = .fixed; config.rules[index].inputSourceID = selection
            }
        }
        activateFrontmost()
    }
    func selection(for rule: AppRule) -> String {
        switch rule.policy {
        case .fixed: return rule.inputSourceID ?? "@default"
        case .remember: return "@remember"
        case .globalDefault: return "@default"
        }
    }
    func addApp(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != ownID else {
            message = "请选择其他有效的应用程序。"
            return
        }
        guard !configuration.rules.contains(where: { $0.id == id }) else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        persist { $0.rules.append(AppRule(id: id, name: name, path: url.path,
                                        policy: $0.rememberUnconfigured ? .remember : .globalDefault)) }
    }
    func removeApp(_ id: String) {
        persist {
            $0.rules.removeAll { $0.id == id }
            $0.remembered.removeValue(forKey: id)
        }
        activateFrontmost()
    }
    func sourceName(_ id: String?) -> String {
        guard let id else { return "尚无记录" }
        return sources.first { $0.id == id }?.name ?? "输入法不可用"
    }
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
            message = nil
        } catch {
            loginStatus = SMAppService.mainApp.status
            message = "开机启动设置失败：\(error.localizedDescription)"
        }
    }
}

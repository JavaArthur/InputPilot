import AppKit
import SwiftUI
import InputPilotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var item: NSStatusItem!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ownID = Bundle.main.bundleIdentifier ?? "cn.aichanning.InputPilot"
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: ownID)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        var configURL: URL?
        if let index = CommandLine.arguments.firstIndex(of: "--config"), index + 1 < CommandLine.arguments.count {
            configURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        model = AppModel(configurationURL: configURL)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = NSMenu()
        item.menu?.delegate = self
        model.onStatusChange = { [weak self] in self?.updateStatus() }
        model.start()
        updateStatus()
        installMainMenu()
        if (configURL == nil && !UserDefaults.standard.bool(forKey: "hasOpenedSettings")) || CommandLine.arguments.contains("--settings") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model?.stop() }

    private func updateStatus() {
        item.button?.title = model.menuTitle
        item.button?.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        item.button?.toolTip = "应用输入法 · \(model.currentSourceName)\(model.configuration.paused ? " · 已暂停" : "")"
        item.button?.setAccessibilityLabel("应用输入法：\(model.currentSourceName)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = NSMenuItem(title: "当前：\(model.currentSourceName)", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())
        if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
           id != Bundle.main.bundleIdentifier, let url = app.bundleURL, app.activationPolicy == .regular {
            let submenuItem = NSMenuItem(title: "为 \(app.localizedName ?? id) 预设", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for source in model.sources {
                let choice = NSMenuItem(title: source.name, action: #selector(quickRule(_:)), keyEquivalent: "")
                choice.target = self
                choice.representedObject = ["path": url.path, "id": id, "source": source.id]
                if model.configuration.rules.contains(where: { $0.id == id && $0.policy == .fixed && $0.inputSourceID == source.id }) {
                    choice.state = .on
                }
                submenu.addItem(choice)
            }
            submenuItem.submenu = submenu
            menu.addItem(submenuItem)
        }
        let pause = NSMenuItem(title: model.configuration.paused ? "恢复自动切换" : "暂停自动切换", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let settings = NSMenuItem(title: "应用规则与设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出应用输入法", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func quickRule(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [String: String],
              let path = values["path"], let id = values["id"], let source = values["source"] else { return }
        model.addApp(url: URL(fileURLWithPath: path))
        model.setSelection(source, for: id)
    }

    @objc private func togglePause() { model.setPaused(!model.configuration.paused) }

    @objc func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 730, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "应用输入法"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.minSize = NSSize(width: 650, height: 550)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "退出应用输入法", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        editItem.submenu = NSMenu(title: "编辑")
        for (name, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                      ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editItem.submenu?.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key)
        }
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}

if CommandLine.arguments.contains("--list-inputs") {
    let value: [String: Any] = ["current": InputSources.currentID() ?? "", "sources": InputSources.available().map {
        ["id": $0.id, "name": $0.name, "language": $0.language]
    }]
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} else {
    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        withExtendedLifetime(delegate) { NSApplication.shared.run() }
    }
}

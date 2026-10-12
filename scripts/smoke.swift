import AppKit
import Carbon

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let configURL = root.appendingPathComponent("verification/config.json")
let fixtureBinary = root.appendingPathComponent("verification/Fixture")
let fm = FileManager.default
var running: [NSRunningApplication] = []
var pilot: NSRunningApplication?
var failures = 0
let initialApp = NSWorkspace.shared.frontmostApplication

func current() -> String {
    let input = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let value = TISGetInputSourceProperty(input, kTISPropertyInputSourceID)!
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}
func select(_ id: String) {
    let filter = [kTISPropertyInputSourceID!: id] as CFDictionary
    let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
    if let input = list.first { _ = TISSelectInputSource(input) }
}
let initialSource = current()
func wait(_ seconds: Double) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}
func check(_ name: String, _ condition: @autoclosure () throws -> Bool) rethrows {
    let success = try condition()
    if !success { failures += 1 }
    print("\(success ? "PASS" : "FAIL") \(name); current=\(current())")
}
func open(_ url: URL, arguments: [String] = []) throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = arguments
    configuration.activates = false
    var result: NSRunningApplication?
    var openError: Error?
    var finished = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
        result = app; openError = error; finished = true
    }
    let deadline = Date().addingTimeInterval(10)
    while !finished && Date() < deadline { wait(0.05) }
    if let openError { throw openError }
    guard let result else { throw NSError(domain: "Smoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Launch timed out"]) }
    return result
}
func focus(_ app: NSRunningApplication, settle: Double = 0.9) {
    app.activate(options: [.activateIgnoringOtherApps])
    wait(settle)
}
func readConfig() throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
}
func run() throws {
    defer {
        pilot?.terminate()
        running.forEach { $0.terminate() }
        wait(0.5)
        initialApp?.activate(options: [.activateIgnoringOtherApps])
        wait(0.3)
        select(initialSource)
    }
    let english = "com.apple.keylayout.ABC"
    let filter = [kTISPropertyInputSourceIsEnabled!: kCFBooleanTrue!, kTISPropertyInputSourceIsSelectCapable!: kCFBooleanTrue!] as CFDictionary
    let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
    let ids = sources.compactMap { source -> String? in
        guard let p = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    guard ids.contains(english), let chinese = ids.first(where: { $0 != english && ($0.lowercased().contains("wetype") || $0.contains("SCIM") || $0.lowercased().contains("pinyin")) }) else {
        throw NSError(domain: "Smoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Need enabled ABC and Chinese sources"])
    }
    let prefix = "cn.aichanning.InputPilot.fixture."
    let config: [String: Any] = ["schemaVersion": 1, "paused": false, "rememberUnconfigured": true,
        "defaultSourceID": english,
        "rules": [["id": prefix + "A", "name": "Test A", "policy": "fixed", "inputSourceID": english],
                  ["id": prefix + "B", "name": "Test B", "policy": "fixed", "inputSourceID": chinese],
                  ["id": prefix + "C", "name": "Test C", "policy": "remember"]],
        "remembered": [prefix + "C": chinese]]
    try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]).write(to: configURL)
    for name in ["A", "B", "C", "D"] {
        let bundle = root.appendingPathComponent("verification/Fixture\(name).app")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("Fixture")
        if !fm.fileExists(atPath: executable.path) { try fm.copyItem(at: fixtureBinary, to: executable) }
        let plist = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": prefix + name,
                     "CFBundleName": "InputPilot Test \(name)", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        running.append(try open(bundle))
    }
    wait(0.5)
    pilot = try open(root.appendingPathComponent("dist/InputPilot.app"), arguments: ["--config", configURL.path])
    wait(0.8)
    focus(running[1]); check("B fixed Chinese", current() == chinese)
    focus(running[0]); check("A fixed ABC", current() == english)
    focus(running[1]); focus(running[3]); check("unconfigured global default", current() == english)
    focus(running[2]); check("C restores previous source", current() == chinese)
    select(english); wait(0.8)
    try check("manual change persisted", (try readConfig()["remembered"] as? [String: String])?[prefix + "C"] == english)
    focus(running[1]); focus(running[2]); check("C restores new memory", current() == english)
    focus(running[0]); select(chinese); wait(0.7)
    try check("fixed rule did not learn manual source", (try readConfig()["remembered"] as? [String: String])?[prefix + "A"] == nil)
    focus(running[1]); focus(running[0]); check("A preset still wins", current() == english)
    for _ in 0..<5 {
        focus(running[0], settle: 0.03)
        focus(running[1], settle: 0.03)
    }
    focus(running[0]); check("rapid switch finishes on A", current() == english)
    pilot?.terminate(); wait(0.8)
    pilot = try open(root.appendingPathComponent("dist/InputPilot.app"), arguments: ["--config", configURL.path])
    wait(0.8)
    focus(running[1]); focus(running[2]); check("memory survives restart", current() == english)
    pilot?.terminate(); wait(0.8)
    var paused = try readConfig()
    paused["paused"] = true
    try JSONSerialization.data(withJSONObject: paused).write(to: configURL, options: .atomic)
    pilot = try open(root.appendingPathComponent("dist/InputPilot.app"), arguments: ["--config", configURL.path])
    wait(0.8)
    select(english)
    focus(running[1]); check("paused does not switch B", current() == english)
    pilot?.terminate(); wait(0.8)
    paused["paused"] = false
    try JSONSerialization.data(withJSONObject: paused).write(to: configURL, options: .atomic)
    pilot = try open(root.appendingPathComponent("dist/InputPilot.app"), arguments: ["--config", configURL.path])
    wait(0.8)
    focus(running[0]); focus(running[1]); check("resume restores switching", current() == chinese)
}
do { try run() } catch { failures += 1; print("FAIL \(error)") }
print("Native integration failures: \(failures)")
exit(failures == 0 ? 0 : 1)

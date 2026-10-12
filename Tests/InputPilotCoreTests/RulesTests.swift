import Foundation
import InputPilotCore

final class RulesTests {
    func testFixedRuleWinsOverRememberedAndDefault() {
        var config = Configuration()
        config.defaultSourceID = "default"
        config.remembered["a"] = "remembered"
        config.rules = [AppRule(id: "a", name: "A", policy: .fixed, inputSourceID: "fixed")]
        expectEqual(config.target(for: "a"), "fixed")
        expectFalse(config.shouldRemember("a"))
    }

    func testRememberAndDefaultPolicies() {
        var config = Configuration()
        config.defaultSourceID = "default"
        config.remembered["a"] = "previous"
        expectEqual(config.target(for: "a"), "previous")
        expectEqual(config.target(for: "b"), "default")
        config.rememberUnconfigured = false
        expectEqual(config.target(for: "a"), "default")
        config.rules = [AppRule(id: "a", name: "A", policy: .remember)]
        expectEqual(config.target(for: "a"), "previous")
        config.rules[0].policy = .globalDefault
        expectEqual(config.target(for: "a"), "default")
        config.defaultSourceID = nil
        expectNil(config.target(for: "a"))
    }

    func testRapidActivationCancelsOldRequest() {
        var config = Configuration()
        config.defaultSourceID = "en"
        var state = SwitchState()
        let a = state.activate(pid: 1, bundleID: "a", configuration: config, currentID: "zh", now: 0)!
        let b = state.activate(pid: 2, bundleID: "b", configuration: config, currentID: "zh", now: 0.1)!
        expectFalse(state.isCurrent(a, frontmostPID: 2))
        expectFalse(state.isCurrent(b, frontmostPID: 1))
        expect(state.isCurrent(b, frontmostPID: 2))
        state.finish(a, now: 1)
        expectEqual(state.pending, b)
    }

    func testProgrammaticChangeCannotBecomeMemory() {
        var config = Configuration()
        config.defaultSourceID = "en"
        var state = SwitchState()
        let request = state.activate(pid: 1, bundleID: "a", configuration: config, currentID: "zh", now: 0)!
        expectFalse(state.canRemember(bundleID: "a", frontmostPID: 1, now: 1, configuration: config))
        state.finish(request, now: 1)
        expectFalse(state.canRemember(bundleID: "a", frontmostPID: 1, now: 1.1, configuration: config))
        expect(state.canRemember(bundleID: "a", frontmostPID: 1, now: 1.3, configuration: config))
        expectFalse(state.canRemember(bundleID: "b", frontmostPID: 2, now: 2, configuration: config))
    }

    func testPauseAndOwnWindowInvalidateWork() {
        var config = Configuration()
        config.defaultSourceID = "en"
        var state = SwitchState()
        let request = state.activate(pid: 1, bundleID: "a", configuration: config, currentID: "zh", now: 0)!
        config.paused = true
        expectNil(state.activate(pid: 1, bundleID: "a", configuration: config, currentID: "zh", now: 1))
        expectFalse(state.isCurrent(request, frontmostPID: 1))
        expectFalse(state.canRemember(bundleID: "a", frontmostPID: 1, now: 2, configuration: config))
        config.paused = false
        expectNil(state.activate(pid: nil, bundleID: nil, configuration: config, currentID: "zh", now: 3))
    }

    func testRetryBudgetIsBoundedAndIndependentPerActivation() {
        var config = Configuration()
        config.defaultSourceID = "en"
        var state = SwitchState()
        var request = state.activate(pid: 1, bundleID: "a", configuration: config, currentID: "zh", now: 0)!
        for expected in [2, 1, 0] {
            request = state.retry(request)!
            expectEqual(request.retriesLeft, expected)
        }
        expectNil(state.retry(request))
        expectEqual(state.activate(pid: 2, bundleID: "b", configuration: config, currentID: "zh", now: 1)?.retriesLeft, 3)
    }

    func testNoUnnecessarySwitchWhenAlreadySelected() {
        var config = Configuration()
        config.defaultSourceID = "en"
        var state = SwitchState()
        expectNil(state.activate(pid: 1, bundleID: "a", configuration: config, currentID: "en", now: 0))
        expectFalse(state.canRemember(bundleID: "a", frontmostPID: 1, now: 0.1, configuration: config))
        expect(state.canRemember(bundleID: "a", frontmostPID: 1, now: 1, configuration: config))
    }

    func testConfigurationRoundTripAndCorruptionPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        try expectEqual(try ConfigurationFile.load(url), Configuration())
        var config = Configuration()
        config.defaultSourceID = "en"
        config.remembered["a"] = "zh"
        config.rules = [AppRule(id: "a", name: "A")]
        try ConfigurationFile.save(config, to: url)
        try expectEqual(try ConfigurationFile.load(url), config)
        let broken = Data("not json".utf8)
        try broken.write(to: url)
        expectThrows(try ConfigurationFile.load(url))
        try expectEqual(try Data(contentsOf: url), broken)
    }

    func testFutureSchemaIsNotSilentlyOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Configuration()
        config.schemaVersion = 2
        try JSONEncoder().encode(config).write(to: url)
        expectThrows(try ConfigurationFile.load(url))
    }
}

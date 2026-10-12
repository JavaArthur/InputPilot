import Foundation

var failures = 0
func expect(_ expression: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    if !expression() { failures += 1; print("FAIL \(file):\(line)") }
}
func expectFalse(_ expression: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    expect(!expression(), file: file, line: line)
}
func expectEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T,
                               file: StaticString = #file, line: UInt = #line) rethrows {
    let first = try left(), second = try right()
    if first != second { failures += 1; print("FAIL \(file):\(line): \(first) != \(second)") }
}
func expectNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) {
    expect(value() == nil, file: file, line: line)
}
func expectThrows<T>(_ body: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try body(); failures += 1; print("FAIL expected throw \(file):\(line)") } catch {}
}
let suite = RulesTests()
let checks: [(String, () throws -> Void)] = [
    ("fixed-rule-precedence", suite.testFixedRuleWinsOverRememberedAndDefault),
    ("remember-and-default", suite.testRememberAndDefaultPolicies),
    ("rapid-activation", suite.testRapidActivationCancelsOldRequest),
    ("programmatic-memory-isolation", suite.testProgrammaticChangeCannotBecomeMemory),
    ("pause-invalidation", suite.testPauseAndOwnWindowInvalidateWork),
    ("bounded-retry", suite.testRetryBudgetIsBoundedAndIndependentPerActivation),
    ("already-selected", suite.testNoUnnecessarySwitchWhenAlreadySelected),
    ("persistence-corruption", suite.testConfigurationRoundTripAndCorruptionPreserved),
    ("future-schema", suite.testFutureSchemaIsNotSilentlyOverwritten)
]
for (name, check) in checks {
    let before = failures
    do { try check() } catch { failures += 1; print("FAIL \(name): \(error)") }
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
print("\(checks.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)

import Foundation

public enum AppPolicy: String, Codable, CaseIterable {
    case fixed, remember, globalDefault
}

public struct AppRule: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var path: String?
    public var policy: AppPolicy
    public var inputSourceID: String?

    public init(id: String, name: String, path: String? = nil,
                policy: AppPolicy = .remember, inputSourceID: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.policy = policy
        self.inputSourceID = inputSourceID
    }
}

public struct Configuration: Codable, Equatable {
    public var schemaVersion = 1
    public var paused = false
    public var rememberUnconfigured = true
    public var defaultSourceID: String?
    public var rules: [AppRule] = []
    public var remembered: [String: String] = [:]
    public init() {}

    public func target(for bundleID: String) -> String? {
        if let rule = rules.first(where: { $0.id == bundleID }) {
            switch rule.policy {
            case .fixed: return rule.inputSourceID
            case .remember: return remembered[bundleID] ?? defaultSourceID
            case .globalDefault: return defaultSourceID
            }
        }
        return (rememberUnconfigured ? remembered[bundleID] : nil) ?? defaultSourceID
    }

    public func shouldRemember(_ bundleID: String) -> Bool {
        if let rule = rules.first(where: { $0.id == bundleID }) {
            return rule.policy == .remember
        }
        return rememberUnconfigured
    }
}

public struct SwitchRequest: Equatable {
    public let generation: Int
    public let pid: Int32
    public let bundleID: String
    public let sourceID: String
    public var retriesLeft: Int
}

public struct SwitchState {
    public private(set) var generation = 0
    public private(set) var activePID: Int32?
    public private(set) var activeBundleID: String?
    public private(set) var pending: SwitchRequest?
    public private(set) var suppressMemoryUntil: TimeInterval = 0
    public init() {}

    public mutating func activate(pid: Int32?, bundleID: String?, configuration: Configuration,
                                  currentID: String?, now: TimeInterval) -> SwitchRequest? {
        generation += 1
        activePID = pid
        activeBundleID = bundleID
        pending = nil
        // Notifications arriving during activation can belong to the previous app or the OS.
        suppressMemoryUntil = now + 0.35
        guard !configuration.paused, let pid, let bundleID,
              let target = configuration.target(for: bundleID), target != currentID else { return nil }
        let request = SwitchRequest(generation: generation, pid: pid, bundleID: bundleID,
                                    sourceID: target, retriesLeft: 3)
        pending = request
        return request
    }

    public func isCurrent(_ request: SwitchRequest, frontmostPID: Int32?) -> Bool {
        pending == request && generation == request.generation && frontmostPID == request.pid
    }

    public mutating func finish(_ request: SwitchRequest, now: TimeInterval) {
        guard pending == request else { return }
        pending = nil
        suppressMemoryUntil = now + 0.25
    }

    public mutating func retry(_ request: SwitchRequest) -> SwitchRequest? {
        guard pending == request, request.retriesLeft > 0 else { return nil }
        var next = request
        next.retriesLeft -= 1
        pending = next
        return next
    }

    public func canRemember(bundleID: String, frontmostPID: Int32?, now: TimeInterval,
                            configuration: Configuration) -> Bool {
        !configuration.paused && pending == nil && now >= suppressMemoryUntil
            && bundleID == activeBundleID && frontmostPID == activePID
            && configuration.shouldRemember(bundleID)
    }
}

public enum ConfigurationError: Error { case unsupportedVersion(Int) }

public enum ConfigurationFile {
    public static func load(_ url: URL) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        guard config.schemaVersion == 1 else { throw ConfigurationError.unsupportedVersion(config.schemaVersion) }
        return config
    }

    public static func save(_ configuration: Configuration, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}

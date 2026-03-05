import Foundation

public enum ListenerProtocol: String, Codable, Sendable {
    case tcp
}

public enum ListenerFamily: String, Codable, Sendable, Comparable {
    case ipv4
    case ipv6

    public static func < (lhs: ListenerFamily, rhs: ListenerFamily) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Listener: Codable, Sendable, Equatable, Comparable {
    public let proto: ListenerProtocol
    public let port: Int
    public let bindAddress: String
    public let family: ListenerFamily
    public let pid: Int
    public let processName: String
    public let commandLine: String?
    public let cwd: String?
    public let cpuPercent: Double?
    public let memBytes: UInt64?
    public let requiresAdminToKill: Bool?

    public init(
        proto: ListenerProtocol,
        port: Int,
        bindAddress: String,
        family: ListenerFamily,
        pid: Int,
        processName: String,
        commandLine: String? = nil,
        cwd: String? = nil,
        cpuPercent: Double? = nil,
        memBytes: UInt64? = nil,
        requiresAdminToKill: Bool? = nil
    ) {
        self.proto = proto
        self.port = port
        self.bindAddress = bindAddress
        self.family = family
        self.pid = pid
        self.processName = processName
        self.commandLine = commandLine
        self.cwd = cwd
        self.cpuPercent = cpuPercent
        self.memBytes = memBytes
        self.requiresAdminToKill = requiresAdminToKill
    }

    public static func < (lhs: Listener, rhs: Listener) -> Bool {
        if lhs.port != rhs.port {
            return lhs.port < rhs.port
        }

        if lhs.pid != rhs.pid {
            return lhs.pid < rhs.pid
        }

        return lhs.family < rhs.family
    }
}

public struct ListenerSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let listeners: [Listener]

    public init(generatedAt: Date = Date(), listeners: [Listener]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.listeners = listeners.sorted()
    }
}

public enum SinkSignal: String, Codable, Sendable {
    case term
    case kill
}

public enum SinkResult: Codable, Sendable, Equatable {
    case terminated
    case notFound
    case requiresAdmin
    case systemError(String)
}

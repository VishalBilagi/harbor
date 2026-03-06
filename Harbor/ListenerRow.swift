import Foundation
import PortKit

struct ListenerRow: Identifiable, Equatable {
    enum BindTone: Equatable {
        case neutral
        case localhost
        case wildcard
        case protected
    }

    private struct GroupKey: Hashable {
        let port: Int
        let pid: Int
        let processName: String
    }

    let port: Int
    let pid: Int
    let processName: String
    let bindAddresses: [String]
    let families: [ListenerFamily]
    let commandLine: String?
    let cwd: String?
    let cpuPercent: Double?
    let memBytes: UInt64?
    let requiresAdminToKill: Bool

    var id: String {
        "\(port)-\(pid)-\(processName)"
    }

    var portText: String {
        String(port)
    }

    var bindSummary: String {
        Self.summarize(bindAddresses, maxVisible: 2)
    }

    var familySummary: String {
        let labels = families.map(Self.familyLabel)
        return labels.joined(separator: "+")
    }

    var bindTone: BindTone {
        if requiresAdminToKill {
            return .protected
        }

        if bindAddresses.contains(where: Self.isWildcardBindAddress) {
            return .wildcard
        }

        if !bindAddresses.isEmpty && bindAddresses.allSatisfy(Self.isLoopbackBindAddress) {
            return .localhost
        }

        return .neutral
    }

    var tickerCommandText: String? {
        commandLine.flatMap(Self.normalized).flatMap(Self.compactCommand)
    }

    var tickerCwdText: String? {
        cwd.flatMap(Self.normalized).map(Self.compactPath)
    }

    var tickerText: String {
        let command = tickerCommandText
        let formattedCwd = tickerCwdText

        switch (command, formattedCwd) {
        case let (command?, formattedCwd?):
            return "\(command) • \(formattedCwd)"
        case let (command?, nil):
            return command
        case let (nil, formattedCwd?):
            return formattedCwd
        case (nil, nil):
            return "No command line or cwd metadata"
        }
    }

    var statsText: String? {
        var parts: [String] = []

        if let cpuPercent {
            parts.append(
                "CPU \(cpuPercent.formatted(.number.precision(.fractionLength(1))))%"
            )
        }

        if let memBytes {
            parts.append("MEM \(Self.formatMemory(memBytes))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    func matches(query: String) -> Bool {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }

        guard !tokens.isEmpty else {
            return true
        }

        return tokens.allSatisfy { token in
            String(port).contains(token) || String(pid).contains(token) || searchBlob.contains(token)
        }
    }

    static func grouped(from listeners: [Listener]) -> [ListenerRow] {
        guard !listeners.isEmpty else {
            return []
        }

        let grouped = Dictionary(grouping: listeners) { listener in
            GroupKey(
                port: listener.port,
                pid: listener.pid,
                processName: listener.processName
            )
        }

        let rows = grouped.map { key, listeners in
            let bindAddresses = Array(Set(listeners.map(\.bindAddress))).sorted()
            let families = Array(Set(listeners.map(\.family))).sorted()
            let requiresAdminToKill = listeners.contains { $0.requiresAdminToKill ?? true }
            let commandLine = listeners.lazy.compactMap(\.commandLine).first
            let cwd = listeners.lazy.compactMap(\.cwd).first
            let cpuPercent = listeners.lazy.compactMap(\.cpuPercent).max()
            let memBytes = listeners.lazy.compactMap(\.memBytes).max()

            return ListenerRow(
                port: key.port,
                pid: key.pid,
                processName: key.processName,
                bindAddresses: bindAddresses,
                families: families,
                commandLine: commandLine,
                cwd: cwd,
                cpuPercent: cpuPercent,
                memBytes: memBytes,
                requiresAdminToKill: requiresAdminToKill
            )
        }

        return rows.sorted { lhs, rhs in
            if lhs.port != rhs.port {
                return lhs.port < rhs.port
            }

            if lhs.pid != rhs.pid {
                return lhs.pid < rhs.pid
            }

            return lhs.processName.localizedCaseInsensitiveCompare(rhs.processName) == .orderedAscending
        }
    }

    private var searchBlob: String {
        [
            processName,
            commandLine ?? "",
            cwd ?? "",
            bindAddresses.joined(separator: " "),
            familySummary
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private static func summarize(_ values: [String], maxVisible: Int) -> String {
        guard values.count > maxVisible else {
            return values.joined(separator: ", ")
        }

        let leading = values.prefix(maxVisible).joined(separator: ", ")
        return "\(leading), +\(values.count - maxVisible)"
    }

    private nonisolated static func familyLabel(_ family: ListenerFamily) -> String {
        switch family {
        case .ipv4:
            return "IPv4"
        case .ipv6:
            return "IPv6"
        }
    }

    private nonisolated static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func compactPath(_ path: String) -> String {
        let homeDirectory = NSHomeDirectory()
        if path == homeDirectory {
            return "~"
        }

        let homePrefix = homeDirectory + "/"
        guard path.hasPrefix(homePrefix) else {
            return compactApplicationsPath(path)
        }

        return compactApplicationsPath("~/" + path.dropFirst(homePrefix.count))
    }

    private nonisolated static func compactCommand(_ commandLine: String) -> String? {
        let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executableToken = tokens.first else {
            return nil
        }

        let executable = compactExecutable(executableToken)
        let args = tokens.dropFirst().prefix(2).map(compactCommandArg)
        let hasMoreArgs = tokens.count > 3

        var parts = [executable]
        parts.append(contentsOf: args)
        if hasMoreArgs {
            parts.append("…")
        }

        return parts.joined(separator: " ")
    }

    private nonisolated static func compactExecutable(_ token: String) -> String {
        let cleaned = compactCommandArg(token)
        if cleaned.hasPrefix("/") || cleaned.hasPrefix("~/") {
            return URL(fileURLWithPath: cleaned).lastPathComponent
        }
        return cleaned
    }

    private nonisolated static func compactCommandArg(_ token: String) -> String {
        let strippedToken = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if strippedToken.hasPrefix("/") || strippedToken.hasPrefix("~/") {
            return compactPath(strippedToken)
        }
        return strippedToken
    }

    private nonisolated static func compactApplicationsPath(_ path: String) -> String {
        let prefix = "/Applications/"
        guard path.hasPrefix(prefix) else {
            return path
        }

        let components = path.split(separator: "/")
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return path
        }

        return components[appIndex...].joined(separator: "/")
    }

    private nonisolated static func isWildcardBindAddress(_ address: String) -> Bool {
        switch address.lowercased() {
        case "*", "0.0.0.0", "::", "[::]":
            return true
        default:
            return false
        }
    }

    private nonisolated static func isLoopbackBindAddress(_ address: String) -> Bool {
        switch address.lowercased() {
        case "127.0.0.1", "::1", "[::1]", "localhost":
            return true
        default:
            return false
        }
    }

    private nonisolated static func formatMemory(_ memBytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(memBytes))
    }
}

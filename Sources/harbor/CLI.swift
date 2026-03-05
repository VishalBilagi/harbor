import Darwin
import Foundation
import PortKit

enum CLIParseError: Error, Equatable {
    case message(String)
}

extension CLIParseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

struct ListDisplayOptions: Equatable {
    var wide = false
    var showCommandLine = true
    var showCwd = true
}

enum HarborCommand: Equatable {
    case help
    case list(display: ListDisplayOptions, json: Bool)
    case who(port: Int, display: ListDisplayOptions, json: Bool)
    case watch(interval: TimeInterval, jsonl: Bool)
}

enum HarborCLIParser {
    static func parse(arguments: [String]) throws -> HarborCommand {
        let args = Array(arguments.dropFirst())

        guard let first = args.first else {
            return .list(display: ListDisplayOptions(), json: false)
        }

        switch first {
        case "help", "-h", "--help":
            return .help
        case "list", "ls":
            return try parseList(arguments: Array(args.dropFirst()))
        case "who":
            return try parseWho(arguments: Array(args.dropFirst()))
        case "watch":
            return try parseWatch(arguments: Array(args.dropFirst()))
        default:
            if first.hasPrefix("-") {
                return try parseList(arguments: args)
            }

            throw CLIParseError.message("Unknown command '\(first)'.")
        }
    }

    private static func parseList(arguments: [String]) throws -> HarborCommand {
        var display = ListDisplayOptions()
        var json = false

        for argument in arguments {
            switch argument {
            case "--json":
                json = true
            case "--wide":
                display.wide = true
            case "--no-cmd":
                display.showCommandLine = false
            case "--no-cwd":
                display.showCwd = false
            case "-h", "--help":
                return .help
            default:
                throw CLIParseError.message("Unknown option '\(argument)' for 'list'.")
            }
        }

        return .list(display: display, json: json)
    }

    private static func parseWho(arguments: [String]) throws -> HarborCommand {
        var display = ListDisplayOptions()
        var json = false
        var port: Int?

        for argument in arguments {
            switch argument {
            case "--json":
                json = true
            case "--wide":
                display.wide = true
            case "--no-cmd":
                display.showCommandLine = false
            case "--no-cwd":
                display.showCwd = false
            case "-h", "--help":
                return .help
            default:
                if argument.hasPrefix("-") {
                    throw CLIParseError.message("Unknown option '\(argument)' for 'who'.")
                }

                if port != nil {
                    throw CLIParseError.message("Unexpected extra argument '\(argument)' for 'who'.")
                }

                port = try parsePort(argument)
            }
        }

        guard let port else {
            throw CLIParseError.message("Missing required <port> for 'who'.")
        }

        return .who(port: port, display: display, json: json)
    }

    private static func parseWatch(arguments: [String]) throws -> HarborCommand {
        var interval: TimeInterval = 2
        var jsonl = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--interval":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError.message("Missing value for '--interval'.")
                }
                interval = try parseInterval(arguments[index])
            case "--jsonl":
                jsonl = true
            case "-h", "--help":
                return .help
            default:
                throw CLIParseError.message("Unknown option '\(argument)' for 'watch'.")
            }

            index += 1
        }

        guard jsonl else {
            throw CLIParseError.message("The 'watch' command requires '--jsonl'.")
        }

        return .watch(interval: interval, jsonl: jsonl)
    }

    private static func parsePort(_ value: String) throws -> Int {
        guard let port = Int(value), (1...65_535).contains(port) else {
            throw CLIParseError.message("Invalid port '\(value)'. Expected an integer from 1 to 65535.")
        }

        return port
    }

    private static func parseInterval(_ value: String) throws -> TimeInterval {
        guard let interval = TimeInterval(value), interval > 0 else {
            throw CLIParseError.message("Invalid interval '\(value)'. Expected a number greater than 0.")
        }

        return interval
    }
}

struct HarborCLI {
    private let portKit: PortKit
    private let arguments: [String]
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let terminalWidthProvider: @Sendable () -> Int?
    private let sleep: @Sendable (TimeInterval) -> Void

    init(
        portKit: PortKit = PortKit(),
        arguments: [String] = CommandLine.arguments,
        stdout: FileHandle = .standardOutput,
        stderr: FileHandle = .standardError,
        terminalWidthProvider: @escaping @Sendable () -> Int? = { TerminalWidthDetector.current() },
        sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.portKit = portKit
        self.arguments = arguments
        self.stdout = stdout
        self.stderr = stderr
        self.terminalWidthProvider = terminalWidthProvider
        self.sleep = sleep
    }

    func run() -> Int {
        do {
            let command = try HarborCLIParser.parse(arguments: arguments)
            return try execute(command)
        } catch let parseError as CLIParseError {
            write("\(parseError.localizedDescription)\n\n\(Usage.text)\n", to: stderr)
            return 2
        } catch {
            write("Failed to scan listeners: \(error.localizedDescription)\n", to: stderr)
            return 1
        }
    }

    private func execute(_ command: HarborCommand) throws -> Int {
        switch command {
        case .help:
            write("\(Usage.text)\n", to: stdout)
            return 0
        case let .list(display, json):
            return try runList(display: display, json: json)
        case let .who(port, display, json):
            return try runWho(port: port, display: display, json: json)
        case let .watch(interval, jsonl):
            return try runWatch(interval: interval, jsonl: jsonl)
        }
    }

    private func runList(display: ListDisplayOptions, json: Bool) throws -> Int {
        let snapshot = try portKit.snapshot()

        if json {
            try writeJSON(snapshot)
            return 0
        }

        guard !snapshot.listeners.isEmpty else {
            write("No listening TCP ports found.\n", to: stdout)
            return 0
        }

        let table = ListenerTableRenderer.render(
            listeners: snapshot.listeners,
            display: display,
            terminalWidth: effectiveWidth(isWide: display.wide)
        )
        write("\(table)\n", to: stdout)
        return 0
    }

    private func runWho(port: Int, display: ListDisplayOptions, json: Bool) throws -> Int {
        let snapshot = try portKit.snapshot()
        let matchingListeners = snapshot.listeners.filter { $0.port == port }
        let filteredSnapshot = ListenerSnapshot(generatedAt: snapshot.generatedAt, listeners: matchingListeners)

        if json {
            try writeJSON(filteredSnapshot)
            return 0
        }

        guard !matchingListeners.isEmpty else {
            write("No listeners found on port \(port).\n", to: stdout)
            return 0
        }

        let table = ListenerTableRenderer.render(
            listeners: matchingListeners,
            display: display,
            terminalWidth: effectiveWidth(isWide: display.wide)
        )
        write("\(table)\n", to: stdout)
        return 0
    }

    private func runWatch(interval: TimeInterval, jsonl: Bool) throws -> Int {
        guard jsonl else {
            throw CLIParseError.message("The 'watch' command requires '--jsonl'.")
        }

        while true {
            try writeJSON(portKit.snapshot())
            sleep(interval)
        }
    }

    private func writeJSON(_ snapshot: ListenerSnapshot) throws {
        let line = try SnapshotJSONEncoder.encode(snapshot)
        write("\(line)\n", to: stdout)
    }

    private func write(_ value: String, to handle: FileHandle) {
        handle.write(Data(value.utf8))
    }

    private func effectiveWidth(isWide: Bool) -> Int {
        let measured = terminalWidthProvider() ?? 120

        if isWide {
            return max(measured, 180)
        }

        return measured
    }
}

enum SnapshotJSONEncoder {
    private struct SnapshotEnvelope: Encodable {
        let schemaVersion: Int
        let generatedAt: Date
        let listeners: [ListenerEnvelope]

        init(snapshot: ListenerSnapshot) {
            self.schemaVersion = snapshot.schemaVersion
            self.generatedAt = snapshot.generatedAt
            self.listeners = snapshot.listeners.map(ListenerEnvelope.init)
        }
    }

    private struct ListenerEnvelope: Encodable {
        let proto: ListenerProtocol
        let port: Int
        let bindAddress: String
        let family: ListenerFamily
        let pid: Int
        let processName: String
        let commandLine: String?
        let cwd: String?
        let cpuPercent: Double?
        let memBytes: UInt64?
        let requiresAdminToKill: Bool?

        init(listener: Listener) {
            self.proto = listener.proto
            self.port = listener.port
            self.bindAddress = listener.bindAddress
            self.family = listener.family
            self.pid = listener.pid
            self.processName = listener.processName
            self.commandLine = listener.commandLine
            self.cwd = listener.cwd
            self.cpuPercent = listener.cpuPercent
            self.memBytes = listener.memBytes
            self.requiresAdminToKill = listener.requiresAdminToKill
        }

        enum CodingKeys: String, CodingKey {
            case proto
            case port
            case bindAddress
            case family
            case pid
            case processName
            case commandLine
            case cwd
            case cpuPercent
            case memBytes
            case requiresAdminToKill
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(proto, forKey: .proto)
            try container.encode(port, forKey: .port)
            try container.encode(bindAddress, forKey: .bindAddress)
            try container.encode(family, forKey: .family)
            try container.encode(pid, forKey: .pid)
            try container.encode(processName, forKey: .processName)

            if let commandLine {
                try container.encode(commandLine, forKey: .commandLine)
            } else {
                try container.encodeNil(forKey: .commandLine)
            }

            if let cwd {
                try container.encode(cwd, forKey: .cwd)
            } else {
                try container.encodeNil(forKey: .cwd)
            }

            if let cpuPercent {
                try container.encode(cpuPercent, forKey: .cpuPercent)
            } else {
                try container.encodeNil(forKey: .cpuPercent)
            }

            if let memBytes {
                try container.encode(memBytes, forKey: .memBytes)
            } else {
                try container.encodeNil(forKey: .memBytes)
            }

            if let requiresAdminToKill {
                try container.encode(requiresAdminToKill, forKey: .requiresAdminToKill)
            } else {
                try container.encodeNil(forKey: .requiresAdminToKill)
            }
        }
    }

    static func encode(_ snapshot: ListenerSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(SnapshotEnvelope(snapshot: snapshot))

        guard let line = String(data: data, encoding: .utf8) else {
            throw CLIParseError.message("Failed to encode JSON output as UTF-8.")
        }

        return line
    }
}

enum ListenerTableRenderer {
    private struct Column {
        let header: String
        let values: [String]
        let isFlexible: Bool
        let minWidth: Int
    }

    private static let separator = "  "

    static func render(listeners: [Listener], display: ListDisplayOptions, terminalWidth: Int) -> String {
        let sortedListeners = listeners.sorted()
        let columns = buildColumns(listeners: sortedListeners, display: display)
        let widths = fitWidths(columns: columns, maxWidth: max(terminalWidth, 40))

        var lines: [String] = []
        lines.append(row(values: columns.map(\.header), widths: widths))
        lines.append(row(values: widths.map { String(repeating: "-", count: $0) }, widths: widths))

        for rowIndex in sortedListeners.indices {
            let values = columns.map { $0.values[rowIndex] }
            lines.append(row(values: values, widths: widths))
        }

        return lines.joined(separator: "\n")
    }

    private static func buildColumns(listeners: [Listener], display: ListDisplayOptions) -> [Column] {
        var columns: [Column] = [
            Column(header: "PORT", values: listeners.map { "\($0.port)" }, isFlexible: false, minWidth: 4),
            Column(header: "PROC", values: listeners.map(\.processName), isFlexible: false, minWidth: 4),
            Column(header: "PID", values: listeners.map { "\($0.pid)" }, isFlexible: false, minWidth: 3),
            Column(header: "BIND", values: listeners.map(\.bindAddress), isFlexible: false, minWidth: 4),
            Column(
                header: "FAM",
                values: listeners.map { $0.family == .ipv4 ? "IPv4" : "IPv6" },
                isFlexible: false,
                minWidth: 4
            ),
        ]

        if display.showCommandLine {
            columns.append(
                Column(
                    header: "CMD",
                    values: listeners.map { $0.commandLine ?? "-" },
                    isFlexible: true,
                    minWidth: 12
                )
            )
        }

        if display.showCwd {
            columns.append(
                Column(
                    header: "CWD",
                    values: listeners.map { $0.cwd ?? "-" },
                    isFlexible: true,
                    minWidth: 12
                )
            )
        }

        return columns
    }

    private static func fitWidths(columns: [Column], maxWidth: Int) -> [Int] {
        var widths = columns.map { column in
            let maxValueWidth = column.values.map(\.count).max() ?? 0
            return max(column.header.count, maxValueWidth)
        }

        let minimumWidths = columns.map { column in
            max(column.minWidth, column.header.count)
        }

        func currentTotalWidth() -> Int {
            widths.reduce(0, +) + (max(columns.count - 1, 0) * separator.count)
        }

        func reduceWidth(candidateIndices: [Int]) -> Bool {
            guard let index = candidateIndices
                .filter({ widths[$0] > minimumWidths[$0] })
                .max(by: { widths[$0] < widths[$1] }) else {
                return false
            }

            widths[index] -= 1
            return true
        }

        let flexibleIndices = columns.indices.filter { columns[$0].isFlexible }
        let allIndices = Array(columns.indices)

        while currentTotalWidth() > maxWidth {
            if reduceWidth(candidateIndices: flexibleIndices) {
                continue
            }

            if reduceWidth(candidateIndices: allIndices) {
                continue
            }

            break
        }

        return widths
    }

    private static func row(values: [String], widths: [Int]) -> String {
        zip(values, widths)
            .map { value, width in pad(value, to: width) }
            .joined(separator: separator)
    }

    private static func pad(_ value: String, to width: Int) -> String {
        let truncated = truncate(value, to: width)
        let padding = max(width - truncated.count, 0)

        return truncated + String(repeating: " ", count: padding)
    }

    private static func truncate(_ value: String, to width: Int) -> String {
        guard value.count > width else {
            return value
        }

        if width <= 0 {
            return ""
        }

        if width <= 3 {
            return String(value.prefix(width))
        }

        return String(value.prefix(width - 3)) + "..."
    }
}

enum TerminalWidthDetector {
    static func current() -> Int? {
        guard isatty(STDOUT_FILENO) == 1 else {
            return nil
        }

        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else {
            return nil
        }

        return Int(size.ws_col)
    }
}

enum Usage {
    static let text = """
    Usage:
      harbor list [--json] [--wide] [--no-cmd] [--no-cwd]
      harbor who <port> [--json] [--wide] [--no-cmd] [--no-cwd]
      harbor watch [--interval <seconds>] --jsonl

    Commands:
      list        Show active TCP listeners.
      who         Filter listeners by port.
      watch       Stream snapshots continuously as JSONL.

    Notes:
      'ls' is a hidden alias for 'list'.
    """
}

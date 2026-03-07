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

enum CLIExitCode: Int {
    case success = 0
    case runtimeFailure = 1
    case usageOrAmbiguityFailure = 2
    case freePort = 3
    case requiresAdmin = 4
    case targetNotFound = 5
}

struct ListDisplayOptions: Equatable {
    var wide = false
    var showCommandLine = true
    var showCwd = true
}

enum SinkTarget: Equatable {
    case port(Int)
    case pid(Int)
}

struct SinkOptions: Equatable {
    let target: SinkTarget
    let force: Bool
    let assumeYes: Bool
}

enum HarborBuildInfo {
    static let version = "0.2.2" /* x-release-please-version */
}

enum HarborCommand: Equatable {
    case help
    case version(json: Bool)
    case list(display: ListDisplayOptions, json: Bool)
    case who(port: Int, display: ListDisplayOptions, json: Bool)
    case watch(interval: TimeInterval, jsonl: Bool)
    case sink(options: SinkOptions)
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
        case "version":
            return try parseVersion(arguments: Array(args.dropFirst()))
        case "--version":
            return .version(json: false)
        case "list", "ls":
            return try parseList(arguments: Array(args.dropFirst()))
        case "who":
            return try parseWho(arguments: Array(args.dropFirst()))
        case "watch":
            return try parseWatch(arguments: Array(args.dropFirst()))
        case "sink", "kill":
            return try parseSink(arguments: Array(args.dropFirst()))
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

    private static func parseVersion(arguments: [String]) throws -> HarborCommand {
        var json = false

        for argument in arguments {
            switch argument {
            case "--json":
                json = true
            case "-h", "--help":
                return .help
            default:
                throw CLIParseError.message("Unknown option '\(argument)' for 'version'.")
            }
        }

        return .version(json: json)
    }

    private static func parseSink(arguments: [String]) throws -> HarborCommand {
        var force = false
        var assumeYes = false
        var requestedPID: Int?
        var requestedPort: Int?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--force":
                force = true
            case "--yes":
                assumeYes = true
            case "--pid":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError.message("Missing value for '--pid'.")
                }

                if requestedPID != nil {
                    throw CLIParseError.message("Duplicate '--pid' option for 'sink'.")
                }

                requestedPID = try parsePID(arguments[index])
            case "-h", "--help":
                return .help
            default:
                if argument.hasPrefix("-") {
                    throw CLIParseError.message("Unknown option '\(argument)' for 'sink'.")
                }

                if requestedPort != nil {
                    throw CLIParseError.message("Unexpected extra argument '\(argument)' for 'sink'.")
                }

                requestedPort = try parsePort(argument)
            }

            index += 1
        }

        let target: SinkTarget
        if let requestedPID {
            if requestedPort != nil {
                throw CLIParseError.message("Specify either <port> or '--pid <pid>' for 'sink', not both.")
            }
            target = .pid(requestedPID)
        } else if let requestedPort {
            target = .port(requestedPort)
        } else {
            throw CLIParseError.message("Missing target for 'sink'. Provide <port> or '--pid <pid>'.")
        }

        return .sink(options: SinkOptions(target: target, force: force, assumeYes: assumeYes))
    }

    private static func parsePort(_ value: String) throws -> Int {
        guard let port = Int(value), (1...65_535).contains(port) else {
            throw CLIParseError.message("Invalid port '\(value)'. Expected an integer from 1 to 65535.")
        }

        return port
    }

    private static func parsePID(_ value: String) throws -> Int {
        guard let pid = Int(value), (1...Int(Int32.max)).contains(pid) else {
            throw CLIParseError.message("Invalid pid '\(value)'. Expected an integer greater than 0.")
        }

        return pid
    }

    private static func parseInterval(_ value: String) throws -> TimeInterval {
        guard let interval = TimeInterval(value), interval > 0 else {
            throw CLIParseError.message("Invalid interval '\(value)'. Expected a number greater than 0.")
        }

        return interval
    }
}

struct SinkCandidate: Equatable {
    let pid: Int
    let processName: String
    let listeners: [Listener]

    var bindSummary: String {
        SinkResolver.bindSummary(listeners: listeners)
    }

    var ticker: String {
        SinkResolver.ticker(listeners: listeners)
    }

    var requiresAdminToKill: Bool? {
        if listeners.contains(where: { $0.requiresAdminToKill == true }) {
            return true
        }

        if listeners.contains(where: { $0.requiresAdminToKill == false }) {
            return false
        }

        return nil
    }
}

enum PortSinkResolution: Equatable {
    case freePort
    case unambiguous(SinkCandidate)
    case ambiguous([SinkCandidate])
}

enum SinkResolver {
    static func resolvePort(port: Int, listeners: [Listener]) -> PortSinkResolution {
        let matchingListeners = listeners.filter { $0.port == port }

        guard !matchingListeners.isEmpty else {
            return .freePort
        }

        let candidates = candidates(from: matchingListeners)
        if candidates.count == 1, let candidate = candidates.first {
            return .unambiguous(candidate)
        }

        return .ambiguous(candidates)
    }

    static func candidateForPID(pid: Int, listeners: [Listener]) -> SinkCandidate? {
        let matching = listeners
            .filter { $0.pid == pid }
            .sorted()

        guard !matching.isEmpty else {
            return nil
        }

        let processName = matching.first?.processName ?? "pid \(pid)"
        return SinkCandidate(pid: pid, processName: processName, listeners: matching)
    }

    static func candidates(from listeners: [Listener]) -> [SinkCandidate] {
        let listenersByPID = Dictionary(grouping: listeners) { $0.pid }

        return listenersByPID
            .keys
            .sorted()
            .compactMap { pid in
                guard let matchingListeners = listenersByPID[pid] else {
                    return nil
                }

                let sortedListeners = matchingListeners.sorted()
                let processName = sortedListeners.first?.processName ?? "pid \(pid)"
                return SinkCandidate(pid: pid, processName: processName, listeners: sortedListeners)
            }
    }

    static func bindSummary(listeners: [Listener]) -> String {
        guard !listeners.isEmpty else {
            return "-"
        }

        let listenersByPort = Dictionary(grouping: listeners) { $0.port }
        let summaries = listenersByPort
            .keys
            .sorted()
            .map { port in
                let matches = listenersByPort[port] ?? []
                let addresses = Array(Set(matches.map(\.bindAddress))).sorted()
                let familySummary = familySummaryText(families: Set(matches.map(\.family)))
                return "\(addresses.joined(separator: ",")):\(port) \(familySummary)"
            }

        return summaries.joined(separator: "; ")
    }

    static func ticker(listeners: [Listener]) -> String {
        let commandLine = listeners
            .compactMap(\.commandLine)
            .map(normalizeSingleLine)
            .first { !$0.isEmpty }

        let cwd = listeners
            .compactMap(\.cwd)
            .map(normalizeSingleLine)
            .first { !$0.isEmpty }

        switch (commandLine, cwd) {
        case let (.some(commandLine), .some(cwd)):
            return "\(commandLine) | \(cwd)"
        case let (.some(commandLine), .none):
            return commandLine
        case let (.none, .some(cwd)):
            return cwd
        case (.none, .none):
            return "-"
        }
    }

    private static func familySummaryText(families: Set<ListenerFamily>) -> String {
        let hasIPv4 = families.contains(.ipv4)
        let hasIPv6 = families.contains(.ipv6)

        if hasIPv4 && hasIPv6 {
            return "v4+v6"
        }

        if hasIPv4 {
            return "v4"
        }

        return "v6"
    }

    private static func normalizeSingleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

struct HarborCLI {
    private let arguments: [String]
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let terminalWidthProvider: @Sendable () -> Int?
    private let sleep: @Sendable (TimeInterval) -> Void
    private let snapshotProvider: @Sendable () throws -> ListenerSnapshot
    private let sinkProvider: @Sendable (_ pid: Int, _ signal: SinkSignal) -> SinkResult
    private let isInteractiveTTYProvider: @Sendable () -> Bool
    private let readInputLine: @Sendable () -> String?

    init(
        portKit: PortKit = PortKit(),
        arguments: [String] = CommandLine.arguments,
        stdout: FileHandle = .standardOutput,
        stderr: FileHandle = .standardError,
        terminalWidthProvider: @escaping @Sendable () -> Int? = { TerminalWidthDetector.current() },
        sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        isInteractiveTTYProvider: @escaping @Sendable () -> Bool = { TerminalInteractivityDetector.current() },
        readInputLine: @escaping @Sendable () -> String? = { readLine(strippingNewline: true) },
        snapshotProvider: (@Sendable () throws -> ListenerSnapshot)? = nil,
        sinkProvider: (@Sendable (_ pid: Int, _ signal: SinkSignal) -> SinkResult)? = nil
    ) {
        self.arguments = arguments
        self.stdout = stdout
        self.stderr = stderr
        self.terminalWidthProvider = terminalWidthProvider
        self.sleep = sleep
        self.isInteractiveTTYProvider = isInteractiveTTYProvider
        self.readInputLine = readInputLine

        let resolvedPortKit = portKit
        self.snapshotProvider = snapshotProvider ?? { try resolvedPortKit.snapshot() }
        self.sinkProvider = sinkProvider ?? { pid, signal in
            resolvedPortKit.sink(pid: pid, signal: signal)
        }
    }

    func run() -> Int {
        do {
            let command = try HarborCLIParser.parse(arguments: arguments)
            return try execute(command)
        } catch let parseError as CLIParseError {
            write("\(parseError.localizedDescription)\n\n\(Usage.text)\n", to: stderr)
            return CLIExitCode.usageOrAmbiguityFailure.rawValue
        } catch {
            write("Failed to scan listeners: \(error.localizedDescription)\n", to: stderr)
            return CLIExitCode.runtimeFailure.rawValue
        }
    }

    private func execute(_ command: HarborCommand) throws -> Int {
        switch command {
        case .help:
            write("\(Usage.text)\n", to: stdout)
            return CLIExitCode.success.rawValue
        case let .version(json):
            return runVersion(json: json)
        case let .list(display, json):
            return try runList(display: display, json: json)
        case let .who(port, display, json):
            return try runWho(port: port, display: display, json: json)
        case let .watch(interval, jsonl):
            return try runWatch(interval: interval, jsonl: jsonl)
        case let .sink(options):
            return try runSink(options: options)
        }
    }

    private func runVersion(json: Bool) -> Int {
        if json {
            write("{\"version\":\"\(HarborBuildInfo.version)\"}\n", to: stdout)
        } else {
            write("\(HarborBuildInfo.version)\n", to: stdout)
        }

        return CLIExitCode.success.rawValue
    }

    private func runList(display: ListDisplayOptions, json: Bool) throws -> Int {
        let snapshot = try snapshotProvider()

        if json {
            try writeJSON(snapshot)
            return CLIExitCode.success.rawValue
        }

        guard !snapshot.listeners.isEmpty else {
            write("No listening TCP ports found.\n", to: stdout)
            return CLIExitCode.success.rawValue
        }

        let table = ListenerTableRenderer.render(
            listeners: snapshot.listeners,
            display: display,
            terminalWidth: effectiveWidth(isWide: display.wide)
        )
        write("\(table)\n", to: stdout)
        return CLIExitCode.success.rawValue
    }

    private func runWho(port: Int, display: ListDisplayOptions, json: Bool) throws -> Int {
        let snapshot = try snapshotProvider()
        let matchingListeners = snapshot.listeners.filter { $0.port == port }
        let filteredSnapshot = ListenerSnapshot(generatedAt: snapshot.generatedAt, listeners: matchingListeners)

        if json {
            try writeJSON(filteredSnapshot)
            return CLIExitCode.success.rawValue
        }

        guard !matchingListeners.isEmpty else {
            write("No listeners found on port \(port).\n", to: stdout)
            return CLIExitCode.success.rawValue
        }

        let table = ListenerTableRenderer.render(
            listeners: matchingListeners,
            display: display,
            terminalWidth: effectiveWidth(isWide: display.wide)
        )
        write("\(table)\n", to: stdout)
        return CLIExitCode.success.rawValue
    }

    private func runWatch(interval: TimeInterval, jsonl: Bool) throws -> Int {
        guard jsonl else {
            throw CLIParseError.message("The 'watch' command requires '--jsonl'.")
        }

        while true {
            try writeJSON(snapshotProvider())
            sleep(interval)
        }
    }

    private func runSink(options: SinkOptions) throws -> Int {
        let snapshot = try snapshotProvider()
        let signal: SinkSignal = options.force ? .kill : .term

        let selectedCandidate: SinkCandidate
        let targetDescription: String

        switch options.target {
        case let .port(port):
            switch SinkResolver.resolvePort(port: port, listeners: snapshot.listeners) {
            case .freePort:
                write("Port \(port) is free; nothing to sink.\n", to: stdout)
                return CLIExitCode.freePort.rawValue
            case let .unambiguous(candidate):
                selectedCandidate = candidate
                targetDescription = "port \(port)"
            case let .ambiguous(candidates):
                if options.assumeYes || !isInteractiveTTYProvider() {
                    let pidList = candidates.map { String($0.pid) }.joined(separator: ", ")
                    write(
                        "Port \(port) maps to multiple processes (\(pidList)). Rerun with '--pid <pid>'.\n",
                        to: stderr
                    )
                    return CLIExitCode.usageOrAmbiguityFailure.rawValue
                }

                guard let chosenCandidate = promptForCandidateSelection(port: port, candidates: candidates) else {
                    write("Sink cancelled.\n", to: stderr)
                    return CLIExitCode.usageOrAmbiguityFailure.rawValue
                }

                selectedCandidate = chosenCandidate
                targetDescription = "port \(port)"
            }
        case let .pid(pid):
            selectedCandidate = SinkResolver.candidateForPID(pid: pid, listeners: snapshot.listeners)
                ?? SinkCandidate(pid: pid, processName: "pid \(pid)", listeners: [])
            targetDescription = "pid \(pid)"
        }

        if selectedCandidate.requiresAdminToKill == true {
            write(
                "PID \(selectedCandidate.pid) requires admin privileges. Harbor will not escalate privileges.\n",
                to: stderr
            )
            return CLIExitCode.requiresAdmin.rawValue
        }

        if !options.assumeYes {
            guard isInteractiveTTYProvider() else {
                write("Refusing to prompt in non-interactive mode. Rerun with '--yes'.\n", to: stderr)
                return CLIExitCode.usageOrAmbiguityFailure.rawValue
            }

            let confirmed = promptForConfirmation(
                candidate: selectedCandidate,
                signal: signal,
                targetDescription: targetDescription
            )

            guard confirmed else {
                write("Sink cancelled.\n", to: stderr)
                return CLIExitCode.usageOrAmbiguityFailure.rawValue
            }
        }

        switch sinkProvider(selectedCandidate.pid, signal) {
        case .terminated:
            write(
                "Sent \(signal.displayName) to PID \(selectedCandidate.pid) (\(selectedCandidate.processName)).\n",
                to: stdout
            )
            return CLIExitCode.success.rawValue
        case .notFound:
            write("PID \(selectedCandidate.pid) was not found.\n", to: stderr)
            return CLIExitCode.targetNotFound.rawValue
        case .requiresAdmin:
            write(
                "PID \(selectedCandidate.pid) requires admin privileges. Harbor will not escalate privileges.\n",
                to: stderr
            )
            return CLIExitCode.requiresAdmin.rawValue
        case let .systemError(message):
            write("Failed to sink PID \(selectedCandidate.pid): \(message)\n", to: stderr)
            return CLIExitCode.runtimeFailure.rawValue
        }
    }

    private func promptForCandidateSelection(port: Int, candidates: [SinkCandidate]) -> SinkCandidate? {
        write("Multiple processes are listening on port \(port):\n", to: stdout)

        let rowWidth = max(effectiveWidth(isWide: false) - 6, 40)
        for (index, candidate) in candidates.enumerated() {
            let line = "\(index + 1)) PID \(candidate.pid) \(candidate.processName)  \(candidate.bindSummary)  \(candidate.ticker)"
            write("   \(truncateLine(line, to: rowWidth))\n", to: stdout)
        }

        while true {
            write("Select process [1-\(candidates.count)] or 'q' to cancel: ", to: stdout)
            guard let input = readInputLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }

            if input.caseInsensitiveCompare("q") == .orderedSame {
                return nil
            }

            guard let selected = Int(input), (1...candidates.count).contains(selected) else {
                write("Invalid selection '\(input)'.\n", to: stderr)
                continue
            }

            return candidates[selected - 1]
        }
    }

    private func promptForConfirmation(candidate: SinkCandidate, signal: SinkSignal, targetDescription: String) -> Bool {
        write(
            "About to send \(signal.displayName) to PID \(candidate.pid) (\(candidate.processName)) from \(targetDescription).\n",
            to: stdout
        )
        if !candidate.listeners.isEmpty {
            write("Bind: \(candidate.bindSummary)\n", to: stdout)
            write("Info: \(truncateLine(candidate.ticker, to: max(effectiveWidth(isWide: false) - 8, 40)))\n", to: stdout)
        }

        write("Proceed? [y/N]: ", to: stdout)
        guard let rawInput = readInputLine() else {
            return false
        }

        switch rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "y", "yes":
            return true
        default:
            return false
        }
    }

    private func truncateLine(_ value: String, to width: Int) -> String {
        guard value.count > width else {
            return value
        }

        if width <= 3 {
            return String(value.prefix(max(width, 0)))
        }

        return String(value.prefix(width - 3)) + "..."
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

private extension SinkSignal {
    var displayName: String {
        switch self {
        case .term:
            return "SIGTERM"
        case .kill:
            return "SIGKILL"
        }
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

enum TerminalInteractivityDetector {
    static func current() -> Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }
}

enum Usage {
    static let text = """
    Usage:
      harbor version [--json]
      harbor --version
      harbor list [--json] [--wide] [--no-cmd] [--no-cwd]
      harbor who <port> [--json] [--wide] [--no-cmd] [--no-cwd]
      harbor watch [--interval <seconds>] --jsonl
      harbor sink <port> [--force] [--yes]
      harbor sink --pid <pid> [--force] [--yes]

    Commands:
      version     Show Harbor CLI version.
      list        Show active TCP listeners.
      who         Filter listeners by port.
      watch       Stream snapshots continuously as JSONL.
      sink        Signal a listener process by port or pid.

    Notes:
      '--version' is a hidden alias for 'version'.
      'ls' is a hidden alias for 'list'.
      'kill' is a hidden alias for 'sink'.
    """
}

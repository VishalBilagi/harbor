import Foundation
import PortKit
import Testing
@testable import harbor

@Test func parserDefaultsToListCommand() throws {
    let command = try HarborCLIParser.parse(arguments: ["harbor"])

    #expect(command == .list(display: ListDisplayOptions(), json: false))
}

@Test func parserSupportsListAliasAndDisplayFlags() throws {
    let command = try HarborCLIParser.parse(arguments: ["harbor", "ls", "--wide", "--no-cmd", "--no-cwd"])

    #expect(
        command == .list(
            display: ListDisplayOptions(wide: true, showCommandLine: false, showCwd: false),
            json: false
        )
    )
}

@Test func parserParsesVersionCommandAndFlagAlias() throws {
    let command = try HarborCLIParser.parse(arguments: ["harbor", "version", "--json"])
    #expect(command == .version(json: true))

    let aliasCommand = try HarborCLIParser.parse(arguments: ["harbor", "--version"])
    #expect(aliasCommand == .version(json: false))
}

@Test func parserParsesWhoCommandWithJsonFlag() throws {
    let command = try HarborCLIParser.parse(arguments: ["harbor", "who", "3000", "--json"])

    #expect(
        command == .who(
            port: 3000,
            display: ListDisplayOptions(wide: false, showCommandLine: true, showCwd: true),
            json: true
        )
    )
}

@Test func parserParsesSinkByPortWithFlags() throws {
    let command = try HarborCLIParser.parse(arguments: ["harbor", "sink", "3000", "--force", "--yes"])

    #expect(
        command == .sink(
            options: SinkOptions(target: .port(3000), force: true, assumeYes: true)
        )
    )
}

@Test func parserParsesSinkByPIDAndKillAlias() throws {
    let command = try HarborCLIParser.parse(arguments: ["harbor", "kill", "--pid", "4242"])

    #expect(
        command == .sink(
            options: SinkOptions(target: .pid(4242), force: false, assumeYes: false)
        )
    )
}

@Test func parserRejectsSinkWithoutTarget() {
    #expect(throws: CLIParseError.self) {
        _ = try HarborCLIParser.parse(arguments: ["harbor", "sink", "--yes"])
    }
}

@Test func parserRejectsSinkPortAndPIDCombination() {
    #expect(throws: CLIParseError.self) {
        _ = try HarborCLIParser.parse(arguments: ["harbor", "sink", "3000", "--pid", "42"])
    }
}

@Test func parserValidatesPortBoundsForWho() {
    #expect(throws: CLIParseError.self) {
        _ = try HarborCLIParser.parse(arguments: ["harbor", "who", "99999"])
    }
}

@Test func parserRequiresJsonlForWatch() {
    #expect(throws: CLIParseError.self) {
        _ = try HarborCLIParser.parse(arguments: ["harbor", "watch", "--interval", "1"])
    }
}

@Test func sinkResolverGroupsRowsByPIDAndSummarizesDualStackOnce() {
    let listeners = [
        makeListener(
            port: 3000,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 200,
            processName: "node",
            commandLine: "node server.js",
            cwd: "/tmp/project"
        ),
        makeListener(
            port: 3000,
            bindAddress: "::1",
            family: .ipv6,
            pid: 200,
            processName: "node",
            commandLine: "node server.js",
            cwd: "/tmp/project"
        )
    ]

    let candidates = SinkResolver.candidates(from: listeners)
    #expect(candidates.count == 1)
    #expect(candidates[0].pid == 200)
    #expect(candidates[0].bindSummary.contains("v4+v6"))
}

@Test func sinkResolverDetectsAmbiguousPortAcrossDistinctPIDs() {
    let listeners = [
        makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 100, processName: "web"),
        makeListener(port: 3000, bindAddress: "::1", family: .ipv6, pid: 200, processName: "api")
    ]

    let resolution = SinkResolver.resolvePort(port: 3000, listeners: listeners)

    switch resolution {
    case let .ambiguous(candidates):
        #expect(candidates.map(\.pid) == [100, 200])
    default:
        Issue.record("Expected an ambiguous resolution for port 3000")
    }
}

@Test func tableRendererTruncatesFlexibleColumnsToTerminalWidth() {
    let listener = makeListener(
        port: 3000,
        bindAddress: "127.0.0.1",
        family: .ipv4,
        pid: 123,
        processName: "node",
        commandLine: "node /very/long/path/to/server/entrypoint.js --verbose --trace-warnings",
        cwd: "/Users/vishalbilagi/personal/Harbor/this/is/a/very/long/path/to/a/project/root"
    )

    let rendered = ListenerTableRenderer.render(
        listeners: [listener],
        display: ListDisplayOptions(),
        terminalWidth: 70
    )

    let lines = rendered.split(separator: "\n").map(String.init)
    for line in lines {
        #expect(line.count <= 70)
    }

    #expect(rendered.contains("..."))
}

@Test func tableRendererCanHideCommandAndCwdColumns() {
    let listener = makeListener(
        port: 5432,
        bindAddress: "*",
        family: .ipv4,
        pid: 456,
        processName: "postgres"
    )

    let rendered = ListenerTableRenderer.render(
        listeners: [listener],
        display: ListDisplayOptions(wide: false, showCommandLine: false, showCwd: false),
        terminalWidth: 120
    )

    let header = String(rendered.split(separator: "\n").first ?? "")
    #expect(header.contains("PORT"))
    #expect(!header.contains("CMD"))
    #expect(!header.contains("CWD"))
}

@Test func snapshotJsonEncoderIncludesAllMachineFields() throws {
    let listener = makeListener(
        port: 8080,
        bindAddress: "::1",
        family: .ipv6,
        pid: 777,
        processName: "api",
        commandLine: nil,
        cwd: nil,
        cpuPercent: nil,
        memBytes: nil,
        requiresAdminToKill: nil
    )

    let snapshot = ListenerSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_741_052_800),
        listeners: [listener]
    )

    let json = try SnapshotJSONEncoder.encode(snapshot)
    let payload = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

    #expect(payload["schemaVersion"] as? Int == 1)
    #expect(payload["generatedAt"] as? String != nil)

    let listeners = try #require(payload["listeners"] as? [[String: Any]])
    #expect(listeners.count == 1)

    let object = listeners[0]
    #expect(object["proto"] as? String == "tcp")
    #expect(object["port"] as? Int == 8080)
    #expect(object["bindAddress"] as? String == "::1")
    #expect(object["family"] as? String == "ipv6")
    #expect(object["pid"] as? Int == 777)
    #expect(object["processName"] as? String == "api")
    #expect(object["commandLine"] is NSNull)
    #expect(object["cwd"] is NSNull)
    #expect(object["cpuPercent"] is NSNull)
    #expect(object["memBytes"] is NSNull)
    #expect(object["requiresAdminToKill"] is NSNull)
}

@Test func versionCommandRendersPlainAndJSONOutput() throws {
    let plain = runCLI(
        arguments: ["harbor", "version"],
        snapshot: ListenerSnapshot(generatedAt: Date(), listeners: []),
        interactiveTTY: false
    )
    #expect(plain.exitCode == CLIExitCode.success.rawValue)
    #expect(plain.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == HarborBuildInfo.version)

    let json = runCLI(
        arguments: ["harbor", "version", "--json"],
        snapshot: ListenerSnapshot(generatedAt: Date(), listeners: []),
        interactiveTTY: false
    )
    #expect(json.exitCode == CLIExitCode.success.rawValue)

    let payload = try #require(
        JSONSerialization.jsonObject(with: Data(json.stdout.utf8), options: []) as? [String: Any]
    )
    #expect(payload["version"] as? String == HarborBuildInfo.version)
}

@Test func listCommandRendersHumanOutputTable() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(port: 3000, bindAddress: "*", family: .ipv4, pid: 101, processName: "node"),
            makeListener(port: 5432, bindAddress: "127.0.0.1", family: .ipv4, pid: 202, processName: "postgres")
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "list", "--no-cmd", "--no-cwd"],
        snapshot: snapshot,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.success.rawValue)
    #expect(result.stdout.contains("PORT"))
    #expect(result.stdout.contains("PROC"))
    #expect(result.stdout.contains("node"))
    #expect(result.stdout.contains("postgres"))
}

@Test func listCommandJsonOutputMatchesMachineContract() throws {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_741_052_800),
        listeners: [
            makeListener(
                port: 8080,
                bindAddress: "127.0.0.1",
                family: .ipv4,
                pid: 777,
                processName: "api",
                commandLine: nil,
                cwd: nil,
                cpuPercent: nil,
                memBytes: nil,
                requiresAdminToKill: nil
            )
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "list", "--json"],
        snapshot: snapshot,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.success.rawValue)
    let payload = try #require(
        JSONSerialization.jsonObject(with: Data(result.stdout.utf8), options: []) as? [String: Any]
    )
    #expect(payload["schemaVersion"] as? Int == 1)
    let listeners = try #require(payload["listeners"] as? [[String: Any]])
    #expect(listeners.count == 1)
    #expect(listeners[0]["port"] as? Int == 8080)
    #expect(listeners[0]["processName"] as? String == "api")
    #expect(listeners[0]["commandLine"] is NSNull)
}

@Test func whoCommandJsonFiltersPortRows() throws {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(port: 3000, bindAddress: "*", family: .ipv4, pid: 10, processName: "web"),
            makeListener(port: 3000, bindAddress: "::1", family: .ipv6, pid: 10, processName: "web"),
            makeListener(port: 5432, bindAddress: "127.0.0.1", family: .ipv4, pid: 20, processName: "postgres")
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "who", "3000", "--json"],
        snapshot: snapshot,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.success.rawValue)
    let payload = try #require(
        JSONSerialization.jsonObject(with: Data(result.stdout.utf8), options: []) as? [String: Any]
    )
    let listeners = try #require(payload["listeners"] as? [[String: Any]])
    #expect(listeners.count == 2)
    #expect(listeners.allSatisfy { ($0["port"] as? Int) == 3000 })
}

@Test func sinkReturnsFreePortCodeWhenNoListenersMatch() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [makeListener(port: 8080, bindAddress: "*", family: .ipv4, pid: 999, processName: "api")]
    )

    let result = runCLI(
        arguments: ["harbor", "sink", "3000", "--yes"],
        snapshot: snapshot,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.freePort.rawValue)
    #expect(result.sinkCalls.isEmpty)
    #expect(result.stdout.contains("Port 3000 is free"))
}

@Test func sinkFailsAmbiguousPortWithoutTTY() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 100, processName: "web"),
            makeListener(port: 3000, bindAddress: "::1", family: .ipv6, pid: 200, processName: "api")
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "sink", "3000"],
        snapshot: snapshot,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.usageOrAmbiguityFailure.rawValue)
    #expect(result.sinkCalls.isEmpty)
    #expect(result.stderr.contains("Rerun with '--pid <pid>'"))
}

@Test func sinkFailsAmbiguousPortWhenYesIsUsed() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 100, processName: "web"),
            makeListener(port: 3000, bindAddress: "::1", family: .ipv6, pid: 200, processName: "api")
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "sink", "3000", "--yes"],
        snapshot: snapshot,
        interactiveTTY: true,
        inputLines: ["1"]
    )

    #expect(result.exitCode == CLIExitCode.usageOrAmbiguityFailure.rawValue)
    #expect(result.sinkCalls.isEmpty)
    #expect(result.stderr.contains("Rerun with '--pid <pid>'"))
}

@Test func sinkSupportsInteractivePickerAndConfirmation() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 100, processName: "web"),
            makeListener(port: 3000, bindAddress: "::1", family: .ipv6, pid: 200, processName: "api")
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "sink", "3000"],
        snapshot: snapshot,
        sinkResult: .terminated,
        interactiveTTY: true,
        inputLines: ["2", "y"]
    )

    #expect(result.exitCode == CLIExitCode.success.rawValue)
    #expect(result.sinkCalls.count == 1)
    #expect(result.sinkCalls[0].0 == 200)
    #expect(result.sinkCalls[0].1 == .term)
}

@Test func sinkForceByPIDUsesSigkill() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 4242, processName: "node")
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "sink", "--pid", "4242", "--force", "--yes"],
        snapshot: snapshot,
        sinkResult: .terminated,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.success.rawValue)
    #expect(result.sinkCalls.count == 1)
    #expect(result.sinkCalls[0].0 == 4242)
    #expect(result.sinkCalls[0].1 == .kill)
}

@Test func sinkRequiresAdminFromMetadataWithoutAttemptingSignal() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(
                port: 3000,
                bindAddress: "127.0.0.1",
                family: .ipv4,
                pid: 300,
                processName: "root-owned",
                requiresAdminToKill: true
            )
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "sink", "3000", "--yes"],
        snapshot: snapshot,
        sinkResult: .terminated,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.requiresAdmin.rawValue)
    #expect(result.sinkCalls.isEmpty)
    #expect(result.stderr.contains("will not escalate privileges"))
}

@Test func sinkReturnsRequiresAdminWhenResolverRejectsSignal() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [
            makeListener(
                port: 3000,
                bindAddress: "127.0.0.1",
                family: .ipv4,
                pid: 301,
                processName: "owned",
                requiresAdminToKill: false
            )
        ]
    )

    let result = runCLI(
        arguments: ["harbor", "sink", "3000", "--yes"],
        snapshot: snapshot,
        sinkResult: .requiresAdmin,
        interactiveTTY: false
    )

    #expect(result.exitCode == CLIExitCode.requiresAdmin.rawValue)
    #expect(result.sinkCalls.count == 1)
    #expect(result.stderr.contains("will not escalate privileges"))
}

@Test func watchCommandHonorsIntervalCadenceUntilProviderFails() {
    let snapshot = ListenerSnapshot(
        generatedAt: Date(),
        listeners: [makeListener(port: 3000, bindAddress: "*", family: .ipv4, pid: 42, processName: "node")]
    )
    let provider = FailingSnapshotProvider(
        snapshotsBeforeFailure: [snapshot, snapshot],
        failure: WatchSnapshotFailure.stop
    )
    let sleeps = SleepRecorder()

    let result = runCLIWithProviders(
        arguments: ["harbor", "watch", "--interval", "1.5", "--jsonl"],
        interactiveTTY: false,
        inputLines: [],
        sleep: { interval in
            sleeps.record(interval)
        },
        snapshotProvider: {
            try provider.next()
        },
        sinkProvider: { _, _ in
            .terminated
        }
    )

    #expect(result.exitCode == CLIExitCode.runtimeFailure.rawValue)
    #expect(result.sleepCalls == [1.5, 1.5])
    #expect(result.stdout.split(whereSeparator: \.isNewline).count == 2)
    #expect(result.stderr.contains("Failed to scan listeners"))
}

private enum WatchSnapshotFailure: Error {
    case stop
}

private struct CLIExecutionResult {
    let exitCode: Int
    let stdout: String
    let stderr: String
    let sinkCalls: [(Int, SinkSignal)]
    let sleepCalls: [TimeInterval]
}

private func runCLI(
    arguments: [String],
    snapshot: ListenerSnapshot,
    sinkResult: SinkResult = .terminated,
    interactiveTTY: Bool,
    inputLines: [String] = []
) -> CLIExecutionResult {
    runCLIWithProviders(
        arguments: arguments,
        interactiveTTY: interactiveTTY,
        inputLines: inputLines,
        sleep: { _ in },
        snapshotProvider: { snapshot },
        sinkProvider: { _, _ in sinkResult }
    )
}

private func runCLIWithProviders(
    arguments: [String],
    interactiveTTY: Bool,
    inputLines: [String],
    sleep: @escaping @Sendable (TimeInterval) -> Void,
    snapshotProvider: @escaping @Sendable () throws -> ListenerSnapshot,
    sinkProvider: @escaping @Sendable (_ pid: Int, _ signal: SinkSignal) -> SinkResult
) -> CLIExecutionResult {
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    let sinkCallRecorder = SinkCallRecorder(sinkProvider: sinkProvider)
    let sleepRecorder = SleepRecorder()
    let inputFeed = InputFeed(lines: inputLines)

    let cli = HarborCLI(
        arguments: arguments,
        stdout: outputPipe.fileHandleForWriting,
        stderr: errorPipe.fileHandleForWriting,
        terminalWidthProvider: { 120 },
        sleep: { interval in
            sleepRecorder.record(interval)
            sleep(interval)
        },
        isInteractiveTTYProvider: { interactiveTTY },
        readInputLine: { inputFeed.read() },
        snapshotProvider: snapshotProvider,
        sinkProvider: { pid, signal in
            sinkCallRecorder.call(pid: pid, signal: signal)
        }
    )

    let exitCode = cli.run()

    outputPipe.fileHandleForWriting.closeFile()
    errorPipe.fileHandleForWriting.closeFile()

    let standardOutput = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let standardError = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    return CLIExecutionResult(
        exitCode: exitCode,
        stdout: standardOutput,
        stderr: standardError,
        sinkCalls: sinkCallRecorder.calls,
        sleepCalls: sleepRecorder.calls
    )
}

private final class SinkCallRecorder: @unchecked Sendable {
    private let sinkProvider: @Sendable (_ pid: Int, _ signal: SinkSignal) -> SinkResult
    private(set) var calls: [(Int, SinkSignal)] = []

    init(sinkProvider: @escaping @Sendable (_ pid: Int, _ signal: SinkSignal) -> SinkResult) {
        self.sinkProvider = sinkProvider
    }

    func call(pid: Int, signal: SinkSignal) -> SinkResult {
        calls.append((pid, signal))
        return sinkProvider(pid, signal)
    }
}

private final class InputFeed: @unchecked Sendable {
    private var lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    func read() -> String? {
        guard !lines.isEmpty else {
            return nil
        }

        return lines.removeFirst()
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private(set) var calls: [TimeInterval] = []

    func record(_ interval: TimeInterval) {
        calls.append(interval)
    }
}

private final class FailingSnapshotProvider: @unchecked Sendable {
    private var snapshots: [ListenerSnapshot]
    private let failure: Error

    init(snapshotsBeforeFailure: [ListenerSnapshot], failure: Error) {
        self.snapshots = snapshotsBeforeFailure
        self.failure = failure
    }

    func next() throws -> ListenerSnapshot {
        guard !snapshots.isEmpty else {
            throw failure
        }

        return snapshots.removeFirst()
    }
}

private func makeListener(
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
) -> Listener {
    Listener(
        proto: .tcp,
        port: port,
        bindAddress: bindAddress,
        family: family,
        pid: pid,
        processName: processName,
        commandLine: commandLine,
        cwd: cwd,
        cpuPercent: cpuPercent,
        memBytes: memBytes,
        requiresAdminToKill: requiresAdminToKill
    )
}

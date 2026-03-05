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

@Test func tableRendererTruncatesFlexibleColumnsToTerminalWidth() {
    let listener = Listener(
        proto: .tcp,
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
    let listener = Listener(
        proto: .tcp,
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
    let listener = Listener(
        proto: .tcp,
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

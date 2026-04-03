import Foundation
import Testing
@testable import PortKit

@Test func endpointParserHandlesWildcardIPv4AndIPv6Formats() throws {
    let wildcard = try #require(ListenerEndpointParser.parse("*:3000"))
    #expect(wildcard == ListenerEndpoint(bindAddress: "*", port: 3000))

    let localhost = try #require(ListenerEndpointParser.parse("localhost:8080"))
    #expect(localhost == ListenerEndpoint(bindAddress: "localhost", port: 8080))

    let ipv4 = try #require(ListenerEndpointParser.parse("127.0.0.1:3000"))
    #expect(ipv4 == ListenerEndpoint(bindAddress: "127.0.0.1", port: 3000))

    let ipv6 = try #require(ListenerEndpointParser.parse("[::1]:5432"))
    #expect(ipv6 == ListenerEndpoint(bindAddress: "::1", port: 5432))
}

@Test func scannerParsesFiltersAndSortsListenerRows() throws {
    let fixture = try fixture(named: "common-listeners.txt")

    let scanner = LsofListenerScanner(runCommand: { executablePath, arguments in
        #expect(executablePath == "/usr/sbin/lsof")
        #expect(arguments == ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcnPTtf"])

        return CommandResult(
            standardOutput: Data(fixture.utf8),
            standardError: Data(),
            terminationStatus: 0
        )
    })

    let listeners = try scanner.scan()

    #expect(listeners.map(\.port) == [3000, 5432, 5432, 8080, 9222, 9222])
    #expect(listeners.map(\.pid) == [88, 111, 111, 47, 312, 312])
    #expect(listeners.map(\.family) == [.ipv4, .ipv4, .ipv6, .ipv4, .ipv4, .ipv6])
    #expect(listeners.map(\.bindAddress) == ["*", "127.0.0.1", "::1", "localhost", "127.0.0.1", "::1"])
    #expect(listeners.map(\.processName) == ["node", "postgres", "postgres", "devserver", "Google Chrome", "Google Chrome"])
    #expect(listeners.allSatisfy { $0.proto == .tcp })
}

@Test func scannerParsesMultipleRowsForSinglePIDFromFixture() throws {
    let fixture = try fixture(named: "multiple-rows-single-pid.txt")
    let scanner = LsofListenerScanner(runCommand: { _, _ in
        CommandResult(
            standardOutput: Data(fixture.utf8),
            standardError: Data(),
            terminationStatus: 0
        )
    })

    let listeners = try scanner.scan()
    #expect(listeners.count == 3)
    #expect(listeners.map(\.pid) == [501, 501, 501])
    #expect(listeners.map(\.port) == [5000, 5000, 8000])
    #expect(listeners.map(\.bindAddress) == ["127.0.0.1", "::1", "0.0.0.0"])
}

@Test func scannerDropsNoisyRowsFromFixture() throws {
    let fixture = try fixture(named: "restricted-and-noisy.txt")
    let scanner = LsofListenerScanner(runCommand: { _, _ in
        CommandResult(
            standardOutput: Data(fixture.utf8),
            standardError: Data(),
            terminationStatus: 0
        )
    })

    let listeners = try scanner.scan()
    #expect(listeners.count == 1)
    #expect(listeners[0].pid == 700)
    #expect(listeners[0].port == 8443)
    #expect(listeners[0].processName == "rootd")
}

@Test func scannerDropsRowsMissingProtocolField() throws {
    let fixture = """
    p100
    cmissing
    f1
    tIPv4
    n127.0.0.1:19000
    TST=LISTEN
    """

    let scanner = LsofListenerScanner(runCommand: { _, _ in
        CommandResult(
            standardOutput: Data(fixture.utf8),
            standardError: Data(),
            terminationStatus: 0
        )
    })

    let listeners = try scanner.scan()
    #expect(listeners.isEmpty)
}

@Test func scannerAcceptsStatusOneWhenOutputIsPresent() throws {
    let fixture = """
    p42
    cweb
    f5
    Ptcp
    tIPv4
    n127.0.0.1:9000
    TST=LISTEN
    """

    let scanner = LsofListenerScanner(runCommand: { _, _ in
        CommandResult(
            standardOutput: Data(fixture.utf8),
            standardError: Data("lsof: can't find PID 42's byte count: Operation not permitted".utf8),
            terminationStatus: 1
        )
    })

    let listeners = try scanner.scan()
    #expect(listeners.count == 1)
    #expect(listeners[0].pid == 42)
    #expect(listeners[0].port == 9000)
}

@Test func scannerTreatsStatusOneWithoutOutputAsEmptyResult() throws {
    let scanner = LsofListenerScanner(runCommand: { _, _ in
        CommandResult(
            standardOutput: Data(),
            standardError: Data(),
            terminationStatus: 1
        )
    })

    let listeners = try scanner.scan()
    #expect(listeners.isEmpty)
}

@Test func scannerThrowsOnUnexpectedStatusOneFailure() {
    let scanner = LsofListenerScanner(runCommand: { _, _ in
        CommandResult(
            standardOutput: Data(),
            standardError: Data("lsof: catastrophic failure".utf8),
            terminationStatus: 1
        )
    })

    #expect(throws: PortKitError.self) {
        _ = try scanner.scan()
    }
}

@Test func snapshotBuilderPinsSchemaVersionAndOrdering() {
    let latePort = Listener(
        proto: .tcp,
        port: 8080,
        bindAddress: "127.0.0.1",
        family: .ipv4,
        pid: 99,
        processName: "api"
    )
    let earlyPort = Listener(
        proto: .tcp,
        port: 3000,
        bindAddress: "*",
        family: .ipv4,
        pid: 11,
        processName: "node"
    )
    let generatedAt = Date(timeIntervalSince1970: 1_741_052_800)

    let snapshot = ListenerSnapshot(generatedAt: generatedAt, listeners: [latePort, earlyPort])

    #expect(snapshot.schemaVersion == 1)
    #expect(snapshot.generatedAt == generatedAt)
    #expect(snapshot.listeners.map(\.port) == [3000, 8080])
}

@Test func snapshotReportsOnlyNewUniquePortsRelativeToPreviousSnapshot() {
    let previous = ListenerSnapshot(listeners: [
        makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 11, processName: "node"),
        makeListener(port: 5432, bindAddress: "127.0.0.1", family: .ipv4, pid: 22, processName: "postgres"),
        makeListener(port: 5432, bindAddress: "::1", family: .ipv6, pid: 22, processName: "postgres")
    ])
    let current = ListenerSnapshot(listeners: [
        makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 11, processName: "node"),
        makeListener(port: 5432, bindAddress: "127.0.0.1", family: .ipv4, pid: 22, processName: "postgres"),
        makeListener(port: 5432, bindAddress: "::1", family: .ipv6, pid: 22, processName: "postgres"),
        makeListener(port: 8080, bindAddress: "127.0.0.1", family: .ipv4, pid: 33, processName: "api"),
        makeListener(port: 8080, bindAddress: "::1", family: .ipv6, pid: 33, processName: "api"),
        makeListener(port: 9222, bindAddress: "127.0.0.1", family: .ipv4, pid: 44, processName: "chrome")
    ])

    #expect(current.newlyListeningPorts(since: previous) == [8080, 9222])
}

@Test func snapshotReportsOnlyClosedUniquePortsRelativeToPreviousSnapshot() {
    let previous = ListenerSnapshot(listeners: [
        makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 11, processName: "node"),
        makeListener(port: 8080, bindAddress: "127.0.0.1", family: .ipv4, pid: 33, processName: "api"),
        makeListener(port: 8080, bindAddress: "::1", family: .ipv6, pid: 33, processName: "api"),
        makeListener(port: 9222, bindAddress: "127.0.0.1", family: .ipv4, pid: 44, processName: "chrome")
    ])
    let current = ListenerSnapshot(listeners: [
        makeListener(port: 3000, bindAddress: "127.0.0.1", family: .ipv4, pid: 11, processName: "node")
    ])

    #expect(current.closedListeningPorts(since: previous) == [8080, 9222])
}

@Test func snapshotSkipsNewPortNotificationsWithoutABaseline() {
    let snapshot = ListenerSnapshot(listeners: [
        makeListener(port: 8080, bindAddress: "127.0.0.1", family: .ipv4, pid: 99, processName: "api")
    ])

    #expect(snapshot.newlyListeningPorts(since: nil).isEmpty)
}

@Test func snapshotSkipsClosedPortNotificationsWithoutABaseline() {
    let snapshot = ListenerSnapshot(listeners: [
        makeListener(port: 8080, bindAddress: "127.0.0.1", family: .ipv4, pid: 99, processName: "api")
    ])

    #expect(snapshot.closedListeningPorts(since: nil).isEmpty)
}

private func fixture(named name: String) throws -> String {
    let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
    let fixtureURL = testsDirectory
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("lsof")
        .appendingPathComponent(name)

    return try String(contentsOf: fixtureURL, encoding: .utf8)
}

private func makeListener(
    port: Int,
    bindAddress: String,
    family: ListenerFamily,
    pid: Int,
    processName: String
) -> Listener {
    Listener(
        proto: .tcp,
        port: port,
        bindAddress: bindAddress,
        family: family,
        pid: pid,
        processName: processName
    )
}

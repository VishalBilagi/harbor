import Foundation
import Testing
@testable import PortKit

@Test func endpointParserHandlesWildcardIPv4AndIPv6Formats() throws {
    let wildcard = try #require(ListenerEndpointParser.parse("*:3000"))
    #expect(wildcard == ListenerEndpoint(bindAddress: "*", port: 3000))

    let ipv4 = try #require(ListenerEndpointParser.parse("127.0.0.1:3000"))
    #expect(ipv4 == ListenerEndpoint(bindAddress: "127.0.0.1", port: 3000))

    let ipv6 = try #require(ListenerEndpointParser.parse("[::1]:5432"))
    #expect(ipv6 == ListenerEndpoint(bindAddress: "::1", port: 5432))
}

@Test func scannerParsesFiltersAndSortsListenerRows() throws {
    let fixture = """
    p42
    cweb
    f5
    Ptcp
    tIPv6
    n[::1]:9000
    TST=LISTEN
    f6
    Pudp
    tIPv4
    n127.0.0.1:9000
    TST=LISTEN
    f7
    Ptcp
    tIPv4
    n127.0.0.1:9000->127.0.0.1:53412
    TST=ESTABLISHED
    p11
    cpostgres
    f8
    Ptcp
    tIPv6
    n[::1]:5432
    TST=LISTEN
    f9
    Ptcp
    tIPv4
    n127.0.0.1:5432
    TST=LISTEN
    p7
    cnode
    f3
    Ptcp
    tIPv4
    n*:3000
    TST=LISTEN
    """

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

    #expect(listeners.map(\.port) == [3000, 5432, 5432, 9000])
    #expect(listeners.map(\.pid) == [7, 11, 11, 42])
    #expect(listeners.map(\.family) == [.ipv4, .ipv4, .ipv6, .ipv6])
    #expect(listeners.map(\.bindAddress) == ["*", "127.0.0.1", "::1", "::1"])
    #expect(listeners.map(\.processName) == ["node", "postgres", "postgres", "web"])
    #expect(listeners.allSatisfy { $0.proto == .tcp })
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

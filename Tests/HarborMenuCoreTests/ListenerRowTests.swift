import Foundation
import PortKit
import Testing
@testable import HarborMenuCore

@Test func groupedRowsMergeDualStackAndNormalizeTicker() throws {
    let home = NSHomeDirectory()
    let rows = ListenerRow.grouped(from: [
        makeListener(
            port: 3000,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 42,
            processName: "node",
            commandLine: "node server.js",
            cwd: "\(home)/projects/harbor",
            cpuPercent: 18.2,
            memBytes: 8_192,
            requiresAdminToKill: false
        ),
        makeListener(
            port: 3000,
            bindAddress: "::1",
            family: .ipv6,
            pid: 42,
            processName: "node",
            commandLine: "node server.js",
            cwd: "\(home)/projects/harbor",
            cpuPercent: 20.4,
            memBytes: 16_384,
            requiresAdminToKill: false
        )
    ])

    #expect(rows.count == 1)
    let row = try #require(rows.first)
    #expect(row.familySummary == "IPv4+IPv6")
    #expect(row.tickerText.contains("node server.js"))
    #expect(row.tickerText.contains("~/projects/harbor"))
    #expect(row.statsText?.contains("CPU 20.4%") == true)
}

@Test func groupedRowsTreatMissingMetadataAsKnownV1Fallbacks() throws {
    let rows = ListenerRow.grouped(from: [
        makeListener(
            port: 8080,
            bindAddress: "*",
            family: .ipv4,
            pid: 99,
            processName: "api",
            commandLine: nil,
            cwd: nil,
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: nil
        )
    ])

    let row = try #require(rows.first)
    #expect(row.tickerText == "No command line or cwd metadata")
    #expect(row.statsText == nil)
    #expect(row.requiresAdminToKill == true)
}

@Test func groupedRowsExposeUngroupedPortText() throws {
    let rows = ListenerRow.grouped(from: [
        makeListener(
            port: 5432,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 99,
            processName: "api",
            commandLine: nil,
            cwd: nil,
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: false
        )
    ])

    let row = try #require(rows.first)
    #expect(row.portText == "5432")
}

@Test func groupedRowsClassifyBindTonesByListenerKind() throws {
    let localhostRows = ListenerRow.grouped(from: [
        makeListener(
            port: 3000,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 10,
            processName: "node",
            commandLine: "node",
            cwd: nil,
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: false
        ),
        makeListener(
            port: 3000,
            bindAddress: "::1",
            family: .ipv6,
            pid: 10,
            processName: "node",
            commandLine: "node",
            cwd: nil,
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: false
        )
    ])

    let wildcardRows = ListenerRow.grouped(from: [
        makeListener(
            port: 8080,
            bindAddress: "0.0.0.0",
            family: .ipv4,
            pid: 11,
            processName: "api",
            commandLine: "api",
            cwd: nil,
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: false
        )
    ])

    let protectedRows = ListenerRow.grouped(from: [
        makeListener(
            port: 5432,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 12,
            processName: "postgres",
            commandLine: "postgres",
            cwd: nil,
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: true
        )
    ])

    #expect(try #require(localhostRows.first).bindTone == .localhost)
    #expect(try #require(wildcardRows.first).bindTone == .wildcard)
    #expect(try #require(protectedRows.first).bindTone == .protected)
}

@Test func groupedRowsCompactsTickerCommandAndPaths() throws {
    let home = NSHomeDirectory()
    let rows = ListenerRow.grouped(from: [
        makeListener(
            port: 4567,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 66,
            processName: "node",
            commandLine: "/usr/local/bin/node \(home)/apps/service/server.js --watch --inspect",
            cwd: "\(home)/apps/service",
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: false
        )
    ])

    let row = try #require(rows.first)
    #expect(row.tickerCommandText == "node ~/apps/service/server.js --watch …")
    #expect(row.tickerCwdText == "~/apps/service")
}

@Test func groupedRowsMatchMultiTokenSearchAcrossCoreFields() throws {
    let home = NSHomeDirectory()
    let rows = ListenerRow.grouped(from: [
        makeListener(
            port: 3000,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 42,
            processName: "node",
            commandLine: "node server.js --watch",
            cwd: "\(home)/projects/harbor",
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: false
        )
    ])

    let row = try #require(rows.first)
    #expect(row.matches(query: "3000 node"))
    #expect(row.matches(query: "42 SERVER.JS"))
    #expect(row.matches(query: "node projects harbor"))
    #expect(row.matches(query: "3001 node") == false)
}

@Test func groupedRowsRequireAdminIfAnyListenerNeedsIt() throws {
    let rows = ListenerRow.grouped(from: [
        makeListener(
            port: 5432,
            bindAddress: "127.0.0.1",
            family: .ipv4,
            pid: 100,
            processName: "postgres",
            commandLine: "postgres",
            cwd: "/tmp",
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: false
        ),
        makeListener(
            port: 5432,
            bindAddress: "::1",
            family: .ipv6,
            pid: 100,
            processName: "postgres",
            commandLine: "postgres",
            cwd: "/tmp",
            cpuPercent: nil,
            memBytes: nil,
            requiresAdminToKill: nil
        )
    ])

    let row = try #require(rows.first)
    #expect(row.requiresAdminToKill == true)
}

private func makeListener(
    port: Int,
    bindAddress: String,
    family: ListenerFamily,
    pid: Int,
    processName: String,
    commandLine: String?,
    cwd: String?,
    cpuPercent: Double?,
    memBytes: UInt64?,
    requiresAdminToKill: Bool?
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

import Darwin
import Foundation
import Testing
@testable import PortKit

@Test func resolverCachesHeavyMetadataAndComputesCPUDeltas() throws {
    let pid: Int32 = 4242
    let provider = StubProcessInformationProvider()
    provider.snapshots[pid] = [
        ProcessSnapshot(
            uid: 501,
            startTimeMicros: 1_000,
            residentMemoryBytes: 512,
            totalCPUTimeNanos: 1_000_000_000
        ),
        ProcessSnapshot(
            uid: 501,
            startTimeMicros: 1_000,
            residentMemoryBytes: 768,
            totalCPUTimeNanos: 1_200_000_000
        )
    ]
    provider.commandLineSequences[pid] = ["node api.js"]
    provider.cwdSequences[pid] = ["/tmp/harbor"]

    let clock = StubUptimeClock(values: [10_000_000_000, 11_000_000_000])
    let resolver = ProcessMetadataResolver(
        processInformationProvider: provider,
        currentUIDProvider: { 501 },
        uptimeNanosecondsProvider: { clock.next() },
        signalCall: { _, _ in .success }
    )

    let baseListener = makeListener(pid: Int(pid), processName: "node")
    let first = resolver.enrich([baseListener])
    let second = resolver.enrich([baseListener])

    #expect(first[0].commandLine == "node api.js")
    #expect(first[0].cwd == "/tmp/harbor")
    #expect(first[0].memBytes == 512)
    #expect(first[0].cpuPercent == nil)
    #expect(first[0].requiresAdminToKill == false)

    #expect(second[0].commandLine == "node api.js")
    #expect(second[0].cwd == "/tmp/harbor")
    #expect(second[0].memBytes == 768)
    let cpuPercent = try #require(second[0].cpuPercent)
    #expect(abs(cpuPercent - 20.0) < 0.0001)
    #expect(second[0].requiresAdminToKill == false)

    #expect(provider.commandLineReads[pid] == 1)
    #expect(provider.cwdReads[pid] == 1)
}

@Test func resolverInvalidatesPIDCacheWhenProcessStartTimeChanges() {
    let pid: Int32 = 31337
    let provider = StubProcessInformationProvider()
    provider.snapshots[pid] = [
        ProcessSnapshot(
            uid: 501,
            startTimeMicros: 10,
            residentMemoryBytes: 100,
            totalCPUTimeNanos: 1_000_000_000
        ),
        ProcessSnapshot(
            uid: 501,
            startTimeMicros: 11,
            residentMemoryBytes: 200,
            totalCPUTimeNanos: 2_000_000_000
        )
    ]
    provider.commandLineSequences[pid] = ["old cmd", "new cmd"]
    provider.cwdSequences[pid] = ["/old", "/new"]

    let clock = StubUptimeClock(values: [1_000_000_000, 2_000_000_000])
    let resolver = ProcessMetadataResolver(
        processInformationProvider: provider,
        currentUIDProvider: { 501 },
        uptimeNanosecondsProvider: { clock.next() },
        signalCall: { _, _ in .success }
    )

    let baseListener = makeListener(pid: Int(pid), processName: "service")
    let first = resolver.enrich([baseListener])
    let second = resolver.enrich([baseListener])

    #expect(first[0].commandLine == "old cmd")
    #expect(second[0].commandLine == "new cmd")
    #expect(first[0].cwd == "/old")
    #expect(second[0].cwd == "/new")
    #expect(second[0].cpuPercent == nil)
    #expect(provider.commandLineReads[pid] == 2)
    #expect(provider.cwdReads[pid] == 2)
}

@Test func resolverDefaultsRequiresAdminWhenUIDIsUnavailable() {
    let pid: Int32 = 77
    let provider = StubProcessInformationProvider()
    provider.snapshots[pid] = [
        ProcessSnapshot(
            uid: nil,
            startTimeMicros: 42,
            residentMemoryBytes: nil,
            totalCPUTimeNanos: nil
        )
    ]
    provider.commandLineSequences[pid] = ["python server.py"]
    provider.cwdSequences[pid] = ["/workspace"]

    let resolver = ProcessMetadataResolver(
        processInformationProvider: provider,
        currentUIDProvider: { 501 },
        uptimeNanosecondsProvider: { 100 },
        signalCall: { _, _ in .success }
    )

    let listener = resolver.enrich([makeListener(pid: Int(pid), processName: "python")])[0]
    #expect(listener.requiresAdminToKill == true)
}

@Test func sinkUsesOwnershipChecksAndReturnsExpectedStates() {
    let currentUID: uid_t = 501

    do {
        let provider = StubProcessInformationProvider()
        let signalCall = StubSignalCall(responses: [.success])
        let pid: Int32 = 1500
        provider.snapshots[pid] = [
            ProcessSnapshot(uid: currentUID, startTimeMicros: 1, residentMemoryBytes: nil, totalCPUTimeNanos: nil)
        ]

        let resolver = ProcessMetadataResolver(
            processInformationProvider: provider,
            currentUIDProvider: { currentUID },
            uptimeNanosecondsProvider: { 0 },
            signalCall: signalCall.call(pid:signal:)
        )

        let result = resolver.sink(pid: Int(pid), signal: .term)
        #expect(result == .terminated)
        #expect(signalCall.calls.count == 1)
        #expect(signalCall.calls[0].0 == pid)
        #expect(signalCall.calls[0].1 == SIGTERM)
    }

    do {
        let provider = StubProcessInformationProvider()
        let signalCall = StubSignalCall(responses: [])
        let pid: Int32 = 1600
        provider.snapshots[pid] = [
            ProcessSnapshot(uid: currentUID + 1, startTimeMicros: 1, residentMemoryBytes: nil, totalCPUTimeNanos: nil)
        ]

        let resolver = ProcessMetadataResolver(
            processInformationProvider: provider,
            currentUIDProvider: { currentUID },
            uptimeNanosecondsProvider: { 0 },
            signalCall: signalCall.call(pid:signal:)
        )

        let result = resolver.sink(pid: Int(pid), signal: .kill)
        #expect(result == .requiresAdmin)
        #expect(signalCall.calls.isEmpty)
    }

    do {
        let provider = StubProcessInformationProvider()
        let signalCall = StubSignalCall(responses: [.failure(errno: ESRCH)])
        let pid: Int32 = 1700
        provider.snapshots[pid] = [nil]

        let resolver = ProcessMetadataResolver(
            processInformationProvider: provider,
            currentUIDProvider: { currentUID },
            uptimeNanosecondsProvider: { 0 },
            signalCall: signalCall.call(pid:signal:)
        )

        let result = resolver.sink(pid: Int(pid), signal: .term)
        #expect(result == .notFound)
        #expect(signalCall.calls.count == 1)
        #expect(signalCall.calls[0].0 == pid)
        #expect(signalCall.calls[0].1 == 0)
    }

    do {
        let provider = StubProcessInformationProvider()
        let signalCall = StubSignalCall(responses: [.failure(errno: EBUSY)])
        let pid: Int32 = 1800
        provider.snapshots[pid] = [
            ProcessSnapshot(uid: currentUID, startTimeMicros: 1, residentMemoryBytes: nil, totalCPUTimeNanos: nil)
        ]

        let resolver = ProcessMetadataResolver(
            processInformationProvider: provider,
            currentUIDProvider: { currentUID },
            uptimeNanosecondsProvider: { 0 },
            signalCall: signalCall.call(pid:signal:)
        )

        let result = resolver.sink(pid: Int(pid), signal: .term)
        guard case let .systemError(message) = result else {
            Issue.record("Expected .systemError, got \(result)")
            return
        }

        #expect(message.contains("errno \(EBUSY)"))
        #expect(signalCall.calls.count == 1)
        #expect(signalCall.calls[0].0 == pid)
        #expect(signalCall.calls[0].1 == SIGTERM)
    }
}

private func makeListener(pid: Int, processName: String) -> Listener {
    Listener(
        proto: .tcp,
        port: 3000,
        bindAddress: "*",
        family: .ipv4,
        pid: pid,
        processName: processName
    )
}

private final class StubUptimeClock: @unchecked Sendable {
    private var values: [UInt64]

    init(values: [UInt64]) {
        self.values = values
    }

    func next() -> UInt64 {
        if values.isEmpty {
            return 0
        }

        return values.removeFirst()
    }
}

private final class StubSignalCall: @unchecked Sendable {
    private var responses: [SignalCallResult]
    private(set) var calls: [(Int32, Int32)] = []

    init(responses: [SignalCallResult]) {
        self.responses = responses
    }

    func call(pid: Int32, signal: Int32) -> SignalCallResult {
        calls.append((pid, signal))

        if responses.isEmpty {
            return .success
        }

        return responses.removeFirst()
    }
}

private final class StubProcessInformationProvider: ProcessInformationProviding, @unchecked Sendable {
    var snapshots: [Int32: [ProcessSnapshot?]] = [:]
    var commandLineSequences: [Int32: [String?]] = [:]
    var cwdSequences: [Int32: [String?]] = [:]

    private(set) var commandLineReads: [Int32: Int] = [:]
    private(set) var cwdReads: [Int32: Int] = [:]

    func readSnapshot(pid: Int32) -> ProcessSnapshot? {
        guard var entries = snapshots[pid], !entries.isEmpty else {
            return nil
        }

        let snapshot = entries.removeFirst()
        snapshots[pid] = entries
        return snapshot
    }

    func readCommandLine(pid: Int32) -> String? {
        commandLineReads[pid, default: 0] += 1
        return popFirstValue(for: pid, in: &commandLineSequences)
    }

    func readWorkingDirectory(pid: Int32) -> String? {
        cwdReads[pid, default: 0] += 1
        return popFirstValue(for: pid, in: &cwdSequences)
    }

    private func popFirstValue(
        for pid: Int32,
        in storage: inout [Int32: [String?]]
    ) -> String? {
        guard var values = storage[pid], !values.isEmpty else {
            return nil
        }

        let value = values.removeFirst()
        storage[pid] = values
        return value
    }
}

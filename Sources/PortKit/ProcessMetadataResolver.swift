import Darwin
import Foundation

private struct ProcessIdentity: Hashable, Sendable {
    let pid: Int32
    let startTimeMicros: UInt64
}

struct ProcessSnapshot: Sendable {
    let uid: uid_t?
    let startTimeMicros: UInt64?
    let residentMemoryBytes: UInt64?
    let totalCPUTimeNanos: UInt64?
}

private struct HeavyProcessMetadata: Sendable {
    let commandLine: String?
    let cwd: String?
}

private struct CPUSample: Sendable {
    let totalCPUTimeNanos: UInt64
    let capturedAtUptimeNanos: UInt64
}

enum SignalCallResult: Sendable {
    case success
    case failure(errno: Int32)
}

protocol ProcessInformationProviding {
    func readSnapshot(pid: Int32) -> ProcessSnapshot?
    func readCommandLine(pid: Int32) -> String?
    func readWorkingDirectory(pid: Int32) -> String?
}

struct SystemProcessInformationProvider: ProcessInformationProviding {
    func readSnapshot(pid: Int32) -> ProcessSnapshot? {
        var taskAllInfo = proc_taskallinfo()
        let expectedSize = MemoryLayout<proc_taskallinfo>.stride
        let returnedSize = withUnsafeMutablePointer(to: &taskAllInfo) { infoPointer in
            proc_pidinfo(
                pid,
                PROC_PIDTASKALLINFO,
                0,
                infoPointer,
                Int32(expectedSize)
            )
        }

        guard returnedSize == expectedSize else {
            return nil
        }

        let startTimeMicros = Self.makeStartTimeMicros(
            seconds: taskAllInfo.pbsd.pbi_start_tvsec,
            microseconds: taskAllInfo.pbsd.pbi_start_tvusec
        )
        let cpuTimeNanos = UInt64(taskAllInfo.ptinfo.pti_total_user) + UInt64(taskAllInfo.ptinfo.pti_total_system)
        let residentMemoryBytes = UInt64(taskAllInfo.ptinfo.pti_resident_size)

        return ProcessSnapshot(
            uid: taskAllInfo.pbsd.pbi_uid,
            startTimeMicros: startTimeMicros,
            residentMemoryBytes: residentMemoryBytes,
            totalCPUTimeNanos: cpuTimeNanos
        )
    }

    func readCommandLine(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0

        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: Int(size))
        let didReadBuffer = buffer.withUnsafeMutableBytes { rawBuffer in
            sysctl(&mib, u_int(mib.count), rawBuffer.baseAddress, &size, nil, 0)
        }

        guard didReadBuffer == 0 else {
            return nil
        }

        let bytesRead = Int(size)
        guard bytesRead > MemoryLayout<Int32>.size else {
            return nil
        }

        var argcRaw: Int32 = 0
        withUnsafeMutableBytes(of: &argcRaw) { argcBytes in
            argcBytes.copyBytes(from: buffer[0..<MemoryLayout<Int32>.size])
        }

        let argumentCount = Int(Int32(littleEndian: argcRaw))
        guard argumentCount > 0 else {
            return nil
        }

        var index = MemoryLayout<Int32>.size

        // Skip exec path and trailing null terminators.
        while index < bytesRead, buffer[index] != 0 {
            index += 1
        }
        while index < bytesRead, buffer[index] == 0 {
            index += 1
        }

        var arguments: [String] = []
        arguments.reserveCapacity(argumentCount)

        while index < bytesRead, arguments.count < argumentCount {
            let start = index
            while index < bytesRead, buffer[index] != 0 {
                index += 1
            }

            guard start < index else {
                break
            }

            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))

            while index < bytesRead, buffer[index] == 0 {
                index += 1
            }
        }

        return arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }

    func readWorkingDirectory(pid: Int32) -> String? {
        var vnodePathInfo = proc_vnodepathinfo()
        let expectedSize = MemoryLayout<proc_vnodepathinfo>.stride
        let returnedSize = withUnsafeMutablePointer(to: &vnodePathInfo) { infoPointer in
            proc_pidinfo(
                pid,
                PROC_PIDVNODEPATHINFO,
                0,
                infoPointer,
                Int32(expectedSize)
            )
        }

        guard returnedSize == expectedSize else {
            return nil
        }

        return withUnsafePointer(to: &vnodePathInfo.pvi_cdir.vip_path) { pathPointer in
            pathPointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStringPointer in
                guard cStringPointer.pointee != 0 else {
                    return nil
                }

                return String(cString: cStringPointer)
            }
        }
    }

    private static func makeStartTimeMicros(seconds: UInt64, microseconds: UInt64) -> UInt64? {
        guard seconds > 0 else {
            return nil
        }

        let normalizedMicros = microseconds > 0 ? microseconds : 0
        return (seconds * 1_000_000) + normalizedMicros
    }
}

final class ProcessMetadataResolver: @unchecked Sendable {
    private struct ResolvedMetadata: Sendable {
        let commandLine: String?
        let cwd: String?
        let memBytes: UInt64?
        let cpuPercent: Double?
        let requiresAdminToKill: Bool
    }

    private let processInformationProvider: any ProcessInformationProviding
    private let currentUIDProvider: @Sendable () -> uid_t
    private let uptimeNanosecondsProvider: @Sendable () -> UInt64
    private let signalCall: @Sendable (_ pid: Int32, _ signal: Int32) -> SignalCallResult

    private let stateLock = NSLock()
    private var identityByPID: [Int32: ProcessIdentity] = [:]
    private var heavyMetadataByIdentity: [ProcessIdentity: HeavyProcessMetadata] = [:]
    private var cpuSampleByIdentity: [ProcessIdentity: CPUSample] = [:]

    init(
        processInformationProvider: any ProcessInformationProviding = SystemProcessInformationProvider(),
        currentUIDProvider: @escaping @Sendable () -> uid_t = { getuid() },
        uptimeNanosecondsProvider: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        signalCall: @escaping @Sendable (_ pid: Int32, _ signal: Int32) -> SignalCallResult = { pid, signal in
            ProcessMetadataResolver.liveSignalCall(pid: pid, signal: signal)
        }
    ) {
        self.processInformationProvider = processInformationProvider
        self.currentUIDProvider = currentUIDProvider
        self.uptimeNanosecondsProvider = uptimeNanosecondsProvider
        self.signalCall = signalCall
    }

    func enrich(_ listeners: [Listener]) -> [Listener] {
        guard !listeners.isEmpty else {
            pruneCaches(activePIDs: [])
            return []
        }

        let currentUID = currentUIDProvider()
        let activePIDs = Set(listeners.map { Int32($0.pid) })
        var metadataByPID: [Int32: ResolvedMetadata] = [:]
        metadataByPID.reserveCapacity(activePIDs.count)

        for pid in activePIDs {
            metadataByPID[pid] = resolveMetadata(for: pid, currentUID: currentUID)
        }

        pruneCaches(activePIDs: activePIDs)

        return listeners.map { listener in
            guard let metadata = metadataByPID[Int32(listener.pid)] else {
                return listener
            }

            return Listener(
                proto: listener.proto,
                port: listener.port,
                bindAddress: listener.bindAddress,
                family: listener.family,
                pid: listener.pid,
                processName: listener.processName,
                commandLine: metadata.commandLine,
                cwd: metadata.cwd,
                cpuPercent: metadata.cpuPercent,
                memBytes: metadata.memBytes,
                requiresAdminToKill: metadata.requiresAdminToKill
            )
        }
    }

    func sink(pid: Int, signal: SinkSignal) -> SinkResult {
        guard pid > 0, pid <= Int(Int32.max) else {
            return .notFound
        }

        let pidValue = Int32(pid)
        let currentUID = currentUIDProvider()
        let snapshot = processInformationProvider.readSnapshot(pid: pidValue)

        if let ownerUID = snapshot?.uid {
            guard ownerUID == currentUID else {
                return .requiresAdmin
            }
        } else {
            switch signalCall(pidValue, 0) {
            case .success:
                return .requiresAdmin
            case let .failure(errnoCode):
                if errnoCode == ESRCH {
                    return .notFound
                }

                return .requiresAdmin
            }
        }

        let signalValue: Int32 = switch signal {
        case .term: SIGTERM
        case .kill: SIGKILL
        }

        switch signalCall(pidValue, signalValue) {
        case .success:
            return .terminated
        case let .failure(errnoCode):
            if errnoCode == ESRCH {
                return .notFound
            }

            if errnoCode == EPERM {
                return .requiresAdmin
            }

            return .systemError(Self.makeSystemErrorString(errnoCode: errnoCode))
        }
    }

    private func resolveMetadata(for pid: Int32, currentUID: uid_t) -> ResolvedMetadata {
        let snapshot = processInformationProvider.readSnapshot(pid: pid)
        let identity = snapshot?.startTimeMicros.map { ProcessIdentity(pid: pid, startTimeMicros: $0) }

        var cachedHeavyMetadata: HeavyProcessMetadata?
        var previousCPUSample: CPUSample?

        if let identity {
            stateLock.withLock {
                if let previousIdentity = identityByPID[pid], previousIdentity != identity {
                    heavyMetadataByIdentity.removeValue(forKey: previousIdentity)
                    cpuSampleByIdentity.removeValue(forKey: previousIdentity)
                }

                identityByPID[pid] = identity
                cachedHeavyMetadata = heavyMetadataByIdentity[identity]
                previousCPUSample = cpuSampleByIdentity[identity]
            }
        } else {
            stateLock.withLock {
                if let previousIdentity = identityByPID.removeValue(forKey: pid) {
                    heavyMetadataByIdentity.removeValue(forKey: previousIdentity)
                    cpuSampleByIdentity.removeValue(forKey: previousIdentity)
                }
            }
        }

        let heavyMetadata = cachedHeavyMetadata ?? HeavyProcessMetadata(
            commandLine: processInformationProvider.readCommandLine(pid: pid),
            cwd: processInformationProvider.readWorkingDirectory(pid: pid)
        )

        if let identity, cachedHeavyMetadata == nil {
            stateLock.withLock {
                heavyMetadataByIdentity[identity] = heavyMetadata
            }
        }

        var cpuPercent: Double?
        if let identity,
           let totalCPUTimeNanos = snapshot?.totalCPUTimeNanos {
            let newSample = CPUSample(
                totalCPUTimeNanos: totalCPUTimeNanos,
                capturedAtUptimeNanos: uptimeNanosecondsProvider()
            )

            if let previousCPUSample {
                cpuPercent = Self.computeCPUPercent(previous: previousCPUSample, current: newSample)
            }

            stateLock.withLock {
                cpuSampleByIdentity[identity] = newSample
            }
        }

        let requiresAdminToKill = snapshot?.uid.map { $0 != currentUID } ?? true

        return ResolvedMetadata(
            commandLine: heavyMetadata.commandLine,
            cwd: heavyMetadata.cwd,
            memBytes: snapshot?.residentMemoryBytes,
            cpuPercent: cpuPercent,
            requiresAdminToKill: requiresAdminToKill
        )
    }

    private func pruneCaches(activePIDs: Set<Int32>) {
        stateLock.withLock {
            let stalePIDs = identityByPID.keys.filter { !activePIDs.contains($0) }

            for pid in stalePIDs {
                if let identity = identityByPID.removeValue(forKey: pid) {
                    heavyMetadataByIdentity.removeValue(forKey: identity)
                    cpuSampleByIdentity.removeValue(forKey: identity)
                }
            }
        }
    }

    private static func computeCPUPercent(previous: CPUSample, current: CPUSample) -> Double? {
        guard current.capturedAtUptimeNanos > previous.capturedAtUptimeNanos,
              current.totalCPUTimeNanos >= previous.totalCPUTimeNanos else {
            return nil
        }

        let elapsedCPU = Double(current.totalCPUTimeNanos - previous.totalCPUTimeNanos)
        let elapsedWall = Double(current.capturedAtUptimeNanos - previous.capturedAtUptimeNanos)
        let cpuPercent = (elapsedCPU / elapsedWall) * 100.0

        guard cpuPercent.isFinite else {
            return nil
        }

        return max(0, cpuPercent)
    }

    private static func liveSignalCall(pid: Int32, signal: Int32) -> SignalCallResult {
        if Darwin.kill(pid, signal) == 0 {
            return .success
        }

        return .failure(errno: Darwin.errno)
    }

    private static func makeSystemErrorString(errnoCode: Int32) -> String {
        let description = String(cString: strerror(errnoCode))
        return "errno \(errnoCode): \(description)"
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

import Combine
import Foundation
import PortKit

@MainActor
final class HarborMenuModel: ObservableObject {
    enum RefreshReason {
        case menuOpen
        case manualAction
        case sinkCompletion
        case fallbackTimer
    }

    @Published private(set) var snapshot: ListenerSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var sinkInFlightPIDs: Set<Int> = []
    @Published private(set) var lastRefreshAt: Date?
    @Published var errorMessage: String?
    @Published var sinkMessage: String?

    private let portKit = PortKit()
    private var queuedRefresh = false

    var rows: [ListenerRow] {
        ListenerRow.grouped(from: snapshot?.listeners ?? [])
    }

    var statusSummary: String {
        let listenerCount = snapshot?.listeners.count ?? 0
        let timestamp: String

        if let lastRefreshAt {
            timestamp = lastRefreshAt.formatted(
                date: .omitted,
                time: .standard
            )
        } else {
            timestamp = "never"
        }

        return "\(listenerCount) listeners • refreshed \(timestamp)"
    }

    func refresh(for _: RefreshReason) {
        guard !isRefreshing else {
            queuedRefresh = true
            return
        }

        isRefreshing = true
        errorMessage = nil

        let portKit = self.portKit
        Task {
            let result: Result<ListenerSnapshot, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    try portKit.snapshot()
                }
            }.value

            if Task.isCancelled {
                return
            }

            isRefreshing = false
            lastRefreshAt = Date()

            switch result {
            case let .success(snapshot):
                self.snapshot = snapshot
            case let .failure(error):
                errorMessage = error.localizedDescription
            }

            if queuedRefresh {
                queuedRefresh = false
                refresh(for: .fallbackTimer)
            }
        }
    }

    func runFallbackTimer(every intervalSeconds: Int) async {
        let clampedInterval = max(
            Int(AppSettings.minRefreshIntervalSeconds),
            min(Int(AppSettings.maxRefreshIntervalSeconds), intervalSeconds)
        )

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(clampedInterval))
            } catch {
                break
            }

            if Task.isCancelled {
                break
            }

            refresh(for: .fallbackTimer)
        }
    }

    func sink(pid: Int, force: Bool) {
        guard !sinkInFlightPIDs.contains(pid) else {
            return
        }

        sinkInFlightPIDs.insert(pid)
        let portKit = self.portKit

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                portKit.sink(pid: pid, force: force)
            }.value

            if Task.isCancelled {
                return
            }

            sinkInFlightPIDs.remove(pid)
            sinkMessage = Self.makeSinkMessage(result: result, pid: pid, force: force)
            refresh(for: .sinkCompletion)
        }
    }

    func isSinking(pid: Int) -> Bool {
        sinkInFlightPIDs.contains(pid)
    }

    private static func makeSinkMessage(result: SinkResult, pid: Int, force: Bool) -> String {
        let action = force ? "Force sink" : "Sink"

        switch result {
        case .terminated:
            return "\(action) succeeded for PID \(pid)."
        case .notFound:
            return "PID \(pid) is no longer running."
        case .requiresAdmin:
            return "PID \(pid) requires admin privileges."
        case let .systemError(error):
            return "\(action) failed for PID \(pid): \(error)"
        }
    }
}

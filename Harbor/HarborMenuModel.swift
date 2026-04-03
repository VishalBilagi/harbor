import Combine
import Foundation
import PortKit
import UserNotifications

@MainActor
final class HarborMenuModel: ObservableObject {
    enum RefreshReason {
        case appLaunch
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

    private let portKit: PortKit
    private let portChangeNotifier: PortChangeNotifier
    private var monitorTask: Task<Void, Never>?
    private var queuedRefresh = false

    init(
        portKit: PortKit = PortKit(),
        automaticallyStartMonitoring: Bool = true
    ) {
        self.portKit = portKit
        self.portChangeNotifier = .shared

        if automaticallyStartMonitoring {
            startMonitoring()
        }
    }

    deinit {
        monitorTask?.cancel()
    }

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
                let previousSnapshot = self.snapshot
                self.snapshot = snapshot
                let newPorts = snapshot.newlyListeningPorts(since: previousSnapshot)
                if !newPorts.isEmpty {
                    portChangeNotifier.notifyOpened(ports: newPorts, in: snapshot)
                }

                let closedPorts = snapshot.closedListeningPorts(since: previousSnapshot)
                if let previousSnapshot, !closedPorts.isEmpty {
                    portChangeNotifier.notifyClosed(ports: closedPorts, from: previousSnapshot)
                }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }

            if queuedRefresh {
                queuedRefresh = false
                refresh(for: .fallbackTimer)
            }
        }
    }

    func startMonitoring() {
        guard monitorTask == nil else {
            return
        }

        refresh(for: .appLaunch)
        monitorTask = Task { [weak self] in
            await self?.runMonitorLoop()
        }
    }

    private func runMonitorLoop() async {
        while !Task.isCancelled {
            let intervalSeconds = AppSettings.currentRefreshIntervalSeconds()

            do {
                try await Task.sleep(for: .seconds(intervalSeconds))
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

private final class PortChangeNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PortChangeNotifier()

    private let center: UNUserNotificationCenter

    private override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func notifyOpened(ports: [Int], in snapshot: ListenerSnapshot) {
        notify(
            identifierPrefix: "harbor.new-port",
            titlePrefix: "New listening port",
            pluralTitle: "New listening ports",
            fallbackBody: "Harbor detected a new listener.",
            ports: ports,
            snapshot: snapshot
        )
    }

    func notifyClosed(ports: [Int], from snapshot: ListenerSnapshot) {
        notify(
            identifierPrefix: "harbor.closed-port",
            titlePrefix: "Listening port closed",
            pluralTitle: "Listening ports closed",
            fallbackBody: "Harbor detected a closed listener.",
            ports: ports,
            snapshot: snapshot
        )
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func notify(
        identifierPrefix: String,
        titlePrefix: String,
        pluralTitle: String,
        fallbackBody: String,
        ports: [Int],
        snapshot: ListenerSnapshot
    ) {
        guard !ports.isEmpty else {
            return
        }

        Task {
            guard await ensureAuthorization() else {
                return
            }

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix).\(snapshot.generatedAt.timeIntervalSince1970)",
                content: makeContent(
                    titlePrefix: titlePrefix,
                    pluralTitle: pluralTitle,
                    fallbackBody: fallbackBody,
                    ports: ports,
                    snapshot: snapshot
                ),
                trigger: nil
            )

            try? await add(request)
        }
    }

    private func makeContent(
        titlePrefix: String,
        pluralTitle: String,
        fallbackBody: String,
        ports: [Int],
        snapshot: ListenerSnapshot
    ) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        let summaries = portSummaries(for: ports, in: snapshot)

        if let port = ports.first, ports.count == 1 {
            content.title = "\(titlePrefix): \(port)"
            content.body = summaries.first ?? fallbackBody
        } else {
            let visibleSummaries = summaries.prefix(3)
            let extraCount = summaries.count - visibleSummaries.count

            content.title = pluralTitle
            content.body = visibleSummaries.joined(separator: " • ")

            if extraCount > 0 {
                content.body += " • +\(extraCount) more"
            }

            if content.body.isEmpty {
                content.body = fallbackBody
            }
        }

        content.sound = .default
        return content
    }

    private func portSummaries(for ports: [Int], in snapshot: ListenerSnapshot) -> [String] {
        let listenersByPort = Dictionary(grouping: snapshot.listeners.filter { ports.contains($0.port) }, by: \.port)

        return ports.compactMap { port in
            guard let listeners = listenersByPort[port], !listeners.isEmpty else {
                return nil
            }

            let processNames = Array(Set(listeners.map(\.processName))).sorted()
            let bindAddresses = Array(Set(listeners.map(\.bindAddress))).sorted()
            let processSummary = processNames.joined(separator: ", ")
            let bindSummary = bindAddresses.joined(separator: ", ")

            if !processSummary.isEmpty, !bindSummary.isEmpty {
                return "\(port): \(processSummary) on \(bindSummary)"
            }

            if !processSummary.isEmpty {
                return "\(port): \(processSummary)"
            }

            if !bindSummary.isEmpty {
                return "\(port): \(bindSummary)"
            }

            return "Port \(port)"
        }
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            return false
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

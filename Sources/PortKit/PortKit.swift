import Foundation

public struct PortKit: Sendable {
    private let scanner: LsofListenerScanner
    private let metadataResolver: ProcessMetadataResolver

    public init() {
        self.scanner = LsofListenerScanner()
        self.metadataResolver = ProcessMetadataResolver()
    }

    init(scanner: LsofListenerScanner, metadataResolver: ProcessMetadataResolver) {
        self.scanner = scanner
        self.metadataResolver = metadataResolver
    }

    public func scanListeners() throws -> [Listener] {
        metadataResolver.enrich(try scanner.scan())
    }

    public func snapshot(generatedAt: Date = Date()) throws -> ListenerSnapshot {
        ListenerSnapshot(generatedAt: generatedAt, listeners: try scanListeners())
    }

    public func sink(pid: Int, signal: SinkSignal = .term) -> SinkResult {
        metadataResolver.sink(pid: pid, signal: signal)
    }

    public func sink(pid: Int, force: Bool) -> SinkResult {
        sink(pid: pid, signal: force ? .kill : .term)
    }
}

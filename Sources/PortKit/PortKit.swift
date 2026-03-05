import Foundation

public struct PortKit: Sendable {
    public init() {}

    public func scanListeners() throws -> [Listener] {
        try LsofListenerScanner().scan()
    }

    public func snapshot(generatedAt: Date = Date()) throws -> ListenerSnapshot {
        ListenerSnapshot(generatedAt: generatedAt, listeners: try scanListeners())
    }
}

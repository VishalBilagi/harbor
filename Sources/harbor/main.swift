import Darwin
import Foundation
import PortKit

do {
    let snapshot = try PortKit().snapshot()

    for listener in snapshot.listeners {
        print("\(listener.proto.rawValue) \(listener.bindAddress):\(listener.port) pid=\(listener.pid) \(listener.processName) \(listener.family.rawValue)")
    }
} catch {
    let message = "Failed to scan listeners: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

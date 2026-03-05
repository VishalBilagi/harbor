import Foundation

public enum PortKitError: Error, Sendable {
    case scannerLaunchFailed(String)
    case scannerFailed(status: Int32, standardError: String)
    case invalidScannerOutput
}

extension PortKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .scannerLaunchFailed(description):
            return "Failed to launch lsof: \(description)"
        case let .scannerFailed(status, standardError):
            if standardError.isEmpty {
                return "lsof exited with status \(status)."
            }

            return "lsof exited with status \(status): \(standardError)"
        case .invalidScannerOutput:
            return "lsof returned output that could not be decoded as UTF-8."
        }
    }
}

public struct LsofListenerScanner: Sendable {
    static let executablePath = "/usr/sbin/lsof"
    static let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcnPTtf"]

    private let runCommand: @Sendable (_ executablePath: String, _ arguments: [String]) throws -> CommandResult

    public init() {
        self.runCommand = Self.runCommand(executablePath:arguments:)
    }

    init(
        runCommand: @escaping @Sendable (_ executablePath: String, _ arguments: [String]) throws -> CommandResult
    ) {
        self.runCommand = runCommand
    }

    public func scan() throws -> [Listener] {
        let result = try runCommand(Self.executablePath, Self.arguments)

        guard result.terminationStatus == 0 else {
            let standardError = String(decoding: result.standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PortKitError.scannerFailed(status: result.terminationStatus, standardError: standardError)
        }

        guard let output = String(data: result.standardOutput, encoding: .utf8) else {
            throw PortKitError.invalidScannerOutput
        }

        return LsofOutputParser().parse(output)
    }

    private static func runCommand(executablePath: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw PortKitError.scannerLaunchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        return CommandResult(
            standardOutput: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            standardError: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            terminationStatus: process.terminationStatus
        )
    }
}

struct CommandResult: Sendable {
    let standardOutput: Data
    let standardError: Data
    let terminationStatus: Int32
}

struct ListenerEndpoint: Equatable {
    let bindAddress: String
    let port: Int
}

struct ListenerEndpointParser {
    static func parse(_ rawValue: String) -> ListenerEndpoint? {
        let localEndpoint: String
        if let remoteSeparator = rawValue.range(of: "->") {
            localEndpoint = String(rawValue[..<remoteSeparator.lowerBound])
        } else {
            localEndpoint = rawValue
        }

        if localEndpoint.hasPrefix("["),
           let closingBracketIndex = localEndpoint.lastIndex(of: "]") {
            let bindStart = localEndpoint.index(after: localEndpoint.startIndex)
            let bindAddress = String(localEndpoint[bindStart..<closingBracketIndex])
            let portStart = localEndpoint.index(after: closingBracketIndex)
            let portComponent = localEndpoint[portStart...]

            guard portComponent.first == ":" else {
                return nil
            }

            guard let port = Int(portComponent.dropFirst()) else {
                return nil
            }

            return ListenerEndpoint(bindAddress: bindAddress, port: port)
        }

        guard let separatorIndex = localEndpoint.lastIndex(of: ":") else {
            return nil
        }

        let bindAddress = String(localEndpoint[..<separatorIndex])
        guard !bindAddress.isEmpty else {
            return nil
        }

        guard let port = Int(localEndpoint[localEndpoint.index(after: separatorIndex)...]) else {
            return nil
        }

        return ListenerEndpoint(bindAddress: bindAddress, port: port)
    }
}

struct LsofOutputParser {
    func parse(_ output: String) -> [Listener] {
        var currentPID: Int?
        var currentProcessName: String?
        var currentRecord: PartialListenerRecord?
        var listeners: [Listener] = []

        func finalizeCurrentRecord() {
            guard let listener = currentRecord?.listener else {
                currentRecord = nil
                return
            }

            listeners.append(listener)
            currentRecord = nil
        }

        for line in output.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else {
                continue
            }

            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                finalizeCurrentRecord()
                currentPID = Int(value)
                currentProcessName = nil
            case "c":
                currentProcessName = value
                if currentRecord != nil {
                    currentRecord?.processName = value
                }
            case "f":
                finalizeCurrentRecord()
                currentRecord = PartialListenerRecord(pid: currentPID, processName: currentProcessName)
            case "P":
                currentRecord?.protoRawValue = value.lowercased()
            case "t":
                currentRecord?.family = switch value {
                case "IPv4": .ipv4
                case "IPv6": .ipv6
                default: nil
                }
            case "n":
                currentRecord?.endpoint = ListenerEndpointParser.parse(value)
            case "T":
                if value == "ST=LISTEN" {
                    currentRecord?.isListen = true
                }
            default:
                continue
            }
        }

        finalizeCurrentRecord()
        return listeners.sorted()
    }
}

private struct PartialListenerRecord {
    let pid: Int?
    var processName: String?
    var protoRawValue: String?
    var family: ListenerFamily?
    var endpoint: ListenerEndpoint?
    var isListen = false

    var listener: Listener? {
        guard isListen,
              let pid,
              let processName,
              let protoRawValue,
              let family,
              let endpoint else {
            return nil
        }

        guard let proto = ListenerProtocol(rawValue: protoRawValue), proto == .tcp else {
            return nil
        }

        return Listener(
            proto: proto,
            port: endpoint.port,
            bindAddress: endpoint.bindAddress,
            family: family,
            pid: pid,
            processName: processName
        )
    }
}

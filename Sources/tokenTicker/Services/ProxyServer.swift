import Foundation
import Network

// MARK: - ProxyServer

@MainActor
final class ProxyServer {

    // MARK: - Public API

    static let shared = ProxyServer()

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    let logURL: URL

    private let queue = DispatchQueue(label: "com.tokenTicker.proxyServer", qos: .utility)

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".config/tokenTicker")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        logURL = configDir.appendingPathComponent("ollama-proxy.log")
    }

    func start(port: UInt16 = 11435) {
        // Rotate log on startup
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        Self.rotateLog(url: logURL, cutoffDate: cutoff)

        guard listener == nil else { return }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("[ProxyServer] Invalid port: \(port)")
            return
        }

        let params = NWParameters.tcp
        guard let newListener = try? NWListener(using: params, on: nwPort) else {
            print("[ProxyServer] Failed to create listener on port \(port)")
            return
        }

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[ProxyServer] Listening on port \(port)")
            case .failed(let error):
                print("[ProxyServer] Listener failed: \(error)")
                Task { @MainActor in self?.listener = nil }
            case .cancelled:
                print("[ProxyServer] Listener cancelled")
                Task { @MainActor in self?.listener = nil }
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleIncoming(connection)
            }
        }

        listener = newListener
        newListener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections.values {
            conn.cancel()
        }
        connections.removeAll()
    }

    // MARK: - Connection Handling

    private func handleIncoming(_ clientConn: NWConnection) {
        let key = ObjectIdentifier(clientConn)
        connections[key] = clientConn

        clientConn.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { @MainActor in self?.connections.removeValue(forKey: key) }
            } else if case .failed = state {
                Task { @MainActor in
                    self?.connections.removeValue(forKey: key)
                    clientConn.cancel()
                }
            }
        }

        clientConn.start(queue: queue)

        // Read the request from the client, then open upstream and proxy it
        readAll(from: clientConn) { [weak self] requestData in
            guard let self, let requestData else {
                clientConn.cancel()
                return
            }
            self.forwardToUpstream(requestData: requestData, clientConn: clientConn)
        }
    }

    /// Reads all available data from a connection until it closes.
    nonisolated private func readAll(from conn: NWConnection,
                                     accumulated: Data = Data(),
                                     completion: @escaping (Data?) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
            var buffer = accumulated
            if let data = content {
                buffer.append(data)
            }
            if error != nil {
                // If we got an error but have some data, treat as complete
                if buffer.isEmpty {
                    completion(nil)
                } else {
                    completion(buffer)
                }
                return
            }
            if isComplete {
                completion(buffer.isEmpty ? nil : buffer)
            } else if content != nil {
                // For HTTP requests we need headers at minimum to decide how much to read.
                // We consider the request complete once we have a full HTTP header block.
                // Look for \r\n\r\n which terminates headers.
                if buffer.contains(sequence: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                    completion(buffer)
                } else {
                    self.readAll(from: conn, accumulated: buffer, completion: completion)
                }
            } else {
                self.readAll(from: conn, accumulated: buffer, completion: completion)
            }
        }
    }

    private func forwardToUpstream(requestData: Data, clientConn: NWConnection) {
        let upstream = NWConnection(
            host: NWEndpoint.Host("localhost"),
            port: NWEndpoint.Port(rawValue: 11434)!,
            using: .tcp
        )

        let logURL = self.logURL

        upstream.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Send request bytes to upstream
                upstream.send(content: requestData, completion: .contentProcessed { error in
                    if let error {
                        print("[ProxyServer] Upstream send error: \(error)")
                        upstream.cancel()
                        clientConn.cancel()
                        return
                    }
                    // Now stream the upstream response back to the client
                    ProxyServer.pipeResponse(from: upstream,
                                             to: clientConn,
                                             accumulated: Data(),
                                             logURL: logURL)
                })
            case .failed(let error):
                print("[ProxyServer] Upstream connection failed: \(error)")
                clientConn.cancel()
            case .cancelled:
                break
            default:
                break
            }
        }

        upstream.start(queue: queue)
    }

    /// Reads upstream response chunks, forwards each to client, accumulates for log parsing.
    nonisolated private static func pipeResponse(from upstream: NWConnection,
                                                 to client: NWConnection,
                                                 accumulated: Data,
                                                 logURL: URL) {
        upstream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
            var buffer = accumulated

            if let chunk = content, !chunk.isEmpty {
                buffer.append(chunk)
                // Forward chunk to client
                client.send(content: chunk, completion: .contentProcessed { _ in })
            }

            if isComplete || error != nil {
                // Upstream done — close client and parse log
                client.send(content: nil, contentContext: .finalMessage,
                            isComplete: true, completion: .contentProcessed { _ in
                    client.cancel()
                })
                upstream.cancel()
                // Parse token counts from accumulated response
                Self.parseAndLog(responseData: buffer, logURL: logURL)
            } else {
                // Continue piping
                Self.pipeResponse(from: upstream, to: client, accumulated: buffer, logURL: logURL)
            }
        }
    }

    // MARK: - NDJSON Parsing & Logging

    nonisolated private static func parseAndLog(responseData: Data, logURL: URL) {
        guard let text = String(data: responseData, encoding: .utf8) else { return }

        // Strip HTTP headers if present (find \r\n\r\n separator)
        let body: String
        if let headerEnd = text.range(of: "\r\n\r\n") {
            body = String(text[headerEnd.upperBound...])
        } else {
            body = text
        }

        // Find last non-empty line
        let lines = body.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let lastLine = lines.last,
              let lineData = lastLine.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let response = try? decoder.decode(OllamaResponse.self, from: lineData) else { return }

        let prompt = response.promptEvalCount ?? 0
        let completion = response.evalCount ?? 0
        guard prompt > 0 || completion > 0 else { return }

        appendLogEntry(
            model: response.model,
            promptTokens: prompt,
            completionTokens: completion,
            logURL: logURL
        )
    }

    nonisolated private static func appendLogEntry(model: String,
                                                   promptTokens: Int,
                                                   completionTokens: Int,
                                                   logURL: URL) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let entry = ProxyLogEntry(
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            timestamp: formatter.string(from: Date())
        )
        guard let data = try? JSONEncoder().encode(entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                try? handle.close()
            }
        } else {
            try? lineData.write(to: logURL, options: .atomic)
        }
    }

    // MARK: - Log Rotation

    /// Reads the log at `url`, removes entries older than `cutoffDate`, and rewrites it.
    /// Exposed as `internal static` for testability.
    nonisolated static func rotateLog(url: URL, cutoffDate: Date) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        struct TimestampEntry: Decodable { let timestamp: String }
        let decoder = JSONDecoder()

        let kept = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .filter { line -> Bool in
                guard let data = line.data(using: .utf8),
                      let entry = try? decoder.decode(TimestampEntry.self, from: data),
                      let date = formatter.date(from: entry.timestamp)
                else {
                    // Keep lines we can't parse (don't discard unknown data)
                    return true
                }
                return date >= cutoffDate
            }

        let result = kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")
        try? result.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Exposed Internal Types (for tests)

    struct ProxyLogEntry: Encodable {
        let model: String
        let promptTokens: Int
        let completionTokens: Int
        let timestamp: String
    }

    struct OllamaResponse: Decodable {
        let model: String
        let promptEvalCount: Int?  // snake_case: prompt_eval_count
        let evalCount: Int?        // snake_case: eval_count
    }
}

// MARK: - Data extension helper

private extension Data {
    func contains(sequence: Data) -> Bool {
        guard sequence.count <= count else { return false }
        return (0...(count - sequence.count)).contains { i in
            self[i..<(i + sequence.count)] == sequence
        }
    }
}

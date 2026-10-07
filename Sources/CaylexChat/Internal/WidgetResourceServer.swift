#if os(iOS)
import Foundation
import Network

protocol WidgetResourceServing: AnyObject, Sendable {
    func start(completion: @escaping @Sendable (Result<URL, Error>) -> Void)
    func stop()
}

/// Serves only bundled static resources on loopback. A localhost origin supports web media APIs.
/// No credentials or API responses are served by this listener.
final class WidgetResourceServer: WidgetResourceServing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ai.caylex.widget.resources")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var onReady: (@Sendable (Result<URL, Error>) -> Void)?
    private let root: URL
    private let route = UUID().uuidString

    init(root: URL) { self.root = root }

    func start(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async {
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                self.onReady = completion
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard let port = listener.port else { return }
                        let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.route)/index.html")!
                        self.onReady?(.success(url)); self.onReady = nil
                    case .failed(let error):
                        self.onReady?(.failure(error)); self.onReady = nil
                    default: break
                    }
                }
                listener.newConnectionHandler = { connection in
                    self.connections[ObjectIdentifier(connection)] = connection
                    connection.start(queue: self.queue)
                    self.receive(connection, accumulated: Data())
                }
                listener.start(queue: self.queue)
            } catch { completion(.failure(error)) }
        }
    }

    func stop() {
        queue.async {
            self.onReady = nil
            self.listener?.stateUpdateHandler = nil
            self.listener?.newConnectionHandler = nil
            self.listener?.cancel(); self.listener = nil
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            var buffer = accumulated
            if let data { buffer.append(data) }
            guard error == nil, buffer.count <= 16384 else { self.finish(connection); return }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                let line = String(decoding: buffer, as: UTF8.self).components(separatedBy: "\r\n")[0]
                let parts = line.split(separator: " ")
                let prefix = "/\(self.route)/"
                guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix(prefix) else {
                    self.respond(connection, status: "404 Not Found", body: Data(), type: "text/plain"); return
                }
                let name = String(parts[1].dropFirst(prefix.count))
                let allowed = ["index.html": "text/html; charset=utf-8", "chat-widget.js": "text/javascript; charset=utf-8"]
                guard let type = allowed[name], let body = try? Data(contentsOf: self.root.appendingPathComponent(name)) else {
                    self.respond(connection, status: "404 Not Found", body: Data(), type: "text/plain"); return
                }
                self.respond(connection, status: "200 OK", body: body, type: type)
            } else if complete { self.finish(connection) }
            else { self.receive(connection, accumulated: buffer) }
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: Data, type: String) {
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8); response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in self.finish(connection) })
    }

    private func finish(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
}
#endif

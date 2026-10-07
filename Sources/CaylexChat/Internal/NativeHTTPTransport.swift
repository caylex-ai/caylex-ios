#if os(iOS)
import Foundation
import WebKit

/// Native HTTP keeps API traffic independent of browser CORS. Data delegates preserve SSE streaming.
@MainActor
final class NativeHTTPTransport: NSObject, URLSessionDataDelegate {
    private struct Operation {
        let id: String
        let task: URLSessionDataTask
    }
    private var operations: [Int: Operation] = [:]
    private var baseURL: URL
    private let emit: ([String: Any]) -> Void
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    init(baseURL: URL, emit: @escaping ([String: Any]) -> Void) {
        self.baseURL = baseURL
        self.emit = emit
    }

    func update(baseURL: URL) { self.baseURL = baseURL }

    func receive(_ message: [String: Any]) {
        guard let id = message["id"] as? String else { return }
        if message["type"] as? String == "abort" {
            if let key = operations.first(where: { $0.value.id == id })?.key {
                operations.removeValue(forKey: key)?.task.cancel()
            }
            return
        }
        guard message["type"] as? String == "request",
              let rawURL = message["url"] as? String, let url = URL(string: rawURL), allows(url),
              let method = message["method"] as? String,
              ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(method),
              let rawBody = message["body"] as? String, rawBody.count <= 48 * 1024 * 1024,
              let body = Data(base64Encoded: rawBody) else {
            emit(["id": id, "type": "error", "message": "The request is outside the configured Caylex API or is invalid"])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !body.isEmpty { request.httpBody = body }
        let prohibited = ["host", "cookie", "origin", "referer", "content-length", "connection"]
        for (key, value) in message["headers"] as? [String: String] ?? [:] where !prohibited.contains(key.lowercased()) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let task = session.dataTask(with: request)
        operations[task.taskIdentifier] = Operation(id: id, task: task)
        task.resume()
    }

    func cancelRequests() {
        operations.values.forEach { $0.task.cancel() }
        operations.removeAll()
    }

    func stop() {
        cancelRequests()
        session.invalidateAndCancel()
    }

    func allows(_ url: URL) -> Bool {
        let url = url.standardized
        let base = baseURL.standardized
        let basePath = (base.path as NSString).standardizingPath
        let path = basePath.hasSuffix("/") ? basePath : basePath + "/"
        let targetPath = (url.path as NSString).standardizingPath
        let targetPort = url.port ?? (url.scheme == "https" ? 443 : 80)
        let basePort = base.port ?? (base.scheme == "https" ? 443 : 80)
        return url.scheme == base.scheme && url.host == base.host && targetPort == basePort &&
            url.user == nil && url.password == nil && targetPath.hasPrefix(path)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                               didReceive response: URLResponse,
                               completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let disposition = MainActor.assumeIsolated { () -> URLSession.ResponseDisposition in
            guard let operation = operations[dataTask.taskIdentifier], let response = response as? HTTPURLResponse else {
                return .cancel
            }
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                let name = String(describing: key).lowercased()
                if !["content-encoding", "content-length", "transfer-encoding", "set-cookie"].contains(name) {
                    headers[name] = String(describing: value)
                }
            }
            emit(["id": operation.id, "type": "headers", "status": response.statusCode, "headers": headers])
            return .allow
        }
        completionHandler(disposition)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            guard let operation = operations[dataTask.taskIdentifier] else { return }
            emit(["id": operation.id, "type": "data", "data": data.base64EncodedString()])
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let operation = operations.removeValue(forKey: task.taskIdentifier) else { return }
            if error != nil {
                emit(["id": operation.id, "type": "error", "message": "Could not reach the Caylex API"])
            } else { emit(["id": operation.id, "type": "end"]) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                               completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = MainActor.assumeIsolated { request.url.map(allows) == true }
        completionHandler(allowed ? request : nil)
    }
}
#endif

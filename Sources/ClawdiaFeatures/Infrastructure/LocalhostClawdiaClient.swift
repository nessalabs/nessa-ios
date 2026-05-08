import Foundation

public struct LocalhostClawdiaClient: LocalClawdiaConnecting {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 2) {
        self.session = session
        self.timeout = timeout
    }

    public func connect(to endpoint: ClawdiaEndpoint) async -> ConnectionState {
        guard let request = URLRequest.clawdiaHealthRequest(endpoint: endpoint, timeout: timeout) else {
            return .failed("Unsupported endpoint")
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Invalid response")
            }
            return (200..<300).contains(http.statusCode) ? .connected(endpoint) : .failed("HTTP \(http.statusCode)")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

public extension URLRequest {
    static func clawdiaHealthRequest(endpoint: ClawdiaEndpoint, timeout: TimeInterval) -> URLRequest? {
        let url: URL?
        switch endpoint {
        case .localhost(let port):
            url = URL(string: "http://127.0.0.1:\(port)/health")
        case .cloud(let baseURL):
            url = baseURL.appending(path: "health")
        }

        guard let url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

import Foundation
import Network
import TranskribeCore

/// Accepts one bounded HTTP request per connection on the IPv4 loopback address.
// The listener callbacks and connection state use the same serial queue.
final class MCPHTTPListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Transkribe.MCP.HTTP")
    private let listener: NWListener
    private let handle: @Sendable (MCPHTTPHandler.Request) async -> MCPHTTPHandler.Response?
    private var connections: [UUID: NWConnection] = [:]

    init(port: UInt16, handle: @escaping @Sendable (MCPHTTPHandler.Request) async -> MCPHTTPHandler.Response?,
         onFailure: @escaping (String) -> Void) throws {
        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw AIError("The MCP port must be between 1 and 65535.")
        }
        self.handle = handle
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure(error.localizedDescription) }
        }
    }

    func start() { listener.start(queue: queue) }

    func stop() {
        listener.cancel()
        queue.async { [self] in
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 32 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 15) { [weak self, weak connection] in
            connection?.cancel()
            self?.connections[id] = nil
        }
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch MCPHTTPRequestDecoder.decode(buffer) {
            case .incomplete:
                if complete || error != nil {
                    connection.cancel()
                    self.connections[id] = nil
                } else {
                    self.receive(connection, id: id, buffer: buffer)
                }
            case .failure(let status):
                self.send(connection, id: id, status: status, headers: [:], body: Data())
            case .request(let request):
                Task { [weak self] in
                    guard let self else { connection.cancel(); return }
                    let response = await self.handle(request)
                    self.queue.async {
                        self.send(connection, id: id, status: response?.statusCode ?? 503,
                                  headers: response?.headers ?? [:], body: response?.body ?? Data())
                    }
                }
            }
        }
    }

    private func send(_ connection: NWConnection, id: UUID, status: Int, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.connections[id] = nil
        })
    }
}

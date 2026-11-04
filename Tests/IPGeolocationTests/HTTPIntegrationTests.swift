import Foundation
import Network
import XCTest
@testable import IPGeolocation

final class HTTPIntegrationTests: XCTestCase {
    func test_incompleteErrorResponsesKeepStatusOverHTTP() async throws {
        for status in [401, 429, 500] {
            let server = try PartialResponseServer(statusCode: status)
            defer { server.stop() }
            let client = IPGeolocationClient(config: try IPGeolocationClientConfig(
                apiKey: "fixture-key",
                baseURL: server.baseURL,
                requestTimeout: 2,
                resourceTimeout: 3,
                allowInsecureHTTP: true
            ))
            defer { client.close() }
            do {
                _ = try await client.lookupIPGeolocation()
                XCTFail("Expected APIError")
            } catch let error as APIError {
                XCTAssertEqual(error.statusCode, status)
                XCTAssertEqual(error.kind, APIErrorFactory.kind(for: status))
            }
        }
    }
}

private final class PartialResponseServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "http-fixture")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private(set) var baseURL = ""

    init(statusCode: Int) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        let response = Data("HTTP/1.1 \(statusCode) Error\r\nContent-Length: 1000\r\nConnection: close\r\n\r\n{".utf8)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, error in
                guard error == nil else { connection.cancel(); return }
                connection.send(content: response, completion: .contentProcessed { _ in
                    self.queue.asyncAfter(deadline: .now() + 0.1) { connection.cancel() }
                })
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 3) == .success, let port = listener.port else {
            listener.cancel()
            throw NSError(domain: "HTTPFixture", code: 1)
        }
        baseURL = "http://127.0.0.1:\(port.rawValue)"
    }

    func stop() {
        listener.cancel()
        queue.sync {
            for connection in connections { connection.cancel() }
            connections.removeAll()
        }
    }
}

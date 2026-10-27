import BenchCore
import Foundation
import Logging
import MCP

/// The SDK's stdio transport with `PreInitGuard` in front: requests that arrive before
/// `initialize` are answered here, with their own id, and never reach the server.
actor GuardedTransport: Transport {
    nonisolated let logger: Logger
    private let inner: StdioTransport
    private var preInit = PreInitGuard()
    private var upstream: AsyncThrowingStream<Data, Swift.Error>?

    init(inner: StdioTransport = StdioTransport()) {
        self.inner = inner
        self.logger = inner.logger
    }

    func connect() async throws {
        try await inner.connect()
        upstream = await inner.receive()
    }

    func disconnect() async {
        await inner.disconnect()
    }

    func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let upstream else { return AsyncThrowingStream { $0.finish() } }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await message in upstream {
                        if let reply = await self.intercept(message) {
                            try await self.inner.send(reply)
                        } else {
                            continuation.yield(message)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func intercept(_ message: Data) -> Data? {
        preInit.intercept(message)
    }
}

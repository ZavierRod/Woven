import Foundation

protocol PairVaultUpdateTransport: Sendable {
    func events() -> AsyncStream<Void>
}

/// Development-only update delivery. Production can replace this adapter with
/// APNs-triggered refreshes without changing PairVaultStore or cryptography.
struct PairDevelopmentPollingTransport: PairVaultUpdateTransport, Sendable {
    let interval: Duration

    init(interval: Duration = .seconds(2)) {
        self.interval = interval
    }

    func events() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

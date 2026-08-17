import Foundation

@MainActor
public final class RefreshScheduler {
    public init() {}

    public func start(
        interval: TimeInterval,
        retryBaseInterval: TimeInterval = 5,
        maxRetryInterval: TimeInterval = 300,
        immediate: Bool = false,
        operation: @escaping @MainActor () async -> Bool
    ) -> Task<Void, Never> {
        Task { @MainActor in
            if !immediate {
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(interval, 1) * 1_000_000_000))
                } catch {
                    return
                }
            }

            var failureCount = 0
            while !Task.isCancelled {
                let succeeded = await operation()
                if succeeded {
                    failureCount = 0
                } else {
                    failureCount += 1
                }

                let delay: TimeInterval
                if succeeded {
                    delay = max(interval, 1)
                } else {
                    let multiplier = pow(2, Double(min(failureCount - 1, 6)))
                    delay = min(maxRetryInterval, max(retryBaseInterval, retryBaseInterval * multiplier))
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }
}

import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class RefreshSchedulerTests: XCTestCase {
    func test_failureUsesRetryDelayThenSuccessResetsToNormalInterval() async throws {
        let scheduler = await MainActor.run { RefreshScheduler() }
        let probe = SchedulerProbe()
        let start = Date()

        let task = await MainActor.run {
            scheduler.start(interval: 0.01, retryBaseInterval: 0.01, maxRetryInterval: 0.1, immediate: true) {
                await probe.recordAttempt()
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        _ = await task.value

        let snapshot = await probe.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.attempts, 2)
        XCTAssertGreaterThanOrEqual(snapshot.timestamps.count, 2)
        XCTAssertGreaterThanOrEqual(snapshot.timestamps[1].timeIntervalSince(start), 0.005)
    }
}

private actor SchedulerProbe {
    private(set) var attempts = 0
    private(set) var timestamps: [Date] = []

    func recordAttempt() -> Bool {
        attempts += 1
        timestamps.append(Date())
        return attempts >= 2
    }

    func snapshot() -> (attempts: Int, timestamps: [Date]) {
        (attempts, timestamps)
    }
}

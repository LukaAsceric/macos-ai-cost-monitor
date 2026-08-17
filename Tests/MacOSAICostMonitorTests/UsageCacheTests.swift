import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class UsageCacheTests: XCTestCase {
    func test_saveThenLoadReturnsValue() throws {
        let fileURL = temporaryURL()
        let cache = UsageCache(fileURL: fileURL)
        let cost = DailyCost.empty(for: "2026-08-17")
        let fetchedAt = Date(timeIntervalSince1970: 123)

        try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt))
        let result = cache.load()

        XCTAssertEqual(result?.cost, cost)
        XCTAssertEqual(result?.fetchedAt, fetchedAt)
    }

    func test_missingCacheReturnsNil() {
        XCTAssertNil(UsageCache(fileURL: temporaryURL()).load())
    }

    func test_corruptCacheReturnsNil() throws {
        let fileURL = temporaryURL()
        try Data("not-json".utf8).write(to: fileURL)

        XCTAssertNil(UsageCache(fileURL: fileURL).load())
    }

    func test_cacheDoesNotContainAnApiKey() throws {
        let fileURL = temporaryURL()
        let cache = UsageCache(fileURL: fileURL)
        try cache.save(CachedUsage(cost: .empty(for: "2026-08-17"), fetchedAt: Date()))

        let contents = try String(contentsOf: fileURL)
        XCTAssertFalse(contents.contains("sk-or-v1"))
        XCTAssertFalse(contents.contains("management-key"))
    }

    func test_savesAndLoadsNoDataMarker() throws {
        let fileURL = temporaryURL()
        let cache = UsageCache(fileURL: fileURL)
        try cache.save(CachedUsage(cost: .empty(for: "2026-08-17"), fetchedAt: Date(), hasActivity: false))

        XCTAssertEqual(cache.load()?.hasActivity, false)
        XCTAssertNil(cache.load()?.previousCost)
    }

    func test_rejectsUnsupportedCacheVersion() throws {
        let fileURL = temporaryURL()
        try Data("{\"version\":2}".utf8).write(to: fileURL)

        XCTAssertNil(UsageCache(fileURL: fileURL).load())
    }

    private func temporaryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cache.json")
    }
}

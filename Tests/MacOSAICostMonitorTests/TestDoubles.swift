import Foundation

private final class TestURLProtocolStore: @unchecked Sendable {
    let lock = NSLock()
    var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    var lastRequest: URLRequest?
}

final class TestURLProtocol: URLProtocol {
    private static let store = TestURLProtocolStore()

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { store.withLock { store.requestHandler } }
        set { store.withLock { store.requestHandler = newValue } }
    }

    static var lastRequest: URLRequest? {
        store.withLock { store.lastRequest }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            Self.store.withLock { Self.store.lastRequest = request }
            guard let requestHandler = Self.requestHandler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        store.withLock {
            store.requestHandler = nil
            store.lastRequest = nil
        }
    }
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var value: String?
    private let lock = NSLock()

    init(value: String? = nil) { self.value = value }

    func read() throws -> String? {
        lock.withLock { value }
    }

    func save(_ value: String) throws {
        lock.withLock { self.value = value }
    }

    func delete() throws {
        lock.withLock { value = nil }
    }
}

final class InMemoryCostCache: CostCache, @unchecked Sendable {
    private var value: CachedUsage?
    private let lock = NSLock()

    init(value: CachedUsage? = nil) { self.value = value }

    func load() -> CachedUsage? {
        lock.withLock { value }
    }

    func save(_ value: CachedUsage) throws {
        lock.withLock { self.value = value }
    }
}

final class FailingCostCache: CostCache, @unchecked Sendable {
    func load() -> CachedUsage? { nil }
    func save(_ value: CachedUsage) throws { throw TestStorageError.unavailable }
}

enum TestStorageError: Error, Equatable, Sendable {
    case unavailable
}

final actor BlockingUsageProvider: UsageProvider {
    private var calls = 0
    private var called = false
    private var released = false
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func activity(for date: String, apiKey: String) async throws -> [ActivityItem] {
        calls += 1
        called = true
        let pendingCallWaiters = callWaiters
        callWaiters.removeAll()
        pendingCallWaiters.forEach { $0.resume() }

        if !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return []
    }

    func waitUntilCalled() async {
        if called { return }
        await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = releaseWaiters
        releaseWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func callCount() -> Int { calls }
}

fileprivate extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

func makeTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TestURLProtocol.self]
    return URLSession(configuration: configuration)
}

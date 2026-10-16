import Foundation

/// Slack's per-method rate-limit tiers (calls per minute).
public enum SlackTier: Sendable, Equatable {
    case tier1, tier2, tier3, tier4
    case perMinute(Int)

    public var callsPerMinute: Int {
        switch self {
        case .tier1: 1
        case .tier2: 20
        case .tier3: 50
        case .tier4: 100
        case .perMinute(let n): n
        }
    }
}

/// Sliding one-minute window per method. `reserve` returns how long to wait before calling.
public actor RateLimiter {
    private var calls: [String: [Date]] = [:]
    private var pausedUntil: [String: Date] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    public func reserve(_ method: String, tier: SlackTier) -> TimeInterval {
        let current = now()
        var window = (calls[method] ?? []).filter { current.timeIntervalSince($0) < 60 }
        var start = max(current, pausedUntil[method] ?? current)
        if window.count >= tier.callsPerMinute, let oldest = window.first {
            start = max(start, oldest.addingTimeInterval(60))
        }
        window.append(start)
        calls[method] = window
        return start.timeIntervalSince(current)
    }

    /// Called on HTTP 429: no calls to `method` until `retryAfter` seconds from now.
    public func pause(_ method: String, retryAfter: TimeInterval) {
        pausedUntil[method] = now().addingTimeInterval(retryAfter)
    }
}

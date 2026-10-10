import Foundation

/// User gestures change follow mode. Text layout alone must never reattach a reader.
public struct ConversationFollow: Equatable, Sendable {
    public private(set) var isFollowing = true
    public init() {}
    public mutating func followLatest() { isFollowing = true }
    public mutating func beginReading() { isFollowing = false }
    public mutating func userReached(distanceFromBottom: Double) {
        isFollowing = distanceFromBottom <= 6
    }
    /// During generation, absorb small temporary height reductions instead of bouncing upward.
    public static func advance(current: Double, bottom: Double, elapsed: Double, scale: Double) -> Double {
        guard current.isFinite, bottom.isFinite else { return current }
        let remaining = bottom - current
        guard remaining > 0 else { return current }
        let pixel = 1 / max(scale, 1)
        if remaining <= pixel { return bottom }
        let fraction = 1 - exp(-18 * min(max(elapsed, 1.0 / 120), 0.1))
        return min(bottom, current + max(pixel, remaining * fraction))
    }
}

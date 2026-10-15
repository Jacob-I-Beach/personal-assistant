import Foundation

/// One policy across model pickers and runtimes. This is space, not a token
/// measurement; each backend still validates its real model capacity.
public enum ContextReserve {
    public static let percent = 30
    public static func amount(in capacity: Int) -> Int {
        let safe = max(0, capacity)
        return (safe / 10) * 3 + ((safe % 10) * 3 + 9) / 10
    }
    public static func working(in capacity: Int) -> Int { max(0, capacity - amount(in: capacity)) }
}

import Foundation

/// Generic thread-safe holder for the most recently loaded value of type `T`.
/// Dashboard/Stats/Insights views get torn down and rebuilt every time you
/// switch tabs (their `@State` resets to nil), which used to make each panel
/// flash an empty state on every visit while its loader re-ran a full scan.
/// Seeding fresh view state from a cache like this means the last known
/// value stays on screen until the new load actually completes.
final class LatestValueCache<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?

    init() {}

    func current() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func update(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

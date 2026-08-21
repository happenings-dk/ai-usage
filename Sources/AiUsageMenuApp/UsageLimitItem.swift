import Foundation

/// A source-qualified live rate-limit window for dashboard presentation.
struct UsageLimitItem: Identifiable, Equatable, Sendable {
    let source: UsageSource
    let window: RateLimitWindow

    var id: String { "\(source.id)-\(window.name)" }
}

extension UsageSnapshot {
    /// Every available live limit, ordered from most to least used.
    var allRateLimits: [UsageLimitItem] {
        summaries
            .flatMap { summary in
                summary.rateLimits.map { window in
                    UsageLimitItem(source: summary.source, window: window)
                }
            }
            .sorted { lhs, rhs in
                lhs.window.usedPercent > rhs.window.usedPercent
            }
    }
}

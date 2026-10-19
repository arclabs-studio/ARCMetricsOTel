import Foundation

/// The wall clock the pipeline stamps records with. A seam so tests can control time.
protocol TelemetryClock: Sendable {
    /// The current wall-clock time.
    var now: Date { get }
}

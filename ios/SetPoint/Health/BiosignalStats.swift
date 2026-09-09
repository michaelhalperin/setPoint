import Foundation

struct BiosignalSample: Equatable {
    let value: Double
    let date: Date
}

/// Pure baseline + deviation math. The app sends only the resulting z-scores to
/// the backend (plan §4). Negative HRV / positive RHR is the under-fuelling
/// direction — the sign is preserved and interpreted server-side.
enum BiosignalStats {
    static let baselineExcludesLastHours: Double = 12
    static let recentWindowHours: Double = 12
    static let minBaselineSamples = 7

    struct Baseline: Equatable {
        let mean: Double
        let std: Double
    }

    /// Personal baseline (mean + population std) from samples older than the
    /// recent window, so a bad night doesn't move the baseline it's measured
    /// against.
    static func baseline(_ samples: [BiosignalSample], now: Date) -> Baseline? {
        let cutoff = now.addingTimeInterval(-baselineExcludesLastHours * 3600)
        let values = samples.filter { $0.date < cutoff }.map(\.value)
        guard values.count >= minBaselineSamples else { return nil }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return Baseline(mean: mean, std: max(sqrt(variance), 1e-6))
    }

    /// z-score of the mean of the last `recentWindowHours` of samples vs baseline.
    static func deviation(recent samples: [BiosignalSample], now: Date, baseline: Baseline) -> Double? {
        let cutoff = now.addingTimeInterval(-recentWindowHours * 3600)
        let values = samples.filter { $0.date >= cutoff }.map(\.value)
        guard !values.isEmpty else { return nil }

        let recentMean = values.reduce(0, +) / Double(values.count)
        let z = (recentMean - baseline.mean) / baseline.std
        return z.isFinite ? z : nil
    }

    /// Convenience: baseline + deviation in one call.
    static func zScore(_ samples: [BiosignalSample], now: Date = Date()) -> Double? {
        guard let base = baseline(samples, now: now) else { return nil }
        return deviation(recent: samples, now: now, baseline: base)
    }
}

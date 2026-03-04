// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Letter grade derived from a composite connection quality score.
///
/// Grades range from ``excellent`` (score above 0.9) to ``critical``
/// (score at or below 0.3). Conforms to `Comparable` so that
/// `excellent > good > fair > poor > critical`.
public enum QualityGrade: String, Sendable, CaseIterable, Comparable {
    case excellent
    case good
    case fair
    case poor
    case critical

    /// Initialize from a normalized score in [0.0, 1.0].
    ///
    /// - Parameter score: A quality score where 1.0 is perfect.
    public init(score: Double) {
        switch score {
        case _ where score > 0.9:
            self = .excellent
        case _ where score > 0.7:
            self = .good
        case _ where score > 0.5:
            self = .fair
        case _ where score > 0.3:
            self = .poor
        default:
            self = .critical
        }
    }

    /// Human-readable label (e.g. "Excellent", "Critical").
    public var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .critical: return "Critical"
        }
    }

    /// Comparable: excellent > good > fair > poor > critical.
    public static func < (lhs: QualityGrade, rhs: QualityGrade) -> Bool {
        let order: [QualityGrade] = [.critical, .poor, .fair, .good, .excellent]
        guard let lhsIndex = order.firstIndex(of: lhs),
            let rhsIndex = order.firstIndex(of: rhs)
        else { return false }
        return lhsIndex < rhsIndex
    }
}

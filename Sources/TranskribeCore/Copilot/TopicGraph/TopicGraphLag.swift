import Foundation

public struct TopicGraphLagRecord: Codable, Equatable, Sendable {
    public let pointIds: [String]
    public internal(set) var speechEndedAt: Date
    public let committedAt: Date
    public let routedAt: Date
    public internal(set) var namedAt: Date?

    public var sttLag: TimeInterval { committedAt.timeIntervalSince(speechEndedAt) }
    /// Speech to routing, including STT. Every routed batch supplies one sample.
    public var graphLag: TimeInterval { routedAt.timeIntervalSince(speechEndedAt) }
    /// Speech to a valid name. Only batches that receive a name supply this sample.
    public var namedLag: TimeInterval? { namedAt?.timeIntervalSince(speechEndedAt) }

    public init(pointIds: [String], speechEndedAt: Date, committedAt: Date, routedAt: Date, namedAt: Date? = nil) {
        self.pointIds = pointIds
        self.speechEndedAt = speechEndedAt
        self.committedAt = committedAt
        self.routedAt = routedAt
        self.namedAt = namedAt
    }
}

public struct TopicGraphLagSummary: Equatable, Sendable {
    public let routedSampleCount: Int
    public let namedSampleCount: Int
    public let sttMedian: TimeInterval?
    public let sttP90: TimeInterval?
    public let graphMedian: TimeInterval?
    public let graphP90: TimeInterval?
    public let namedMedian: TimeInterval?
    public let namedP90: TimeInterval?

    public init(records: [TopicGraphLagRecord]) {
        routedSampleCount = records.count
        let stt = records.map(\.sttLag).sorted()
        let graph = records.map(\.graphLag).sorted()
        let named = records.compactMap(\.namedLag).sorted()
        namedSampleCount = named.count
        sttMedian = Self.median(stt)
        sttP90 = Self.p90(stt)
        graphMedian = Self.median(graph)
        graphP90 = Self.p90(graph)
        namedMedian = Self.median(named)
        namedP90 = Self.p90(named)
    }

    /// One line per meeting. Percentiles use nearest rank. Median averages the middle pair.
    public var logLine: String {
        "Topic graph lag: routed=\(routedSampleCount) STT median=\(Self.seconds(sttMedian)) p90=\(Self.seconds(sttP90)) "
        + "speech-to-routed median=\(Self.seconds(graphMedian)) p90=\(Self.seconds(graphP90)) "
        + "named=\(namedSampleCount) speech-to-named median=\(Self.seconds(namedMedian)) p90=\(Self.seconds(namedP90))"
    }

    private static func median(_ sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func p90(_ sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        return sorted[Int(ceil(Double(sorted.count) * 0.9)) - 1]
    }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.2fs", $0) } ?? "n/a"
    }
}

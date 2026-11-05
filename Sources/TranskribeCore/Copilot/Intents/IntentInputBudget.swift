import Foundation

/// Retains recent speech and measures the complete serialized input.
enum IntentInputBudget {
    static let reserve = 1_024

    static func fit(_ segments: [Segment], maximumBytes: Int,
                    measure: ([Segment]) throws -> Int) throws -> [Segment] {
        guard maximumBytes > reserve else { return [] }
        let ordered = segments.sorted { $0.end == $1.end ? $0.start < $1.start : $0.end < $1.end }
        var lower = 0
        var upper = ordered.count
        while lower < upper {
            let count = lower + (upper - lower + 1) / 2
            if try measure(Array(ordered.suffix(count))) <= maximumBytes - reserve {
                lower = count
            } else {
                upper = count - 1
            }
        }
        if lower > 0 { return Array(ordered.suffix(lower)) }
        guard var newest = ordered.last else { return [] }
        let text = newest.text
        lower = 0
        upper = text.count
        while lower < upper {
            let count = lower + (upper - lower + 1) / 2
            newest.text = String(text.suffix(count))
            if try measure([newest]) <= maximumBytes - reserve {
                lower = count
            } else {
                upper = count - 1
            }
        }
        guard lower > 0 else { return [] }
        newest.text = String(text.suffix(lower))
        return [newest]
    }
}

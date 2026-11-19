import Foundation

/// Tells the call side's voices apart by how they sound. The speaker model is good at *when* the
/// voice changes but has a handful of voice slots, learned on two-person phone calls: in a meeting
/// it reuses a slot for several people. So the call is cut into short windows along its turns,
/// each window gets a voiceprint, and windows are grouped by voice across the whole call, as many
/// people as there are.
public enum VoiceSeparator {
    /// Windows are about this long: long enough for a usable voiceprint, short enough that one
    /// rarely holds two people.
    static let windowLength: TimeInterval = 3
    /// Up to this many windows of one turn are judged together.
    static let unitWindows = 4
    /// Shorter windows (an "Evet", a quick question) are too noisy to group; they join a voice afterwards.
    static let minimumGroupedWindow: TimeInterval = 1.5
    /// Shorter than this, a stretch gets no voiceprint at all.
    static let minimumEmbeddedWindow: TimeInterval = 0.5
    /// Two groups are one voice when their windows are, on average, at least this alike.
    public static let defaultThreshold: Float = 0.25
    /// A voice with less clear speech than this is a stray (a cough, a laugh, a window that
    /// straddled two people) and joins the closest real voice.
    static let minimumSeconds: TimeInterval = 4

    /// A stretch where only one of the speaker model's slots is talking (`slots.count == 1`), or
    /// where several overlap.
    public struct Window: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var slots: [Int]
        /// Windows cut from one uninterrupted turn share this number.
        public var piece: Int

        public var duration: TimeInterval { end - start }
        /// Only windows of one voice get a voiceprint.
        public var wantsVoiceprint: Bool { slots.count == 1 && duration >= minimumEmbeddedWindow }
    }

    /// The call cut along the speaker model's turns into windows of about `windowLength`.
    public static func windows(for turns: [SpeakerTurn]) -> [Window] {
        let edges = Set(turns.flatMap { [$0.start, $0.end] }).sorted()
        var pieces: [Window] = []
        for (start, end) in zip(edges, edges.dropFirst()) where end > start {
            let slots = Set(turns.filter { $0.start < end && start < $0.end }.map(\.speaker)).sorted()
            guard !slots.isEmpty else { continue }
            if var last = pieces.last, last.slots == slots, last.end == start {
                last.end = end
                pieces[pieces.count - 1] = last
            } else {
                pieces.append(Window(start: start, end: end, slots: slots, piece: pieces.count))
            }
        }
        return pieces.flatMap { piece -> [Window] in
            guard piece.slots.count == 1 else { return [piece] }
            let count = max(1, Int((piece.duration / windowLength).rounded()))
            let step = piece.duration / Double(count)
            return (0..<count).map { index in
                Window(start: piece.start + Double(index) * step,
                       end: index == count - 1 ? piece.end : piece.start + Double(index + 1) * step,
                       slots: piece.slots, piece: piece.piece)
            }
        }
    }

    /// New turns, one voice per person, numbered 1, 2, 3… by first appearance. `voiceprints`
    /// lines up with `windows` (nil where there is none). With `speakerCount`, exactly that many
    /// voices are kept, if there are enough windows. Without any voiceprints, `turns` comes back
    /// as it was.
    public static func separate(turns: [SpeakerTurn], windows: [Window], voiceprints: [[Float]?],
                                speakerCount: Int? = nil, threshold: Float = defaultThreshold,
                                smoothing: Smoothing = .standard) -> [SpeakerTurn] {
        precondition(windows.count == voiceprints.count)
        let grouped = windows.indices.filter { voiceprints[$0] != nil && windows[$0].duration >= minimumGroupedWindow }
        guard !grouped.isEmpty else { return turns }
        let vectors = grouped.map { Voiceprint.normalized(voiceprints[$0]!) }
        let (labels, unitVectors) = group(vectors, pieces: grouped.map { windows[$0].piece },
                                          seconds: grouped.map { windows[$0].duration }, threshold: threshold, count: speakerCount)
        let centroids = Clustering.centroids(vectors, labels: labels)
        // A window that was grouped is judged by its whole unit, like it was when grouping.
        var heard = voiceprints.map { $0.map(Voiceprint.normalized) }
        for (position, index) in grouped.enumerated() { heard[index] = unitVectors[position] }
        let voices = centroids.keys.sorted()

        // Along the call, every one-voice window takes the voice it sounds like, but changing
        // voice inside one turn costs a lot and at a pause or a change of slot little, so short
        // and unclear windows follow their neighbors.
        // The speaker model's slot is a hint too: which voices it held, by time.
        var slotShare: [Int: [Int: Float]] = [:]
        for (position, index) in grouped.enumerated() {
            slotShare[windows[index].slots[0], default: [:]][labels[position], default: 0] += Float(windows[index].duration)
        }
        slotShare = slotShare.mapValues { shares in
            let total = shares.values.reduce(0, +)
            return shares.mapValues { $0 / max(total, 1e-6) }
        }
        let single = windows.indices.filter { windows[$0].slots.count == 1 }
        let evidence = single.map { index -> [Float] in
            let share = slotShare[windows[index].slots[0]] ?? [:]
            let prior = voices.map { smoothing.slotPrior * (share[$0] ?? 0) }
            guard let print = heard[index] else { return prior }
            let weight = Float(min(windows[index].duration, windowLength) / windowLength)
            return voices.indices.map { Voiceprint.similarity(print, centroids[voices[$0]]!) * weight + prior[$0] }
        }
        let path = Self.path(evidence: evidence) { position in
            smoothing.cost(from: windows[single[position - 1]], to: windows[single[position]])
        }
        var voice = [Int?](repeating: nil, count: windows.count)
        for (position, index) in single.enumerated() { voice[index] = voices[path[position]] }

        // Where two people talk at once, each slot speaks as the voice it mostly held.
        var slotVoices: [Int: [Int: TimeInterval]] = [:]
        for index in single { slotVoices[windows[index].slots[0], default: [:]][voice[index]!, default: 0] += windows[index].duration }
        func mainVoice(of slot: Int) -> Int? { slotVoices[slot]?.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key }

        var result: [SpeakerTurn] = []
        for (index, window) in windows.enumerated() {
            let speakers = voice[index].map { [$0] } ?? Set(window.slots.compactMap(mainVoice)).sorted()
            for speaker in speakers {
                result.append(SpeakerTurn(start: window.start, end: window.end, speaker: speaker))
            }
        }
        return DiarizationEngine.renumbered(joined(result))
    }

    /// What changing voice between two neighboring windows costs, against how alike a window is
    /// to a voice (0…1).
    public struct Smoothing: Sendable {
        public var withinTurn: Float
        public var acrossShortGap: Float
        public var elsewhere: Float
        /// How much a slot's share of a voice counts, for a window in that slot.
        public var slotPrior: Float
        public static let standard = Smoothing(withinTurn: 0.15, acrossShortGap: 0.05, elsewhere: 0.01, slotPrior: 0.05)
        public static let none = Smoothing(withinTurn: 0, acrossShortGap: 0, elsewhere: 0, slotPrior: 0.05)

        public init(withinTurn: Float, acrossShortGap: Float, elsewhere: Float, slotPrior: Float) {
            self.withinTurn = withinTurn
            self.acrossShortGap = acrossShortGap
            self.elsewhere = elsewhere
            self.slotPrior = slotPrior
        }

        func cost(from a: Window, to b: Window) -> Float {
            if a.piece == b.piece { return withinTurn }
            return a.slots == b.slots && b.start - a.end < 0.5 ? acrossShortGap : elsewhere
        }
    }

    // MARK: - Helpers

    /// Groups windows into voices. Runs of up to `unitWindows` windows from one turn are judged
    /// together (the speaker model rarely misses a change of voice, only who it is), so each
    /// decision rests on more speech than a single window.
    /// Returns each window's voice and its unit's voiceprint.
    static func group(_ vectors: [[Float]], pieces: [Int], seconds: [TimeInterval], threshold: Float,
                      count: Int?) -> (labels: [Int], unitVectors: [[Float]]) {
        var units: [[Int]] = []
        for position in vectors.indices {
            if let last = units.last?.last, pieces[last] == pieces[position], units[units.count - 1].count < unitWindows {
                units[units.count - 1].append(position)
            } else {
                units.append([position])
            }
        }
        let unitVectors = units.map { unit in
            Voiceprint.normalized(unit.dropFirst().reduce(vectors[unit[0]]) { sum, position in zip(sum, vectors[position]).map(+) })
        }
        var unitLabels = Clustering.averageLinkage(unitVectors, weights: units.map(\.count), threshold: threshold, count: count)
        unitLabels = absorbStrays(unitLabels, vectors: unitVectors,
                                  seconds: units.map { $0.reduce(0) { $0 + seconds[$1] } }, keep: count)
        var labels = [Int](repeating: 0, count: vectors.count)
        var perWindow = vectors
        for (index, unit) in units.enumerated() {
            for position in unit { labels[position] = unitLabels[index]; perWindow[position] = unitVectors[index] }
        }
        return (labels, perWindow)
    }

    /// The best sequence of voices (Viterbi): most total `evidence`, minus `switchCost(t)` each
    /// time the voice changes between positions t−1 and t.
    static func path(evidence: [[Float]], switchCost: (Int) -> Float) -> [Int] {
        guard let first = evidence.first else { return [] }
        var score = first
        var back: [[Int]] = [Array(score.indices)]
        for position in evidence.indices.dropFirst() {
            let cost = switchCost(position)
            let best = score.indices.max { score[$0] < score[$1] }!
            var next = score, from = Array(score.indices)
            for voice in score.indices {
                if score[best] - cost > score[voice] { next[voice] = score[best] - cost; from[voice] = best }
                next[voice] += evidence[position][voice]
            }
            score = next
            back.append(from)
        }
        var voice = score.indices.max { score[$0] < score[$1] }!
        var result = [Int](repeating: 0, count: evidence.count)
        for position in evidence.indices.reversed() {
            result[position] = voice
            voice = back[position][voice]
        }
        return result
    }

    /// Groups with too little speech join the most alike group that has enough.
    static func absorbStrays(_ labels: [Int], vectors: [[Float]], seconds: [TimeInterval], keep: Int?) -> [Int] {
        var talk: [Int: TimeInterval] = [:]
        for (label, duration) in zip(labels, seconds) { talk[label, default: 0] += duration }
        let real = Set(talk.filter { $0.value >= minimumSeconds }.keys)
        // A count the user chose is kept even if one of those voices barely speaks.
        guard !real.isEmpty, keep == nil || real.count >= keep! else { return labels }
        let centroids = Clustering.centroids(vectors, labels: labels).filter { real.contains($0.key) }
        return zip(labels, vectors).map { label, vector in
            real.contains(label) ? label
                : centroids.max { Voiceprint.similarity(vector, $0.value) < Voiceprint.similarity(vector, $1.value) }!.key
        }
    }

    /// Back-to-back windows of the same voice become one turn.
    private static func joined(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
        var result: [SpeakerTurn] = []
        for turn in turns.sorted(by: { ($0.start, $0.speaker) < ($1.start, $1.speaker) }) {
            if let index = result.lastIndex(where: { $0.speaker == turn.speaker }), result[index].end >= turn.start - 0.01 {
                result[index].end = max(result[index].end, turn.end)
            } else {
                result.append(turn)
            }
        }
        return result
    }
}

/// Grouping voiceprints by how alike they are.
enum Clustering {
    /// Average-linkage agglomerative clustering on cosine similarity of normalized vectors.
    /// Groups merge while their average similarity is at least `threshold`, or, with `count`,
    /// until that many groups are left. Returns a group number per vector (0, 1, 2…).
    static func averageLinkage(_ vectors: [[Float]], weights: [Int]? = nil, threshold: Float, count: Int? = nil) -> [Int] {
        let n = vectors.count
        guard n > 1 else { return Array(repeating: 0, count: n) }
        var similarity = [Float](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let score = Voiceprint.similarity(vectors[i], vectors[j])
                similarity[i * n + j] = score
                similarity[j * n + i] = score
            }
        }
        let merges = nearestNeighborChain(&similarity, n: n, sizes: weights ?? Array(repeating: 1, count: n))
        // Replaying merges from most to least alike rebuilds the tree at any cut.
        var parent = Array(0..<n)
        func root(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        var groups = n
        for merge in merges.sorted(by: { $0.score > $1.score }) {
            if let count { if groups <= max(1, count) { break } } else if merge.score < threshold { break }
            parent[root(merge.a)] = root(merge.b)
            groups -= 1
        }
        var numbers: [Int: Int] = [:]
        return (0..<n).map { index in
            let group = root(index)
            if let number = numbers[group] { return number }
            numbers[group] = numbers.count
            return numbers.count - 1
        }
    }

    /// The nearest-neighbor chain algorithm for average linkage: every merge in O(n²) total.
    /// `similarity` is an n×n matrix and is used up.
    private static func nearestNeighborChain(_ similarity: inout [Float], n: Int, sizes: [Int]) -> [(a: Int, b: Int, score: Float)] {
        var size = sizes
        var active = Set(0..<n)
        var chain: [Int] = []
        var merges: [(a: Int, b: Int, score: Float)] = []
        while active.count > 1 {
            if chain.isEmpty { chain.append(active.min()!) }
            let a = chain[chain.count - 1]
            let previous = chain.count >= 2 ? chain[chain.count - 2] : nil
            var best = previous ?? -1
            var bestScore = previous.map { similarity[a * n + $0] } ?? -.infinity
            for k in active where k != a && similarity[a * n + k] > bestScore {
                best = k
                bestScore = similarity[a * n + k]
            }
            guard best == previous else { chain.append(best); continue }
            chain.removeLast(2)
            merges.append((a, best, bestScore))
            // Lance–Williams update for average linkage; `a` now stands for both.
            let wa = Float(size[a]), wb = Float(size[best])
            for k in active where k != a && k != best {
                let merged = (wa * similarity[a * n + k] + wb * similarity[best * n + k]) / (wa + wb)
                similarity[a * n + k] = merged
                similarity[k * n + a] = merged
            }
            size[a] += size[best]
            active.remove(best)
        }
        return merges
    }

    /// The normalized mean voiceprint of each group.
    static func centroids(_ vectors: [[Float]], labels: [Int], weights: [Int]? = nil) -> [Int: [Float]] {
        var sums: [Int: [Float]] = [:]
        for (index, (vector, label)) in zip(vectors, labels).enumerated() {
            let weighted = vector.map { $0 * Float(weights?[index] ?? 1) }
            sums[label] = sums[label].map { zip($0, weighted).map(+) } ?? weighted
        }
        return sums.mapValues(Voiceprint.normalized)
    }
}

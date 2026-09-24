import Foundation

/// The order a question's options are shown in, and the one translation that
/// every screen marking a shuffled question has to get right.
///
/// There are two ways to number an option. The SLOT is where it sits on the
/// screen (A is slot 0). The ORIGINAL index is its place in the question's own
/// `options`, which is what `correctIndex`, the answer log's `picked`, the
/// summary and the store all use. `order[slot]` is the original index shown in
/// that slot. Marking compares original with original, always, so a slot can
/// never be compared with `correctIndex` by mistake.
///
/// Foundation only, so the tests can run it.
enum OptionOrder {

    /// `order` if it is a real ordering of `count` options - each index from
    /// 0 to count-1 exactly once - and the options in their written order if
    /// not. A saved order can go stale when a question is edited, and an order
    /// that points past the end of the list would crash or mark the wrong
    /// option.
    static func valid(_ order: [Int]?, count: Int) -> [Int] {
        let identity: [Int] = Array(0..<max(0, count))
        guard let order, order.count == count else { return identity }
        let sorted: [Int] = order.sorted()
        return sorted == identity ? order : identity
    }

    /// A fresh order: shuffled, or as written.
    static func make(count: Int, shuffle: Bool) -> [Int] {
        let identity: [Int] = Array(0..<max(0, count))
        return shuffle ? identity.shuffled() : identity
    }

    /// The original index of the option in `slot`, or nil for no such slot.
    static func original(ofSlot slot: Int?, in order: [Int]) -> Int? {
        guard let slot, order.indices.contains(slot) else { return nil }
        return order[slot]
    }

    /// The slot showing the option whose original index is `original`.
    static func slot(of original: Int, in order: [Int]) -> Int? {
        order.firstIndex(of: original)
    }

    /// Whether the option in `slot` is the right answer.
    static func isCorrect(slot: Int?, correctIndex: Int, order: [Int]) -> Bool {
        guard let picked = original(ofSlot: slot, in: order) else { return false }
        return picked == correctIndex
    }
}

/// Tracks producer completion independently of the user's terminal reception state.
public struct ImportPromiseCompletion: Sendable {
    private var identities: [Int: Set<String>] = [:]
    private var counts: [Int: Int] = [:]
    private var unlistedFailures: Set<Int> = []

    public init() {}

    @discardableResult
    public mutating func record(receiver: Int, identity: String?, failedWithoutNames: Bool) -> Bool {
        if let identity, !identities[receiver, default: []].insert(identity).inserted { return false }
        counts[receiver, default: 0] += 1
        if failedWithoutNames { unlistedFailures.insert(receiver) }
        return true
    }

    public func completedReceivers(expectedCounts: [Int]) -> Set<Int> {
        Set(expectedCounts.indices.filter { index in
            let expected = expectedCounts[index]
            return expected > 0 ? counts[index, default: 0] >= expected : unlistedFailures.contains(index)
        })
    }
}

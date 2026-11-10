public struct ImportBudget: Sendable, Equatable {
    public let kinds: [ExpectedKind]
    public init(kinds: [ExpectedKind]) { self.kinds = kinds }

    public var byteLimit: UInt64 {
        kinds.reduce(0) { total, kind in
            let (sum, overflow) = total.addingReportingOverflow(kind.byteLimit)
            return overflow ? .max : sum
        }
    }

    public func exceedsCapacity(_ observedBytes: UInt64) -> Bool { observedBytes > byteLimit }

    public func expiredIndices(elapsed: Double, completed: Set<Int> = []) -> [Int] {
        kinds.indices.filter { !completed.contains($0) && (!elapsed.isFinite || elapsed >= kinds[$0].timeout) }
    }
}

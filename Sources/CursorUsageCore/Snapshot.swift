import Foundation

public struct ModelRow: Equatable, Sendable {
    public var name: String
    public var tokens: Int
    public var percent: Double

    public init(name: String, tokens: Int, percent: Double) {
        self.name = name
        self.tokens = tokens
        self.percent = percent
    }
}

public struct UsagePool: Equatable, Sendable {
    public var percent: Double
    public var models: [ModelRow]

    public init(percent: Double, models: [ModelRow]) {
        self.percent = percent
        self.models = models
    }

    public var tokens: Int { models.reduce(0) { $0 + $1.tokens } }
}

public struct UsageSnapshot: Equatable, Sendable {
    public var cycleStart: Date
    public var cycleEnd: Date
    public var cursor: UsagePool
    public var other: UsagePool

    public init(cycleStart: Date, cycleEnd: Date, cursor: UsagePool, other: UsagePool) {
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.cursor = cursor
        self.other = other
    }
}

public struct PeriodUsage: Equatable, Sendable {
    public var cycleStart: Date
    public var cycleEnd: Date
    public var cursorPercent: Double
    public var otherPercent: Double
    public var bucket: [String]

    public init(cycleStart: Date, cycleEnd: Date, cursorPercent: Double, otherPercent: Double, bucket: [String]) {
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.cursorPercent = cursorPercent
        self.otherPercent = otherPercent
        self.bucket = bucket
    }
}

public struct ModelEvent: Equatable, Sendable {
    public var name: String
    public var tokens: Int
    public var cents: Double

    public init(name: String, tokens: Int, cents: Double) {
        self.name = name
        self.tokens = tokens
        self.cents = cents
    }
}

public enum UsageMath {
    public static func makeSnapshot(period: PeriodUsage, events: [ModelEvent]) -> UsageSnapshot {
        let merged = merge(events)
        let bucket = Set(period.bucket)
        let cursor = merged.filter { ModelGroups.isCursorModel($0.name, bucket: bucket) }
        let other = merged.filter { !ModelGroups.isCursorModel($0.name, bucket: bucket) }
        return UsageSnapshot(
            cycleStart: period.cycleStart,
            cycleEnd: period.cycleEnd,
            cursor: pool(percent: period.cursorPercent, events: cursor),
            other: pool(percent: period.otherPercent, events: other)
        )
    }

    private struct Accumulator {
        var name: String
        var tokens: Int
        var cents: Double
    }

    private static func merge(_ events: [ModelEvent]) -> [Accumulator] {
        var byName: [String: Accumulator] = [:]
        for event in events {
            var current = byName[event.name] ?? Accumulator(name: event.name, tokens: 0, cents: 0)
            current.tokens += event.tokens
            current.cents += event.cents
            byName[event.name] = current
        }
        return Array(byName.values)
    }

    private static func pool(percent: Double, events: [Accumulator]) -> UsagePool {
        let usable = events.filter { $0.tokens > 0 || $0.cents > 0 }
        let centsSum = usable.reduce(0.0) { $0 + $1.cents }
        let tokenSum = usable.reduce(0) { $0 + $1.tokens }
        let target = tenths(percent)
        var shares = usable.map { item -> (Accumulator, Int) in
            let raw: Double
            if centsSum > 0 {
                raw = percent * item.cents / centsSum
            } else if tokenSum > 0 {
                raw = percent * Double(item.tokens) / Double(tokenSum)
            } else {
                raw = 0
            }
            return (item, tenths(raw))
        }
        if let index = adjustmentIndex(shares) {
            shares[index].1 += target - shares.reduce(0) { $0 + $1.1 }
        }
        let models = shares.map { item, share in
            ModelRow(
                name: ModelGroups.displayName(item.name),
                tokens: item.tokens,
                percent: Double(share) / 10
            )
        }.sorted { lhs, rhs in
            if lhs.percent != rhs.percent { return lhs.percent > rhs.percent }
            if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
            return lhs.name < rhs.name
        }
        return UsagePool(percent: percent, models: models)
    }

    private static func adjustmentIndex(_ shares: [(Accumulator, Int)]) -> Int? {
        shares.indices.max { lhs, rhs in
            let left = shares[lhs].0
            let right = shares[rhs].0
            if left.cents != right.cents { return left.cents < right.cents }
            if left.tokens != right.tokens { return left.tokens < right.tokens }
            return left.name > right.name
        }
    }

    private static func tenths(_ value: Double) -> Int {
        Int((value * 10).rounded())
    }
}

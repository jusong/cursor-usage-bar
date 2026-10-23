import Foundation

public enum UsageDecodeError: Error, Equatable {
    case unrecognized
}

public enum UsageDecoding {
    public static func decodePeriod(_ data: Data) throws -> PeriodUsage {
        guard let object = jsonObject(data) else { throw UsageDecodeError.unrecognized }
        guard
            let plan = object["planUsage"] as? [String: Any],
            let cursor = doubleValue(plan["autoPercentUsed"]),
            let other = doubleValue(plan["apiPercentUsed"]),
            let start = dateValue(object["billingCycleStart"]),
            let end = dateValue(object["billingCycleEnd"])
        else {
            throw UsageDecodeError.unrecognized
        }
        let bucket = object["autoBucketModels"] as? [String] ?? []
        return PeriodUsage(
            cycleStart: start,
            cycleEnd: end,
            cursorPercent: cursor,
            otherPercent: other,
            bucket: bucket
        )
    }

    public static func decodeEvents(_ data: Data) throws -> [ModelEvent] {
        guard let object = jsonObject(data) else { throw UsageDecodeError.unrecognized }
        guard let rows = object["aggregations"] else { return [] }
        guard let rows = rows as? [[String: Any]] else { throw UsageDecodeError.unrecognized }
        return rows.compactMap { row in
            guard let name = row["modelIntent"] as? String, !name.isEmpty else { return nil }
            let tokens = intValue(row["inputTokens"])
                + intValue(row["outputTokens"])
                + intValue(row["cacheReadTokens"])
                + intValue(row["cacheWriteTokens"])
            return ModelEvent(name: name, tokens: tokens, cents: doubleValue(row["totalCents"]) ?? 0)
        }
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as Int: return number
        case let number as Double: return Int(number)
        case let number as NSNumber: return number.intValue
        case let text as String:
            if let number = Int(text) { return number }
            if let number = Double(text) { return Int(number) }
            return 0
        default:
            return 0
        }
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let millis = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}

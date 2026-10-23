import Foundation
import CursorUsageCore

nonisolated(unsafe) var failures: [String] = []

func expect(_ condition: Bool, _ message: String = "failed", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        failures.append("\(file):\(line) \(message)")
    }
}

func expectThrows<T: Error & Equatable>(_ expected: T, file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void) {
    do {
        try body()
        expect(false, "expected \(expected)", file: file, line: line)
    } catch let error as T {
        expect(error == expected, "got \(error)", file: file, line: line)
    } catch {
        expect(false, "got \(error)", file: file, line: line)
    }
}

func detailTokenUnits() {
    expect(UsageText.detailTokens(236_271_557) == "2.4亿", UsageText.detailTokens(236_271_557))
    expect(UsageText.detailTokens(596_849_696) == "6亿")
    expect(UsageText.detailTokens(100_000_000) == "1亿")
    expect(UsageText.detailTokens(150_000_000) == "1.5亿")
    expect(UsageText.detailTokens(32_714_265) == "3271.4万")
    expect(UsageText.detailTokens(30_884_712) == "3088.5万")
    expect(UsageText.detailTokens(796_735) == "79.7万")
    expect(UsageText.detailTokens(10_000) == "1万")
    expect(UsageText.detailTokens(9_999) == "9999")
    expect(UsageText.detailTokens(0) == "0")
}

func barTokenUnitsKeepADecimalForYi() {
    expect(UsageText.barTokens(596_849_696) == "6.0亿", UsageText.barTokens(596_849_696))
    expect(UsageText.barTokens(150_000_000) == "1.5亿")
    expect(UsageText.barTokens(59_216_900) == "5922万", UsageText.barTokens(59_216_900))
    expect(UsageText.barTokens(32_714_265) == "3271万")
    expect(UsageText.barTokens(9_999) == "9999")
}

func percents() {
    expect(UsageText.detailPercent(93.37777777777778) == "93.4%")
    expect(UsageText.detailPercent(9) == "9.0%")
    expect(UsageText.barPercent(93.37777777777778) == "93%")
    expect(UsageText.barPercent(63.511111111111106) == "64%")
}

func menuBarModes() {
    let snapshot = sampleSnapshot()
    expect(UsageText.menuBar(snapshot, mode: .percent) == "Cursor 93% · Other 64%", UsageText.menuBar(snapshot, mode: .percent))
    expect(
        UsageText.menuBar(snapshot, mode: .percentAndTokens) == "Cursor 6.0亿 93% · Other 5922万 64%",
        UsageText.menuBar(snapshot, mode: .percentAndTokens)
    )
    expect(UsageText.menuBar(snapshot, mode: .tokens) == "Cursor 6.0亿 · Other 5922万")
    expect(DisplayMode(stored: nil) == .percent)
    expect(DisplayMode(stored: "nope") == .percent)
    expect(DisplayMode(stored: "tokens") == .tokens)
}

func cycleUsesGivenTimeZone() {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let start = Date(timeIntervalSince1970: 1_790_490_119)
    let end = Date(timeIntervalSince1970: 1_793_082_119)
    expect(UsageText.cycle(start, end, timeZone: zone) == "Sep 27, 2026 – Oct 27, 2026")
}

func familyAndFallbackBuckets() {
    let bucket: Set<String> = ["grok-4.5-high-fast", "default", "composer-2.5"]
    expect(ModelGroups.isCursorModel("grok-4.7-high", bucket: bucket))
    expect(ModelGroups.isCursorModel("default", bucket: bucket))
    expect(ModelGroups.isCursorModel("auto", bucket: bucket))
    expect(!ModelGroups.isCursorModel("gpt-5.6-sol-medium", bucket: bucket))
    expect(!ModelGroups.isCursorModel("vega", bucket: bucket))
    expect(ModelGroups.isCursorModel("composer-2.5", bucket: []))
    expect(ModelGroups.isCursorModel("cursor-grok-4.5", bucket: []))
    expect(ModelGroups.isCursorModel("grok-4.7-high", bucket: []))
    expect(ModelGroups.isCursorModel("auto", bucket: []))
    expect(!ModelGroups.isCursorModel("claude-opus-5-5-medium", bucket: []))
    expect(!ModelGroups.isCursorModel("vega", bucket: []))
    expect(ModelGroups.displayName("default") == "auto")
}

func snapshotSplitsPoolsAndBalancesRoundedPercents() {
    let snapshot = UsageMath.makeSnapshot(period: samplePeriod(), events: sampleEvents())
    expect(snapshot.cursor.models.map(\.name) == [
        "grok-4.7-high", "grok-4.7-xhigh", "auto", "grok-4.7-high-fast",
    ])
    expect(snapshot.cursor.models.map { UsageText.detailPercent($0.percent) } == ["33.0%", "29.0%", "22.4%", "9.0%"])
    expect(snapshot.cursor.tokens == 596_849_696)
    expect(roundedTenths(snapshot.cursor.models.map(\.percent)) == roundedTenths([snapshot.cursor.percent]))
    expect(snapshot.other.models.map(\.name) == [
        "gpt-5.6-sol-medium",
        "glm-5.2-high",
        "glm-5p3-high",
        "claude-opus-5-5-medium",
        "kimi-k3-max",
        "glm-5p3-flash-high",
    ])
    expect(snapshot.other.models.map { UsageText.detailPercent($0.percent) } == ["41.0%", "11.6%", "5.8%", "3.5%", "1.5%", "0.1%"])
    expect(roundedTenths(snapshot.other.models.map(\.percent)) == roundedTenths([snapshot.other.percent]))
}

func zeroCentsFallBackToTokens() {
    let period = PeriodUsage(
        cycleStart: Date(timeIntervalSince1970: 0),
        cycleEnd: Date(timeIntervalSince1970: 10),
        cursorPercent: 10,
        otherPercent: 0,
        bucket: ["composer-2"]
    )
    let events = [
        ModelEvent(name: "composer-2", tokens: 30, cents: 0),
        ModelEvent(name: "composer-2-fast", tokens: 70, cents: 0),
        ModelEvent(name: "idle", tokens: 0, cents: 0),
    ]
    let snapshot = UsageMath.makeSnapshot(period: period, events: events)
    expect(snapshot.cursor.models.map(\.name) == ["composer-2-fast", "composer-2"])
    expect(snapshot.cursor.models.map { UsageText.detailPercent($0.percent) } == ["7.0%", "3.0%"])
    expect(snapshot.other.models.isEmpty)
}

func mergesDuplicateModels() {
    let period = PeriodUsage(
        cycleStart: Date(timeIntervalSince1970: 0),
        cycleEnd: Date(timeIntervalSince1970: 10),
        cursorPercent: 10,
        otherPercent: 0,
        bucket: ["composer-2"]
    )
    let events = [
        ModelEvent(name: "composer-2", tokens: 10, cents: 1),
        ModelEvent(name: "composer-2", tokens: 15, cents: 1),
    ]
    let snapshot = UsageMath.makeSnapshot(period: period, events: events)
    expect(snapshot.cursor.models.count == 1)
    expect(snapshot.cursor.models[0].tokens == 25)
}

func decodePeriodAndEvents() throws {
    let period = try UsageDecoding.decodePeriod(periodJSON)
    expect(abs(period.cursorPercent - 93.37777777777778) < 0.000_000_1)
    expect(abs(period.otherPercent - 63.511111111111106) < 0.000_000_1)
    expect(period.cycleStart == Date(timeIntervalSince1970: 1_790_490_119))
    expect(period.bucket == ["default", "grok-4.5-high"])

    let events = try UsageDecoding.decodeEvents(eventsJSON)
    expect(events.count == 2)
    expect(events[0].name == "grok-4.7-high")
    expect(events[0].tokens == 236_271_557)
    expect(abs(events[0].cents - 14827.43923) < 0.000_001)
    expect(events[1].tokens == 12)
}

func decodeRejectsMissingPercents() {
    expectThrows(UsageDecodeError.unrecognized) {
        _ = try UsageDecoding.decodePeriod(Data("{}".utf8))
    }
}

func sessionCookie() throws {
    expect(SessionCookie.userID(fromSub: "auth0|user_01ABC") == "user_01ABC")
    expect(SessionCookie.userID(fromSub: "user_01ABC") == "user_01ABC")
    expect(SessionCookie.header(userID: "user_01ABC", jwt: "eyJ.payload.sig") == "WorkosCursorSessionToken=user_01ABC%3A%3AeyJ.payload.sig")

    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-usage-\(UUID().uuidString).vscdb")
    expectThrows(SessionError.notSignedIn) {
        _ = try SessionCookie.readToken(database: missing)
    }

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-usage-\(UUID().uuidString).vscdb")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [url.path, "CREATE TABLE ItemTable (key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'jwt-from-db');"]
    try process.run()
    process.waitUntilExit()
    expect(try SessionCookie.readToken(database: url) == "jwt-from-db")
    try? FileManager.default.removeItem(at: url)

    let header = SessionCookie.userID(fromJWT: jwtWithSub("github|user_01XYZ"))
    expect(header == "user_01XYZ")

    let start = Date(timeIntervalSince1970: 1_790_490_119)
    let end = Date(timeIntervalSince1970: 1_793_082_119)
    let request = UsageAPI.eventsRequest(cookie: "cookie", start: start, end: end)
    expect(request.httpMethod == "POST")
    expect(request.value(forHTTPHeaderField: "Origin") == "https://cursor.com")
    expect(request.value(forHTTPHeaderField: "Cookie") == "cookie")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
    expect(body?["startDate"] == "1790490119000")
    expect(body?["endDate"] == "1793082119000")
}

func jwtWithSub(_ sub: String) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["sub": sub])
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(encoded).sig"
}

func roundedTenths(_ values: [Double]) -> Int {
    Int((values.reduce(0, +) * 10).rounded())
}

func samplePeriod() -> PeriodUsage {
    PeriodUsage(
        cycleStart: Date(timeIntervalSince1970: 1_790_490_119),
        cycleEnd: Date(timeIntervalSince1970: 1_793_082_119),
        cursorPercent: 93.37777777777778,
        otherPercent: 63.511111111111106,
        bucket: ["default", "grok-4.5-high-fast", "composer-2.5"]
    )
}

func sampleEvents() -> [ModelEvent] {
    [
        ModelEvent(name: "grok-4.7-high", tokens: 236_271_557, cents: 14827.43923),
        ModelEvent(name: "grok-4.7-xhigh", tokens: 179_555_068, cents: 13056.82283),
        ModelEvent(name: "default", tokens: 148_308_806, cents: 10069.507865),
        ModelEvent(name: "grok-4.7-high-fast", tokens: 32_714_265, cents: 4066.0868),
        ModelEvent(name: "gpt-5.6-sol-medium", tokens: 30_884_712, cents: 1847.67322),
        ModelEvent(name: "glm-5.2-high", tokens: 17_718_640, cents: 522.023852),
        ModelEvent(name: "glm-5p3-high", tokens: 7_069_627, cents: 260.04036),
        ModelEvent(name: "claude-opus-5-5-medium", tokens: 2_273_405, cents: 157.0843),
        ModelEvent(name: "kimi-k3-max", tokens: 473_781, cents: 67.3023),
        ModelEvent(name: "glm-5p3-flash-high", tokens: 796_735, cents: 4.334059),
    ]
}

func sampleSnapshot() -> UsageSnapshot {
    UsageMath.makeSnapshot(period: samplePeriod(), events: sampleEvents())
}

let periodJSON = Data("""
{
  "billingCycleStart": "1790490119000",
  "billingCycleEnd": "1793082119000",
  "planUsage": {
    "autoPercentUsed": 93.37777777777778,
    "apiPercentUsed": 63.511111111111106
  },
  "autoBucketModels": ["default", "grok-4.5-high"]
}
""".utf8)

let eventsJSON = Data("""
{
  "aggregations": [
    {
      "modelIntent": "grok-4.7-high",
      "inputTokens": "100",
      "outputTokens": "20",
      "cacheReadTokens": "236271437",
      "totalCents": 14827.43923
    },
    {
      "modelIntent": "tiny",
      "inputTokens": 12,
      "outputTokens": "0",
      "cacheReadTokens": "0",
      "cacheWriteTokens": "0",
      "totalCents": 1
    }
  ]
}
""".utf8)

detailTokenUnits()
barTokenUnitsKeepADecimalForYi()
percents()
menuBarModes()
cycleUsesGivenTimeZone()
familyAndFallbackBuckets()
snapshotSplitsPoolsAndBalancesRoundedPercents()
zeroCentsFallBackToTokens()
mergesDuplicateModels()
try decodePeriodAndEvents()
decodeRejectsMissingPercents()
try sessionCookie()

if failures.isEmpty {
    print("ok")
} else {
    for failure in failures {
        print(failure)
    }
    exit(EXIT_FAILURE)
}

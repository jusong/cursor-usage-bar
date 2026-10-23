import AppKit
import CursorUsageCore
import Foundation

@MainActor
final class UsageBoard: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let columnsView = StatusColumnsView()
    private let menu = NSMenu()
    private var mode = DisplayMode(stored: UserDefaults.standard.string(forKey: "displayMode"))
    private var phase: Phase = .loading
    private var refreshing = false
    private var timer: Timer?

    private static let modeKey = "displayMode"

    private enum Phase {
        case loading
        case signedOut
        case failed
        case stale(UsageSnapshot, at: Date)
        case partial(PeriodUsage)
        case ready(UsageSnapshot)
    }

    func start() {
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            button.image = nil
            button.title = ""
            button.imagePosition = .imageOnly
            columnsView.frame = button.bounds
            columnsView.autoresizingMask = [.width, .height]
            button.addSubview(columnsView)
        }
        renderTitle()
        populate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            let result = await Self.load()
            refreshing = false
            apply(result)
        }
    }

    nonisolated static func load() async -> LoadResult {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        let jwt: String
        do {
            jwt = try SessionCookie.readToken(database: database)
        } catch {
            return .signedOut
        }
        guard let userID = SessionCookie.userID(fromJWT: jwt) else { return .signedOut }
        let cookie = SessionCookie.header(userID: userID, jwt: jwt)
        let period: PeriodUsage
        do {
            let data = try await fetch(UsageAPI.periodRequest(cookie: cookie))
            period = try UsageDecoding.decodePeriod(data)
        } catch {
            return .periodFailed
        }
        do {
            let data = try await fetch(UsageAPI.eventsRequest(cookie: cookie, start: period.cycleStart, end: period.cycleEnd))
            let events = try UsageDecoding.decodeEvents(data)
            return .ready(UsageMath.makeSnapshot(period: period, events: events))
        } catch {
            return .eventsFailed(period)
        }
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func apply(_ result: LoadResult) {
        switch result {
        case .signedOut:
            phase = .signedOut
        case .periodFailed:
            switch phase {
            case .ready(let snapshot), .stale(let snapshot, _):
                phase = .stale(snapshot, at: Date())
            default:
                phase = .failed
            }
        case .eventsFailed(let period):
            phase = .partial(period)
        case .ready(let snapshot):
            phase = .ready(snapshot)
        }
        renderTitle()
        populate()
    }

    private func renderTitle() {
        switch phase {
        case .signedOut:
            columnsView.plain = "未登录"
            columnsView.columns = []
        case .loading, .failed:
            columnsView.plain = nil
            columnsView.columns = [
                StatusColumnsView.Column(label: "Cursor", value: "—", tint: .cursor),
                StatusColumnsView.Column(label: "Other", value: "—", tint: .other),
            ]
        case .ready(let snapshot), .stale(let snapshot, _):
            columnsView.plain = nil
            columnsView.columns = readout(
                cursorPercent: snapshot.cursor.percent,
                otherPercent: snapshot.other.percent,
                cursorTokens: snapshot.cursor.tokens,
                otherTokens: snapshot.other.tokens
            )
        case .partial(let period):
            columnsView.plain = nil
            columnsView.columns = readout(
                cursorPercent: period.cursorPercent,
                otherPercent: period.otherPercent,
                cursorTokens: nil,
                otherTokens: nil
            )
        }
        let width = columnsView.preferredWidth()
        statusItem.length = width
        if let button = statusItem.button {
            columnsView.frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
        }
    }

    private func readout(cursorPercent: Double, otherPercent: Double, cursorTokens: Int?, otherTokens: Int?) -> [StatusColumnsView.Column] {
        [
            StatusColumnsView.Column(
                label: "Cursor",
                value: StatusReadout.value(percent: cursorPercent, tokens: cursorTokens, mode: mode),
                tint: .cursor
            ),
            StatusColumnsView.Column(
                label: "Other",
                value: StatusReadout.value(percent: otherPercent, tokens: otherTokens, mode: mode),
                tint: .other
            ),
        ]
    }

    private func populate() {
        menu.removeAllItems()
        switch phase {
        case .loading:
            addHeader(period: nil, message: "正在读取用量", warning: nil, to: menu)
        case .signedOut:
            addHeader(period: nil, message: "请先打开 Cursor 并登录", warning: nil, to: menu)
        case .failed:
            addHeader(period: nil, message: "用量暂时拉不下来", warning: nil, to: menu)
        case .stale(let snapshot, let failedAt):
            addSnapshot(snapshot, warning: "\(clock.string(from: failedAt)) 刷新失败，下面仍是上次的用量", to: menu)
        case .partial(let period):
            addHeader(period: cycle(period.cycleStart, period.cycleEnd), message: nil, warning: nil, to: menu)
            addLine(UsageLine(name: "Cursor Models", tokens: nil, percent: UsageText.detailPercent(period.cursorPercent), kind: .pool, tint: .cursor), to: menu)
            menu.addItem(.separator())
            addLine(UsageLine(name: "Other Models", tokens: nil, percent: UsageText.detailPercent(period.otherPercent), kind: .pool, tint: .other), to: menu)
            addLine(UsageLine(name: "模型明细暂时不可用", tokens: nil, percent: nil, kind: .note), to: menu)
        case .ready(let snapshot):
            addSnapshot(snapshot, warning: nil, to: menu)
        }
        menu.addItem(.separator())
        menu.addItem(displayMenu)
        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addSnapshot(_ snapshot: UsageSnapshot, warning: String?, to menu: NSMenu) {
        addHeader(period: cycle(snapshot.cycleStart, snapshot.cycleEnd), message: nil, warning: warning, to: menu)
        addPool("Cursor Models", snapshot.cursor, tint: .cursor, to: menu)
        menu.addItem(.separator())
        addPool("Other Models", snapshot.other, tint: .other, to: menu)
    }

    private func addPool(_ title: String, _ pool: UsagePool, tint: UsageTint, to menu: NSMenu) {
        addLine(UsageLine(
            name: title,
            tokens: UsageText.detailTokens(pool.tokens),
            percent: UsageText.detailPercent(pool.percent),
            kind: .pool,
            tint: tint
        ), to: menu)
        if pool.models.isEmpty {
            addLine(UsageLine(name: "这个账期没有用量", tokens: nil, percent: nil, kind: .note), to: menu)
            return
        }
        for model in pool.models {
            addLine(UsageLine(
                name: model.name,
                tokens: UsageText.detailTokens(model.tokens),
                percent: UsageText.detailPercent(model.percent),
                kind: .model,
                tint: tint
            ), to: menu)
        }
    }

    private func addHeader(period: String?, message: String?, warning: String?, to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = PeriodHeaderView(period: period, message: message, warning: warning)
        menu.addItem(item)
    }

    private func addLine(_ line: UsageLine, to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = UsageLineView(line: line)
        menu.addItem(item)
    }

    private func cycle(_ start: Date, _ end: Date) -> String {
        UsageText.cycle(start, end, timeZone: .current)
    }

    private var displayMenu: NSMenuItem {
        let root = NSMenuItem(title: "顶部栏显示", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let choices: [(String, DisplayMode)] = [
            ("百分比", .percent),
            ("百分比和 token", .percentAndTokens),
            ("仅 token", .tokens),
        ]
        for (title, value) in choices {
            let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = value == mode ? .on : .off
            submenu.addItem(item)
        }
        root.submenu = submenu
        return root
    }

    private var clock: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        mode = DisplayMode(stored: raw)
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        sender.menu?.items.forEach { $0.state = .off }
        sender.state = .on
        renderTitle()
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

enum LoadResult {
    case signedOut
    case periodFailed
    case eventsFailed(PeriodUsage)
    case ready(UsageSnapshot)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let board = UsageBoard()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            board.start()
        }
    }
}

if CommandLine.arguments.contains("--dump") {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let result = await UsageBoard.load()
        switch result {
        case .signedOut:
            print("未登录")
        case .periodFailed:
            print("用量暂时拉不下来")
        case .eventsFailed(let period):
            print(UsageText.menuBar(
                cursorPercent: period.cursorPercent,
                otherPercent: period.otherPercent,
                cursorTokens: nil,
                otherTokens: nil,
                mode: .percent
            ))
            print("模型明细暂时不可用")
        case .ready(let snapshot):
            print(UsageText.menuBar(snapshot, mode: .percent))
            print(UsageText.menuBar(snapshot, mode: .percentAndTokens))
            print(UsageText.menuBar(snapshot, mode: .tokens))
            print(UsageText.cycle(snapshot.cycleStart, snapshot.cycleEnd, timeZone: TimeZone(identifier: "Asia/Shanghai")!))
            for (title, pool) in [("Cursor Models", snapshot.cursor), ("Other Models", snapshot.other)] {
                print("\(title) \(UsageText.detailLine(tokens: pool.tokens, percent: pool.percent))")
                for model in pool.models {
                    print("  \(model.name) \(UsageText.detailLine(tokens: model.tokens, percent: model.percent))")
                }
            }
        }
        semaphore.signal()
    }
    let deadline = Date(timeIntervalSinceNow: 20)
    while semaphore.wait(timeout: .now()) == .timedOut {
        if Date() > deadline {
            fputs("dump timed out\n", stderr)
            exit(EXIT_FAILURE)
        }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

import Foundation

enum AppLanguage: String {
    case chinese = "zh"
    case english = "en"

    static let storageKey = "language"

    static func stored(_ raw: String?) -> AppLanguage {
        if let raw, let language = AppLanguage(rawValue: raw) {
            return language
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }

    func text(_ key: Key) -> String {
        switch key {
        case .signedOut:
            return self == .chinese ? "未登录" : "Not signed in"
        case .loading:
            return self == .chinese ? "正在读取用量" : "Loading usage"
        case .signInFirst:
            return self == .chinese ? "请先打开 Cursor 并登录" : "Open Cursor and sign in first"
        case .unavailable:
            return self == .chinese ? "用量暂时拉不下来" : "Usage is unavailable right now"
        case .refreshFailed(let time):
            return self == .chinese
                ? "\(time) 刷新失败，下面仍是上次的用量"
                : "\(time) refresh failed. Showing the last usage."
        case .modelsUnavailable:
            return self == .chinese ? "模型明细暂时不可用" : "Model details are unavailable"
        case .noUsage:
            return self == .chinese ? "这个账期没有用量" : "No usage this period"
        case .thisPeriod:
            return self == .chinese ? "本账期" : "This period"
        case .menuBarDisplay:
            return self == .chinese ? "顶部栏显示" : "Menu bar"
        case .percent:
            return self == .chinese ? "百分比" : "Percent"
        case .percentAndTokens:
            return self == .chinese ? "百分比和 token" : "Percent and tokens"
        case .tokensOnly:
            return self == .chinese ? "仅 token" : "Tokens only"
        case .refresh:
            return self == .chinese ? "刷新" : "Refresh"
        case .quit:
            return self == .chinese ? "退出" : "Quit"
        case .language:
            return self == .chinese ? "语言" : "Language"
        }
    }

    enum Key {
        case signedOut
        case loading
        case signInFirst
        case unavailable
        case refreshFailed(String)
        case modelsUnavailable
        case noUsage
        case thisPeriod
        case menuBarDisplay
        case percent
        case percentAndTokens
        case tokensOnly
        case refresh
        case quit
        case language
    }
}

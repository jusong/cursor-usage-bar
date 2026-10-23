import Foundation
import SQLite3

public enum SessionError: Error, Equatable {
    case notSignedIn
}

public enum SessionCookie {
    public static func userID(fromSub sub: String) -> String {
        sub.split(separator: "|").last.map(String.init) ?? sub
    }

    public static func userID(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sub = object["sub"] as? String
        else {
            return nil
        }
        return userID(fromSub: sub)
    }

    public static func header(userID: String, jwt: String) -> String {
        "WorkosCursorSessionToken=\(userID)%3A%3A\(jwt)"
    }

    public static func readToken(database: URL) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw SessionError.notSignedIn
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SessionError.notSignedIn
        }
        defer { sqlite3_finalize(statement) }

        let key = "cursorAuth/accessToken"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw SessionError.notSignedIn
        }
        let token = String(cString: text)
        guard !token.isEmpty else { throw SessionError.notSignedIn }
        return token
    }
}

public enum UsageAPI {
    public static func periodRequest(cookie: String) -> URLRequest {
        request(path: "/api/dashboard/get-current-period-usage", cookie: cookie, body: "{}".data(using: .utf8))
    }

    public static func eventsRequest(cookie: String, start: Date, end: Date) -> URLRequest {
        let body: [String: String] = [
            "startDate": String(milliseconds(start)),
            "endDate": String(milliseconds(end)),
        ]
        return request(
            path: "/api/dashboard/get-aggregated-usage-events",
            cookie: cookie,
            body: try? JSONSerialization.data(withJSONObject: body)
        )
    }

    private static func request(path: String, cookie: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://cursor.com\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.httpBody = body
        return request
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

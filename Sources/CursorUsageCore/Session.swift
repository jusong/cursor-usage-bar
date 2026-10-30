import CommonCrypto
import Foundation
import Security
import SQLite3

public enum SessionError: Error, Equatable {
    case notSignedIn
}

public enum SessionCookie {
    private static let encryptedPrefix = "cursor-safe-storage:v1:"

    private final class Cache: @unchecked Sendable {
        let lock = NSCondition()
        var password: String?
        var stored: String?
        var token: String?
        var passwordLoading = false

        func clear() {
            lock.lock()
            password = nil
            stored = nil
            token = nil
            passwordLoading = false
            lock.broadcast()
            lock.unlock()
        }
    }

    private static let cache = Cache()

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
        let stored = try readStoredValue(database: database)
        cache.lock.lock()
        if stored == cache.stored, let token = cache.token {
            cache.lock.unlock()
            return token
        }
        cache.lock.unlock()

        let token: String
        if stored.hasPrefix(encryptedPrefix) {
            token = try decrypt(stored)
        } else {
            guard !stored.isEmpty else { throw SessionError.notSignedIn }
            token = stored
        }
        cache.lock.lock()
        cache.stored = stored
        cache.token = token
        cache.lock.unlock()
        return token
    }

    public static func clearCache() {
        cache.clear()
    }

    private static func readStoredValue(database: URL) throws -> String {
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
        return String(cString: text)
    }

    private static func decrypt(_ stored: String) throws -> String {
        let encoded = String(stored.dropFirst(encryptedPrefix.count))
        guard let blob = Data(base64Encoded: encoded), blob.count > 3 else {
            throw SessionError.notSignedIn
        }
        let prefix = String(data: blob.prefix(3), encoding: .utf8)
        guard prefix == "v10" else { throw SessionError.notSignedIn }
        let ciphertext = blob.dropFirst(3)
        let password = try safeStoragePassword()
        let key = try deriveKey(password: password)
        let plain = try aes128CBCDecrypt(ciphertext: Data(ciphertext), key: key)
        guard let token = String(data: plain, encoding: .utf8), !token.isEmpty else {
            throw SessionError.notSignedIn
        }
        return token
    }

    private static func safeStoragePassword() throws -> String {
        cache.lock.lock()
        while cache.passwordLoading {
            cache.lock.wait()
        }
        if let password = cache.password {
            cache.lock.unlock()
            return password
        }
        cache.passwordLoading = true
        cache.lock.unlock()

        defer {
            cache.lock.lock()
            cache.passwordLoading = false
            cache.lock.broadcast()
            cache.lock.unlock()
        }

        let password = try readCursorPassword()
        cache.lock.lock()
        cache.password = password
        cache.lock.unlock()
        return password
    }

    /// Reads Cursor's Safe Storage password through Apple's `security` tool.
    /// Its code signature never changes, so a macOS keychain approval is not tied to this app's build.
    private static func readCursorPassword() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-w", "-s", "Cursor Safe Storage", "-a", "Cursor Key"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw SessionError.notSignedIn
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)
        else {
            throw SessionError.notSignedIn
        }
        let password = text.trimmingCharacters(in: .newlines)
        guard !password.isEmpty else { throw SessionError.notSignedIn }
        return password
    }

    private static func deriveKey(password: String) throws -> Data {
        var key = Data(count: Int(kCCKeySizeAES128))
        let passwordData = Data(password.utf8)
        let salt = Data("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { keyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        Int(kCCKeySizeAES128)
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw SessionError.notSignedIn }
        return key
    }

    private static func aes128CBCDecrypt(ciphertext: Data, key: Data) throws -> Data {
        let capacity = ciphertext.count + Int(kCCBlockSizeAES128)
        var output = Data(count: capacity)
        var moved = 0
        let iv = Data(repeating: 0x20, count: Int(kCCBlockSizeAES128))
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            capacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw SessionError.notSignedIn }
        return output.prefix(moved)
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

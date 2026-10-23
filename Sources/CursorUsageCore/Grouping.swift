import Foundation

public enum ModelGroups {
    public static func isCursorModel(_ name: String, bucket: Set<String>) -> Bool {
        if name == "auto" || name == "default" { return true }
        if bucket.isEmpty {
            let lower = name.lowercased()
            return lower.hasPrefix("composer") || lower.hasPrefix("cursor-grok") || lower.hasPrefix("grok")
        }
        if bucket.contains(name) { return true }
        return bucket.contains { sameFamily(name, $0) }
    }

    public static func displayName(_ name: String) -> String {
        name == "default" ? "auto" : name
    }

    static func sameFamily(_ name: String, _ bucketName: String) -> Bool {
        if name == bucketName { return true }
        let left = stem(name)
        let right = stem(bucketName)
        return !left.isEmpty && left == right
    }

    static func stem(_ name: String) -> String {
        var text = name.lowercased().replacingOccurrences(of: "-fast", with: "")
        text = replace(text, pattern: "-(?:xhigh|low|medium|high)")
        text = replace(text, pattern: "\\d+(?:\\.\\d+)*")
        text = text.replacingOccurrences(of: ".", with: "")
        text = replace(text, pattern: "-+", template: "-")
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func replace(_ text: String, pattern: String, template: String = "") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

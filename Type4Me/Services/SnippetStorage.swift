import Foundation

/// Stores trigger → replacement snippet mappings in UserDefaults.
enum SnippetStorage {

    private static let key = "tf_snippets"

    static func load() -> [(trigger: String, value: String)] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let pairs = try? JSONDecoder().decode([[String]].self, from: data)
        else { return [] }
        return pairs.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return (trigger: pair[0], value: pair[1])
        }
    }

    static func save(_ snippets: [(trigger: String, value: String)]) {
        let pairs = snippets.map { [$0.trigger, $0.value] }
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Apply all snippet replacements to text.
    /// Builds a regex per trigger that allows optional whitespace between each character cluster,
    /// so "我的Gmail邮箱" matches "我的 Gmail 邮箱", "我的Gmail 邮箱", etc.
    static func apply(to text: String) -> String {
        let snippets = load()
        guard !snippets.isEmpty else { return text }
        var result = text
        for snippet in snippets {
            let pattern = buildFlexPattern(snippet.trigger)
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: NSRegularExpression.escapedTemplate(for: snippet.value)
                )
            }
        }
        return result
    }

    /// Splits trigger into character clusters and joins with `\s*` so spaces are optional.
    private static func buildFlexPattern(_ trigger: String) -> String {
        // Split into runs of same-script characters (e.g. "我的" "Gmail" "邮箱")
        var clusters: [String] = []
        var current = ""
        var lastType: CharType?

        for ch in trigger where !ch.isWhitespace {
            let type = charType(ch)
            if let last = lastType, last != type {
                if !current.isEmpty { clusters.append(NSRegularExpression.escapedPattern(for: current)) }
                current = String(ch)
            } else {
                current.append(ch)
            }
            lastType = type
        }
        if !current.isEmpty { clusters.append(NSRegularExpression.escapedPattern(for: current)) }

        return clusters.joined(separator: "\\s*")
    }

    private enum CharType { case cjk, ascii, other }

    private static func charType(_ ch: Character) -> CharType {
        guard let scalar = ch.unicodeScalars.first else { return .other }
        let v = scalar.value
        // CJK Unified Ideographs + common CJK ranges
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) ||
           (0x3000...0x303F).contains(v) || (0xFF00...0xFFEF).contains(v) {
            return .cjk
        }
        if ch.isASCII { return .ascii }
        return .other
    }
}

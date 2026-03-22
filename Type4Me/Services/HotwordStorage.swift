import Foundation

/// Stores and loads user-defined hotwords for ASR bias.
/// One word per line in UserDefaults.
enum HotwordStorage {

    private static let key = "tf_hotwords"
    private static let seededKey = "tf_hotwords_seeded"

    /// Example hotwords seeded on first launch.
    private static let exampleHotwords = ["claude", "claude code"]

    /// Seeds example hotwords on first launch. Call once from app startup.
    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        if load().isEmpty {
            save(exampleHotwords)
        }
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    static func load() -> [String] {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        return raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func save(_ words: [String]) {
        UserDefaults.standard.set(words.joined(separator: "\n"), forKey: key)
    }

    static func loadRaw() -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    static func saveRaw(_ text: String) {
        UserDefaults.standard.set(text, forKey: key)
    }
}

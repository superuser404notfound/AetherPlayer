import Foundation
import Testing

/// Guards the string catalog against the two ways a translation silently goes missing: a locale
/// left out of a key (the UI falls back to English without a word), and a translation that lost or
/// changed a format specifier (the value then prints garbage or crashes the formatter). It also
/// pins the key order, because Xcode writes the keys sorted on every extraction and a key parked
/// anywhere else turns the next build into a whole-file diff.
struct LocalizationCatalogTests {

    static let locales: Set<String> = [
        "cs", "da", "de", "el", "es", "fi", "fr", "hr", "hu", "it", "ja", "ko", "nb", "nl",
        "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "tr", "uk", "zh-Hans", "zh-Hant",
    ]

    static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Shared/Resources/Localizable.xcstrings")

    static func strings() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: [String: Any]])
    }

    /// `%1$@` and `%@` name the same argument kind; only the kinds and their count must survive.
    static func specifiers(_ s: String) -> [String] {
        let regex = /%(?:\d+\$)?(lld|@|d|f)/
        return s.matches(of: regex).map { String($0.output.1) }.sorted()
    }

    @Test func everyKeyIsTranslatedIntoEveryLocale() throws {
        for (key, entry) in try Self.strings() where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            let missing = Self.locales.subtracting(localizations.keys)
            #expect(missing.isEmpty, "\(key): missing \(missing.sorted())")
            for (locale, unit) in localizations {
                let stringUnit = unit["stringUnit"] as? [String: String]
                #expect(stringUnit?["state"] == "translated", "\(key) [\(locale)] is not translated")
                let value = stringUnit?["value"] ?? ""
                #expect(!value.isEmpty, "\(key) [\(locale)] is empty")
                #expect(Self.specifiers(value) == Self.specifiers(key),
                        "\(key) [\(locale)] changes the format specifiers: \(value)")
            }
        }
    }

    @Test func keysAreInXcodesOrder() throws {
        let text = try String(contentsOf: Self.catalogURL, encoding: .utf8)
        let keys = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            guard line.hasPrefix("    \""), !line.hasPrefix("     "), line.hasSuffix(" : {") else { return nil }
            return String(line.dropFirst(5).dropLast(5)).replacingOccurrences(of: "\\\"", with: "\"")
        }
        #expect(keys.count == (try Self.strings()).count)
        let sorted = keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(keys == sorted, "run: swift Scripts/xcstrings-sort.swift Sources/Shared/Resources/Localizable.xcstrings")
    }
}

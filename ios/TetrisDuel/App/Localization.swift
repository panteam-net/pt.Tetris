import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        let result = Bundle.main.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
        return result
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let result = String(
            format: text(key),
            locale: Locale.current,
            arguments: arguments
        )
        return result
    }
}

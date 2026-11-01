import Foundation
import SwiftUI

enum PhilotesLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "philotes.interfaceLanguage"

    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var autonym: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        case .traditionalChinese: "繁體中文"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var responseInstruction: String {
        switch self {
        case .simplifiedChinese:
            "请使用简体中文自然回复。"
        case .english:
            "Reply naturally in English."
        case .japanese:
            "自然な日本語で返答してください。"
        case .traditionalChinese:
            "請使用繁體中文自然回覆。"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        let raw = defaults.string(forKey: storageKey) ?? ""
        return Self(rawValue: raw) ?? .simplifiedChinese
    }
}

enum L10n {
    static var language: PhilotesLanguage {
        PhilotesLanguage.stored()
    }

    static var locale: Locale {
        language.locale
    }

    static func string(_ key: String) -> String {
        let language = language
        guard language != .simplifiedChinese,
              let path = Bundle.main.path(
                forResource: language.rawValue,
                ofType: "lproj"
              ),
              let bundle = Bundle(path: path)
        else {
            return key
        }
        return bundle.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: language.locale,
            arguments: arguments
        )
    }

    static func text(_ value: String) -> Text {
        Text(string(value))
    }
}

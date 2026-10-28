import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, tr, en

    var id: Self { self }

    var label: String {
        switch self {
        case .system: L("Sistem", "System")
        case .tr: "Türkçe"
        case .en: "English"
        }
    }

    nonisolated(unsafe) static var resolved: AppLanguage = resolve(stored)

    static var stored: AppLanguage {
        UserDefaults.standard.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    static func resolve(_ choice: AppLanguage) -> AppLanguage {
        guard choice == .system else { return choice }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("tr") ? .tr : .en
    }

    static var locale: Locale {
        Locale(identifier: resolved == .tr ? "tr_TR" : "en_US")
    }
}

struct LocalizedText: Equatable {
    let tr: String
    let en: String

    var string: String { AppLanguage.resolved == .tr ? tr : en }
}

func L(_ tr: String, _ en: String) -> String {
    AppLanguage.resolved == .tr ? tr : en
}

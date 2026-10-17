import Foundation
import SwiftUI

public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case khmer = "km"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .khmer:
            return "ភាសាខ្មែរ (Khmer)"
        }
    }
}

@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    private let userDefaultsKey = "selected_app_language"
    private var bundle: Bundle = .main

    @Published public private(set) var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: userDefaultsKey)
            updateBundle()
        }
    }

    public init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.starts(with: "km") {
                self.currentLanguage = .khmer
            } else {
                self.currentLanguage = .english
            }
        }
        updateBundle()
    }

    public func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
    }

    private func updateBundle() {
        if let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            self.bundle = langBundle
        } else {
            self.bundle = .main
        }
    }

    public func localizedString(for key: String, args: [CVarArg] = []) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        if args.isEmpty {
            return format
        }
        return String(format: format, arguments: args)
    }
}

// Swift Global helper for views
@MainActor
public func L(_ key: String, _ args: CVarArg...) -> String {
    LocalizationManager.shared.localizedString(for: key, args: args)
}

import Foundation
import SwiftUI

/// 已解析的实际语言。
enum Lang {
    case zh
    case en
}

/// 用户可选语言（含「跟随系统」）。可持久化。
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    /// 选项展示名（用各自语言书写，便于识别）。
    var displayName: String {
        switch self {
        case .system: return tr("跟随系统", "System")
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }

    /// 解析为实际渲染语言。
    func resolved() -> Lang {
        switch self {
        case .chinese: return .zh
        case .english: return .en
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.lowercased().hasPrefix("zh") ? .zh : .en
        }
    }
}

/// 全局语言状态。视图通过 `@EnvironmentObject` 订阅，切换语言即时刷新。
/// 非视图代码（模型 / 服务）通过 `AppLocale.shared` 读取。
final class AppLocale: ObservableObject {
    static let shared = AppLocale()

    @Published var language: AppLanguage {
        didSet { persist() }
    }

    private let storageKey = "DriveRideAI.AppLanguage"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let value = AppLanguage(rawValue: raw) {
            self.language = value
        } else {
            self.language = .system
        }
    }

    var lang: Lang { language.resolved() }

    private func persist() {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    }
}

/// 翻译辅助：根据当前语言返回中文或英文文案。
/// 由于参数已是完整插值后的字符串，无需关心占位符顺序。
func tr(_ zh: String, _ en: String) -> String {
    AppLocale.shared.lang == .zh ? zh : en
}

/// 供 `Text` 直接使用的本地化字符串。
func trText(_ zh: String, _ en: String) -> Text {
    Text(tr(zh, en))
}

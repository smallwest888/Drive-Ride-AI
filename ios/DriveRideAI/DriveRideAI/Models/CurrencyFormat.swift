import Foundation

/// 货币格式化：根据目的地所在地区的货币显示价格。
enum CurrencyFormat {
    /// 由国家 / 地区代码（如 "US"、"CN"、"DE"）推出货币代码（如 "USD"、"CNY"、"EUR"）。
    static func currencyCode(forCountry countryCode: String?) -> String {
        if let cc = countryCode, !cc.isEmpty {
            let identifier = Locale.identifier(fromComponents: [NSLocale.Key.countryCode.rawValue: cc])
            if let code = Locale(identifier: identifier).currency?.identifier {
                return code
            }
        }
        return deviceCurrencyCode
    }

    /// 本机区域货币代码（兜底）。
    static var deviceCurrencyCode: String {
        Locale.current.currency?.identifier ?? "CNY"
    }

    /// 本机货币符号，用于设置页输入单位。
    static var deviceCurrencySymbol: String {
        Locale.current.currencySymbol ?? "¥"
    }

    /// 用给定货币代码格式化金额（取整，附带正确的货币符号与位置）。
    static func string(_ amount: Double, code: String) -> String {
        amount.rounded().formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}

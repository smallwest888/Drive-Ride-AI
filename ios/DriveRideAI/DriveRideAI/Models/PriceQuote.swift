import Foundation

/// 价格来源，用于在 UI 上标明这笔钱是怎么来的（不编造）。
enum PriceSource: Sendable {
    case remote
    case none
}

/// 一笔价格报价。amount 为 nil 表示未知（不计入总价，不编造）。
struct PriceQuote: Sendable {
    let amount: Double?
    let source: PriceSource

    var isKnown: Bool { amount != nil }
    static let unknown = PriceQuote(amount: nil, source: .none)
}

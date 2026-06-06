import Foundation
import MapKit

/// 价格来源，用于在 UI 上标明这笔钱是怎么来的（不编造）。
enum PriceSource {
    case profile   // 用户在设置里填写的真实价格
    case remote    // 联网 / 第三方 API 获取（预留）
    case none      // 未知（未填、也没联网取到）

    var label: String {
        switch self {
        case .profile: return tr("按你填写", "your setting")
        case .remote: return tr("联网获取", "fetched online")
        case .none: return tr("未填", "not set")
        }
    }
}

/// 一笔价格报价。amount 为 nil 表示未知（不计入总价，不编造）。
struct PriceQuote {
    let amount: Double?
    let source: PriceSource

    var isKnown: Bool { amount != nil }
    static let unknown = PriceQuote(amount: nil, source: .none)
}

/// 价格来源协议。
///
/// - 方案 A（默认）：`ProfilePricingProvider` 用用户填写的真实价格。
/// - 方案 B（预留）：`RemotePricingProvider` 接第三方票价 / 停车费 API，
///   或让 Agent 联网搜索；只要把它接好，`ChainedPricingProvider` 会优先用它。
protocol PricingProvider {
    /// 公交单程票价（含交通卡折扣）。
    func transitFare(distanceKm: Double, profile: UserProfile) async -> PriceQuote
    /// 自驾市区停车费。
    func cityParkingFee(near coordinate: CLLocationCoordinate2D?, profile: UserProfile) async -> PriceQuote
    /// P+R 换乘停车场停车费。
    func parkRideParkingFee(lot: MKMapItem, profile: UserProfile) async -> PriceQuote
}

/// 方案 A：使用用户在设置里填写的真实价格。
struct ProfilePricingProvider: PricingProvider {
    func transitFare(distanceKm: Double, profile: UserProfile) async -> PriceQuote {
        // 月票 / 通勤套票：公共交通段边际成本为 0（真实）。
        if profile.transitCard.coversTransitFully {
            return PriceQuote(amount: 0, source: .profile)
        }
        guard let base = profile.transitFarePerRide else { return .unknown }
        return PriceQuote(amount: base * profile.transitCard.fareMultiplier, source: .profile)
    }

    func cityParkingFee(near coordinate: CLLocationCoordinate2D?, profile: UserProfile) async -> PriceQuote {
        guard let fee = profile.cityParkingFee else { return .unknown }
        return PriceQuote(amount: fee, source: .profile)
    }

    func parkRideParkingFee(lot: MKMapItem, profile: UserProfile) async -> PriceQuote {
        guard let fee = profile.parkRideParkingFee else { return .unknown }
        return PriceQuote(amount: fee, source: .profile)
    }
}

/// 方案 B（预留）：第三方 API / 联网搜索票价与停车费。
///
/// 目前全部返回 unknown。要启用时，在这里发起网络请求（或调用后端 / Agent 的搜索接口），
/// 把拿到的真实价格用 `PriceQuote(amount:source:.remote)` 返回即可，无需改动其他代码。
struct RemotePricingProvider: PricingProvider {
    func transitFare(distanceKm: Double, profile: UserProfile) async -> PriceQuote {
        // TODO: 接入票价 API / 联网搜索（方案 B）。
        .unknown
    }

    func cityParkingFee(near coordinate: CLLocationCoordinate2D?, profile: UserProfile) async -> PriceQuote {
        // TODO: 接入停车费 API / 联网搜索（方案 B）。
        .unknown
    }

    func parkRideParkingFee(lot: MKMapItem, profile: UserProfile) async -> PriceQuote {
        // TODO: 接入停车费 API / 联网搜索（方案 B）。
        .unknown
    }
}

/// 组合：优先用 primary（如联网 / API），取不到再回落到 fallback（用户填写）。
struct ChainedPricingProvider: PricingProvider {
    let primary: PricingProvider
    let fallback: PricingProvider

    func transitFare(distanceKm: Double, profile: UserProfile) async -> PriceQuote {
        let quote = await primary.transitFare(distanceKm: distanceKm, profile: profile)
        return quote.isKnown ? quote : await fallback.transitFare(distanceKm: distanceKm, profile: profile)
    }

    func cityParkingFee(near coordinate: CLLocationCoordinate2D?, profile: UserProfile) async -> PriceQuote {
        let quote = await primary.cityParkingFee(near: coordinate, profile: profile)
        return quote.isKnown ? quote : await fallback.cityParkingFee(near: coordinate, profile: profile)
    }

    func parkRideParkingFee(lot: MKMapItem, profile: UserProfile) async -> PriceQuote {
        let quote = await primary.parkRideParkingFee(lot: lot, profile: profile)
        return quote.isKnown ? quote : await fallback.parkRideParkingFee(lot: lot, profile: profile)
    }
}

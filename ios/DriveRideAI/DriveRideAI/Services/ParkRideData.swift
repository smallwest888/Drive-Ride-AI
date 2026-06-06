import Foundation

/// P+R（Park & Ride，停车换乘）停车场数据。
enum ParkRideData {

    /// 一个换乘停车场。
    struct Lot: Identifiable {
        let id = UUID()
        let name: String
        /// 单次停车费（元），通常远低于市中心。
        let parkingFee: Double
        /// 与之衔接的公共交通线路名（仅用于展示）。
        let transitLine: String
    }

    /// 代表性的城郊 P+R 换乘点。实际产品中应由地图/POI 数据动态获取。
    static let lots: [Lot] = [
        Lot(name: "城郊地铁 P+R 停车场", parkingFee: 10, transitLine: "地铁直达市中心"),
        Lot(name: "快速公交枢纽 P+R", parkingFee: 8, transitLine: "BRT 快速公交"),
        Lot(name: "环线换乘中心 P+R", parkingFee: 12, transitLine: "地铁环线"),
        Lot(name: "市郊铁路换乘站 P+R", parkingFee: 6, transitLine: "市郊铁路")
    ]

    /// 为某段行程挑选一个换乘点（这里做确定性挑选，便于结果稳定）。
    static func selectLot(for distanceKm: Double) -> Lot {
        let index = Int(distanceKm.rounded()) % lots.count
        return lots[max(0, index)]
    }

    /// P+R 适用的最小总距离（km）。太短则没有换乘价值。
    static let minApplicableDistanceKm: Double = 8
}

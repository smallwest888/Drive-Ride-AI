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

    /// 代表性的城郊 P+R 换乘点（按当前语言生成）。实际产品中应由地图/POI 数据动态获取。
    static var lots: [Lot] {
        [
            Lot(name: tr("城郊地铁 P+R 停车场", "Suburban Metro P+R"),
                parkingFee: 10, transitLine: tr("地铁直达市中心", "Metro to downtown")),
            Lot(name: tr("快速公交枢纽 P+R", "BRT Hub P+R"),
                parkingFee: 8, transitLine: tr("BRT 快速公交", "Bus Rapid Transit")),
            Lot(name: tr("环线换乘中心 P+R", "Loop Line P+R"),
                parkingFee: 12, transitLine: tr("地铁环线", "Metro loop line")),
            Lot(name: tr("市郊铁路换乘站 P+R", "Commuter Rail P+R"),
                parkingFee: 6, transitLine: tr("市郊铁路", "Commuter rail"))
        ]
    }

    /// 为某段行程挑选一个换乘点（这里做确定性挑选，便于结果稳定）。
    static func selectLot(for distanceKm: Double) -> Lot {
        let all = lots
        let index = Int(distanceKm.rounded()) % all.count
        return all[max(0, index)]
    }

    /// P+R 适用的最小总距离（km）。太短则没有换乘价值。
    static let minApplicableDistanceKm: Double = 8
}

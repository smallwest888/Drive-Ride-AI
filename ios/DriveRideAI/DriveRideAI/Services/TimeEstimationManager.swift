import Foundation
import CoreLocation
import MapKit

/// 一个 P+R 停车场候选及其「本地快速预估」时间（不调用 API）。
struct PRCandidate {
    let lot: MKMapItem
    /// 开车到停车场预估时间（分钟）。
    let estimatedDriveMinutes: Double
    /// 停车场到目的地公交预估时间（分钟）。
    let estimatedTransitMinutes: Double

    /// 预估总时间（分钟）= 开车到停车场 + 停车场到目的地公交。
    var estimatedTotalMinutes: Double {
        estimatedDriveMinutes + estimatedTransitMinutes
    }

    /// P+R 候选排序分：更重视停车场到目的地的公共交通段短，避免选到离目的地很远的停车场。
    var parkRideScore: Double {
        estimatedTotalMinutes + estimatedTransitMinutes * 0.8
    }
}

/// P+R 时间预估管理器。
///
/// 核心算法：`P+R 总时间 = 开车到 P+R 停车场时间 + 从 P+R 停车场到目的地的公交时间`。
/// 这里只做**本地直线距离快速预估**，用于在调用 Apple Maps API 之前给所有停车场排序，
/// 避免对每个停车场都发起网络请求。
enum TimeEstimationManager {
    /// 开车段预估速度（km/h）。
    static let driveSpeedKmh = 40.0
    /// 公交段预估速度（km/h）。
    static let transitSpeedKmh = 30.0
    /// 开车段最少分钟数。
    static let minDriveMinutes = 1.0
    /// 公交段最少分钟数。
    static let minTransitMinutes = 2.0

    /// 对单个停车场做本地快速预估。
    static func estimate(origin: CLLocationCoordinate2D,
                         destination: CLLocationCoordinate2D,
                         lot: MKMapItem) -> PRCandidate {
        let lotCoord = lot.placemark.coordinate
        let driveKm = straightLineKm(origin, lotCoord)
        let transitKm = straightLineKm(lotCoord, destination)

        let driveMinutes = max(minDriveMinutes, driveKm / driveSpeedKmh * 60.0)
        let transitMinutes = max(minTransitMinutes, transitKm / transitSpeedKmh * 60.0)

        return PRCandidate(lot: lot,
                           estimatedDriveMinutes: driveMinutes,
                           estimatedTransitMinutes: transitMinutes)
    }

    /// 对一批停车场做本地预估，并按更适合 P+R 的综合分排序。
    static func rankedCandidates(origin: CLLocationCoordinate2D,
                                 destination: CLLocationCoordinate2D,
                                 lots: [MKMapItem]) -> [PRCandidate] {
        lots
            .map { estimate(origin: origin, destination: destination, lot: $0) }
            .sorted { $0.parkRideScore < $1.parkRideScore }
    }

    /// 两坐标间直线距离（km）。
    static func straightLineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000.0
    }
}

import Foundation
import MapKit

/// 一个已解析为真实坐标的地点（来自 MapKit 地址搜索或当前定位）。
struct ResolvedPlace: Identifiable, Equatable {
    let id: UUID
    /// 展示名称（地点名 / 地址）。
    let name: String
    /// 次级地址描述（如所在城市 / 街道）。
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem

    init(id: UUID = UUID(),
         name: String,
         subtitle: String = "",
         coordinate: CLLocationCoordinate2D,
         mapItem: MKMapItem) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.mapItem = mapItem
    }

    static func == (lhs: ResolvedPlace, rhs: ResolvedPlace) -> Bool {
        lhs.name == rhs.name &&
        abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 1e-6 &&
        abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 1e-6
    }
}

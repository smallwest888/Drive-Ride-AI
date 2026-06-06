import Foundation

/// 行程地点。可携带可选坐标，便于距离计算。
struct TripLocation: Equatable {
    var name: String
    var coordinate: RouteData.Coordinate?

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(name: String, coordinate: RouteData.Coordinate? = nil) {
        self.name = name
        self.coordinate = coordinate
    }

    static func == (lhs: TripLocation, rhs: TripLocation) -> Bool {
        lhs.name == rhs.name
    }
}

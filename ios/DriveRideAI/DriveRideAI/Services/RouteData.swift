import Foundation

/// 内置的城市地理数据，用于在离线情况下估算城市间距离。
enum RouteData {

    struct Coordinate {
        let latitude: Double
        let longitude: Double
    }

    /// 常见城市经纬度。键包含常见别名，便于从自然语言中匹配。
    static let cities: [String: Coordinate] = [
        "北京": .init(latitude: 39.9042, longitude: 116.4074),
        "上海": .init(latitude: 31.2304, longitude: 121.4737),
        "广州": .init(latitude: 23.1291, longitude: 113.2644),
        "深圳": .init(latitude: 22.5431, longitude: 114.0579),
        "成都": .init(latitude: 30.5728, longitude: 104.0668),
        "重庆": .init(latitude: 29.5630, longitude: 106.5516),
        "杭州": .init(latitude: 30.2741, longitude: 120.1551),
        "南京": .init(latitude: 32.0603, longitude: 118.7969),
        "武汉": .init(latitude: 30.5928, longitude: 114.3055),
        "西安": .init(latitude: 34.3416, longitude: 108.9398),
        "长沙": .init(latitude: 28.2282, longitude: 112.9388),
        "天津": .init(latitude: 39.3434, longitude: 117.3616),
        "苏州": .init(latitude: 31.2989, longitude: 120.5853),
        "郑州": .init(latitude: 34.7466, longitude: 113.6253),
        "青岛": .init(latitude: 36.0671, longitude: 120.3826),
        "厦门": .init(latitude: 24.4798, longitude: 118.0894),
        "昆明": .init(latitude: 25.0389, longitude: 102.7183),
        "贵阳": .init(latitude: 26.6470, longitude: 106.6302),
        "哈尔滨": .init(latitude: 45.8038, longitude: 126.5350),
        "沈阳": .init(latitude: 41.8057, longitude: 123.4315),
        "大连": .init(latitude: 38.9140, longitude: 121.6147),
        "济南": .init(latitude: 36.6512, longitude: 117.1201),
        "合肥": .init(latitude: 31.8206, longitude: 117.2272),
        "福州": .init(latitude: 26.0745, longitude: 119.2965),
        "南昌": .init(latitude: 28.6820, longitude: 115.8579),
        "三亚": .init(latitude: 18.2528, longitude: 109.5119),
        "海口": .init(latitude: 20.0440, longitude: 110.1989),
        "兰州": .init(latitude: 36.0611, longitude: 103.8343),
        "乌鲁木齐": .init(latitude: 43.8256, longitude: 87.6168),
        "拉萨": .init(latitude: 29.6520, longitude: 91.1721),
        "香港": .init(latitude: 22.3193, longitude: 114.1694),
        "澳门": .init(latitude: 22.1987, longitude: 113.5439),
        "桂林": .init(latitude: 25.2736, longitude: 110.2900),
        "丽江": .init(latitude: 26.8721, longitude: 100.2299)
    ]

    /// 两点间大圆距离（km）。
    static func haversineDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// 估算城市间路网距离（km）。在直线距离基础上乘以 1.25 的绕路系数。
    static func estimatedDistance(from origin: String, to destination: String) -> Double? {
        guard let a = matchCity(origin), let b = matchCity(destination) else { return nil }
        return haversineDistance(a, b) * 1.25
    }

    /// 在城市表中模糊匹配（包含关系）。
    static func matchCity(_ name: String) -> Coordinate? {
        let cleaned = name.replacingOccurrences(of: "市", with: "")
        if let exact = cities[cleaned] { return exact }
        for (key, coord) in cities where cleaned.contains(key) {
            return coord
        }
        return nil
    }

    /// 在文本中查找出现的已知城市名（按出现顺序去重）。
    static func detectCities(in text: String) -> [String] {
        var found: [(name: String, range: Range<String.Index>)] = []
        for key in cities.keys {
            if let range = text.range(of: key) {
                found.append((key, range))
            }
        }
        return found
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map { $0.name }
    }
}

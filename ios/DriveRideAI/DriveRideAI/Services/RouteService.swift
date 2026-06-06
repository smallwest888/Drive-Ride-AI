import Foundation
import MapKit

/// 一段真实路线的结果。
struct RouteLeg {
    let distanceKm: Double
    let travelTime: TimeInterval   // 秒
    let polyline: MKPolyline?
    let usesDetailedRoute: Bool
    let stepCount: Int
    let expectedDepartureDate: Date?

    var travelHours: Double { travelTime / 3600.0 }
}

/// 基于 MapKit 的真实路线 / 地点搜索服务。
struct RouteService {

    /// 计算两点间真实路线（驾车 / 步行）。返回距离、时长与路线几何。
    func route(from source: CLLocationCoordinate2D,
               to destination: CLLocationCoordinate2D,
               transport: MKDirectionsTransportType) async -> RouteLeg? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = transport

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return nil }
            return RouteLeg(distanceKm: route.distance / 1000.0,
                            travelTime: route.expectedTravelTime,
                            polyline: route.polyline,
                            usesDetailedRoute: true,
                            stepCount: route.steps.count,
                            expectedDepartureDate: nil)
        } catch {
            return nil
        }
    }

    /// 公共交通路线。优先取完整 MKRoute；部分地区 MapKit 不返回公交路线时，回退到 ETA。
    func transitETA(from source: CLLocationCoordinate2D,
                    to destination: CLLocationCoordinate2D) async -> RouteLeg? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .transit

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return nil }
            return RouteLeg(distanceKm: route.distance / 1000.0,
                            travelTime: route.expectedTravelTime,
                            polyline: route.polyline,
                            usesDetailedRoute: true,
                            stepCount: route.steps.count,
                            expectedDepartureDate: nil)
        } catch {
            return await transitETAOnly(from: source, to: destination)
        }
    }

    private func transitETAOnly(from source: CLLocationCoordinate2D,
                                to destination: CLLocationCoordinate2D) async -> RouteLeg? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .transit

        let directions = MKDirections(request: request)
        do {
            let eta = try await directions.calculateETA()
            return RouteLeg(distanceKm: eta.distance / 1000.0,
                            travelTime: eta.expectedTravelTime,
                            polyline: nil,
                            usesDetailedRoute: false,
                            stepCount: 0,
                            expectedDepartureDate: eta.expectedDepartureDate)
        } catch {
            return nil
        }
    }

    /// 在某点附近搜索停车换乘点（P+R / 停车场），返回去重后的候选列表。
    func searchParkAndRideLots(near coordinate: CLLocationCoordinate2D,
                               radiusMeters: Double = 8000,
                               maxResults: Int = 12) async -> [MKMapItem] {
        // 依次尝试多组关键词，提升命中率（中英文 + POI 分类）。
        let queries = ["Park and Ride", "P+R 停车场", "停车换乘", "停车场", "Parking"]
        var collected: [MKMapItem] = []
        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: coordinate,
                                                latitudinalMeters: radiusMeters,
                                                longitudinalMeters: radiusMeters)
            if #available(iOS 18.0, *) {
                request.regionPriority = .required
            }
            let search = MKLocalSearch(request: request)
            if let response = try? await search.start() {
                collected.append(contentsOf: response.mapItems)
                if collected.count >= maxResults { break }
            }
        }
        return dedup(collected, limit: maxResults)
    }

    /// 按坐标去重（精度约 50m），避免同一个停车场被多次计入。
    private func dedup(_ items: [MKMapItem], limit: Int) -> [MKMapItem] {
        var seen = Set<String>()
        var result: [MKMapItem] = []
        for item in items {
            let c = item.placemark.coordinate
            let key = String(format: "%.3f,%.3f", c.latitude, c.longitude)
            if seen.insert(key).inserted {
                result.append(item)
                if result.count >= limit { break }
            }
        }
        return result
    }

    /// 计算两坐标之间的直线距离（km），用于挑选换乘点位置。
    static func straightLineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000.0
    }

    /// 在 a→b 之间按比例取一个中间坐标（fraction: 0 在 a，1 在 b）。
    static func interpolate(_ a: CLLocationCoordinate2D,
                            _ b: CLLocationCoordinate2D,
                            fraction: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }
}

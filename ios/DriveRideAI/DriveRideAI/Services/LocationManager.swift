import Foundation
import CoreLocation
import MapKit

/// 获取当前位置并反向地理编码为可用地点。
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isResolving = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<ResolvedPlace?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 请求当前位置并解析为 ResolvedPlace。
    func requestCurrentPlace() async -> ResolvedPlace? {
        if isResolving { return nil }

        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            errorMessage = tr("定位权限未开启，请在系统设置中允许。",
                              "Location access is off — enable it in Settings.")
            return nil
        }

        isResolving = true
        errorMessage = nil

        return await withCheckedContinuation { (cont: CheckedContinuation<ResolvedPlace?, Never>) in
            self.continuation = cont
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            } else {
                // 未决定：弹出授权，等 didChangeAuthorization 回调后再取位置。
                self.manager.requestWhenInUseAuthorization()
            }
        }
    }

    private func finish(_ place: ResolvedPlace?) {
        isResolving = false
        continuation?.resume(returning: place)
        continuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor in self.finish(nil) }
            return
        }
        Task { @MainActor in await self.reverseGeocode(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = tr("无法获取当前位置。", "Couldn't get your current location.")
            self.finish(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if (status == .authorizedWhenInUse || status == .authorizedAlways), self.isResolving, self.continuation != nil {
                manager.requestLocation()
            } else if status == .denied || status == .restricted, self.isResolving {
                self.errorMessage = tr("定位权限未开启，请在系统设置中允许。",
                                       "Location access is off — enable it in Settings.")
                self.finish(nil)
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        let coordinate = location.coordinate
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        let placemark = placemarks?.first

        let name: String = {
            if let pm = placemark {
                let parts = [pm.name, pm.thoroughfare, pm.locality].compactMap { $0 }
                if let first = parts.first { return first }
            }
            return tr("当前位置", "Current location")
        }()

        let mkPlacemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: mkPlacemark)
        item.name = name

        let subtitle = LocationSearchService.subtitle(for: item)
            ?? tr("我的位置", "My location")

        finish(ResolvedPlace(name: name, subtitle: subtitle, coordinate: coordinate, mapItem: item))
    }
}

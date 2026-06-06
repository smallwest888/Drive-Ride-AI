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
    private var timeoutTask: Task<Void, Never>?

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
            errorMessage = tr("定位权限未开启，请在系统设置 → 隐私 → 定位服务中允许本 App。",
                              "Location access is off — enable it in Settings › Privacy › Location.")
            return nil
        }

        isResolving = true
        errorMessage = nil

        return await withCheckedContinuation { (cont: CheckedContinuation<ResolvedPlace?, Never>) in
            self.continuation = cont
            self.startTimeout()
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.beginUpdating()
            } else {
                // 未决定：弹出授权，等 didChangeAuthorization 回调后再取位置。
                self.manager.requestWhenInUseAuthorization()
            }
        }
    }

    private func beginUpdating() {
        // startUpdatingLocation 比 requestLocation 在刚授权时更稳定，取到第一个点后即停止。
        manager.startUpdatingLocation()
    }

    /// 超时保护：避免迟迟取不到点时一直转圈。
    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.continuation != nil {
                self.errorMessage = tr("定位超时，请到空旷处或检查定位服务后重试。",
                                       "Locating timed out — try again with a clearer sky view or check Location Services.")
                self.finish(nil)
            }
        }
    }

    private func finish(_ place: ResolvedPlace?) {
        manager.stopUpdatingLocation()
        timeoutTask?.cancel()
        timeoutTask = nil
        isResolving = false
        continuation?.resume(returning: place)
        continuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            // 已经结束（超时/已取到）则忽略后续更新。
            guard self.continuation != nil else { return }
            await self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            self.errorMessage = tr("无法获取当前位置，请确认定位服务已开启后重试。",
                                   "Couldn't get your current location — make sure Location Services are on, then retry.")
            self.finish(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if (status == .authorizedWhenInUse || status == .authorizedAlways), self.isResolving, self.continuation != nil {
                self.beginUpdating()
            } else if status == .denied || status == .restricted, self.isResolving {
                self.errorMessage = tr("定位权限未开启，请在系统设置 → 隐私 → 定位服务中允许本 App。",
                                       "Location access is off — enable it in Settings › Privacy › Location.")
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

        // 用反查到的真实地标构造 MKPlacemark，保留国家/地址信息（用于货币、导航）。
        let mkPlacemark: MKPlacemark
        if let pm = placemark {
            mkPlacemark = MKPlacemark(placemark: pm)
        } else {
            mkPlacemark = MKPlacemark(coordinate: coordinate)
        }
        let item = MKMapItem(placemark: mkPlacemark)
        item.name = name

        let subtitle = placemark.map { LocationSearchService.subtitle(for: MKMapItem(placemark: MKPlacemark(placemark: $0))) ?? "" }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? tr("我的位置", "My location")

        finish(ResolvedPlace(name: name, subtitle: subtitle, coordinate: coordinate, mapItem: item))
    }
}

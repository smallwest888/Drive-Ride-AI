import Foundation
import MapKit
import Combine

/// 地址自动补全与解析服务（基于 MapKit）。
/// 每个输入框使用一个独立实例。
@MainActor
final class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []

    private var completer: MKLocalSearchCompleter?
    private var debounceTask: Task<Void, Never>?
    /// 选中某条建议后，短暂忽略下一次输入回调，避免再次弹出列表。
    private var suppressNextUpdate = false

    private func lazyCompleter() -> MKLocalSearchCompleter {
        if let completer { return completer }
        let c = MKLocalSearchCompleter()
        c.delegate = self
        c.resultTypes = [.address, .pointOfInterest]
        completer = c
        return c
    }

    /// 随用户输入更新查询。
    func update(query: String) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            completer?.queryFragment = ""
            return
        }
        if suppressNextUpdate {
            suppressNextUpdate = false
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            lazyCompleter().queryFragment = trimmed
        }
    }

    func clear() {
        debounceTask?.cancel()
        suggestions = []
        suppressNextUpdate = true
    }

    // MARK: - 将一条补全建议解析为真实坐标

    func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedPlace? {
        let request = MKLocalSearch.Request(completion: completion)
        return await search(request: request, fallbackName: completion.title,
                            fallbackSubtitle: completion.subtitle)
    }

    /// 直接用一段自由文本解析（用于聊天里出现的地名）。
    func resolve(query: String, near coordinate: CLLocationCoordinate2D? = nil) async -> ResolvedPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let coordinate {
            request.region = MKCoordinateRegion(center: coordinate,
                                                latitudinalMeters: 50_000,
                                                longitudinalMeters: 50_000)
        }
        return await search(request: request, fallbackName: query, fallbackSubtitle: "")
    }

    private func search(request: MKLocalSearch.Request,
                        fallbackName: String,
                        fallbackSubtitle: String) async -> ResolvedPlace? {
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            let name = item.name ?? fallbackName
            let subtitle = Self.subtitle(for: item) ?? fallbackSubtitle
            return ResolvedPlace(name: name,
                                 subtitle: subtitle,
                                 coordinate: item.placemark.coordinate,
                                 mapItem: item)
        } catch {
            return nil
        }
    }

    static func subtitle(for item: MKMapItem) -> String? {
        let p = item.placemark
        let parts = [p.thoroughfare, p.locality, p.administrativeArea].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}

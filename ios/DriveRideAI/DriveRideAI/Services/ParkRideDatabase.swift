import Foundation
import SwiftData
import CoreLocation

/// P+R 停车场本地数据库（SwiftData / SQLite）。首次启动写入种子数据。
@MainActor
final class ParkRideDatabase {
    static let shared = ParkRideDatabase()

    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: ParkRideLot.self)
        } catch {
            // 退回到内存存储，保证不崩溃。
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: ParkRideLot.self, configurations: config)
        }
        seedIfNeeded()
    }

    /// 数据库为空时写入种子数据。
    func seedIfNeeded() {
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<ParkRideLot>())) ?? 0
        guard count == 0 else { return }

        let lots = ParkRideCSVParser.parse(ParkRideSeedData.csv)
        for lot in lots { context.insert(lot) }
        try? context.save()
    }

    /// 所有启用且坐标有效的停车场（值快照）。
    func activeLots() -> [ParkRideLotInfo] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ParkRideLot>(
            predicate: #Predicate { $0.isActive }
        )
        let lots = (try? context.fetch(descriptor)) ?? []
        return lots
            .filter { $0.latitude != 0 || $0.longitude != 0 }
            .map(\.info)
    }

    /// 目的地附近的停车场，按直线距离升序。
    func lots(near coordinate: CLLocationCoordinate2D, maxDistanceKm: Double = 30) -> [ParkRideLotInfo] {
        activeLots()
            .map { ($0, RouteService.straightLineKm($0.coordinate, coordinate)) }
            .filter { $0.1 <= maxDistanceKm }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }
}

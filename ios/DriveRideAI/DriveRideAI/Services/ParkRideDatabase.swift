import Foundation
import CoreLocation

/// P+R 停车场本地缓存。
/// 启动时不做任何 I/O；需要时只在后台解析内置 CSV，避免 SwiftData 初始化 / 写库卡住主线程。
@MainActor
final class ParkRideDatabase {
    static let shared = ParkRideDatabase()

    private var cachedLots: [ParkRideLotInfo] = []
    private var prepareTask: Task<Void, Never>?

    private init() {}

    /// 后台预热内置 P+R 数据；重复调用安全。
    func prepareIfNeeded() {
        guard prepareTask == nil else { return }
        prepareTask = Task(priority: .utility) {
            let lots = await Task.detached(priority: .utility) {
                ParkRideCSVParser.parseInfo(ParkRideSeedData.csv)
                    .filter { $0.latitude != 0 || $0.longitude != 0 }
            }.value
            await MainActor.run {
                self.cachedLots = lots
            }
        }
    }

    /// 规划前调用：若尚未就绪则等待后台解析完成（已就绪则立即返回）。
    func activeLots() async -> [ParkRideLotInfo] {
        prepareIfNeeded()
        await prepareTask?.value
        return cachedLots
    }

    /// 同步读取缓存（仅当已预热过才有数据；否则返回空，由 MapKit 回落）。
    func cachedActiveLots() -> [ParkRideLotInfo] {
        cachedLots
    }

    func lots(near coordinate: CLLocationCoordinate2D, maxDistanceKm: Double = 30) async -> [ParkRideLotInfo] {
        await activeLots()
            .map { ($0, RouteService.straightLineKm($0.coordinate, coordinate)) }
            .filter { $0.1 <= maxDistanceKm }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }
}

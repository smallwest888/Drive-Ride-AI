import Foundation
import SwiftData
import CoreLocation

/// P+R 停车场（本地数据库实体，SwiftData / SQLite）。
@Model
final class ParkRideLot {
    /// 数据源中的原始 id（唯一，避免重复写入）。
    @Attribute(.unique) var remoteID: Int
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var totalSpaces: Int
    /// 每小时停车价（数据源货币），nil = 未提供。
    var pricePerHour: Double?
    var city: String
    var facilities: String
    /// 可换乘的公共交通线路，如 "S41, S42, U6"。
    var publicTransport: String
    var operatingHours: String
    var contactPhone: String
    var notes: String
    var isActive: Bool
    var createdAt: String
    var updatedAt: String

    init(remoteID: Int, name: String, address: String,
         latitude: Double, longitude: Double, totalSpaces: Int,
         pricePerHour: Double?, city: String, facilities: String,
         publicTransport: String, operatingHours: String, contactPhone: String,
         notes: String, isActive: Bool, createdAt: String, updatedAt: String) {
        self.remoteID = remoteID
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.totalSpaces = totalSpaces
        self.pricePerHour = pricePerHour
        self.city = city
        self.facilities = facilities
        self.publicTransport = publicTransport
        self.operatingHours = operatingHours
        self.contactPhone = contactPhone
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// P+R 停车场的值快照（Sendable），供规划器跨并发使用。
struct ParkRideLotInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let totalSpaces: Int
    let pricePerHour: Double?
    let publicTransport: String
    let notes: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension ParkRideLot {
    var info: ParkRideLotInfo {
        ParkRideLotInfo(id: remoteID, name: name, address: address,
                        latitude: latitude, longitude: longitude,
                        totalSpaces: totalSpaces, pricePerHour: pricePerHour,
                        publicTransport: publicTransport, notes: notes)
    }
}

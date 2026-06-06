import Foundation

/// 燃料类型，决定能耗单位与默认单价。
enum FuelType: String, Codable, CaseIterable, Identifiable {
    case gasoline   // 汽油
    case diesel     // 柴油
    case electric   // 纯电
    case hybrid     // 插电混动（按汽油等效计）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gasoline: return "汽油"
        case .diesel: return "柴油"
        case .electric: return "纯电"
        case .hybrid: return "插混"
        }
    }

    /// 能耗单位文案。
    var consumptionUnit: String {
        switch self {
        case .electric: return "kWh/100km"
        default: return "L/100km"
        }
    }

    /// 默认能源单价（元 / L 或 元 / kWh）。
    var defaultUnitPrice: Double {
        switch self {
        case .gasoline: return 7.8
        case .diesel: return 7.4
        case .electric: return 1.2
        case .hybrid: return 7.8
        }
    }
}

/// 用户车辆信息，用于自驾 / P+R 的油电成本计算。
struct CarProfile: Codable, Equatable, Identifiable {
    var id: UUID
    /// 车型名称，如「Toyota Corolla」。
    var name: String
    var fuelType: FuelType
    /// 百公里能耗（L 或 kWh）。
    var consumptionPer100km: Double
    /// 能源单价（元 / L 或 元 / kWh）。若为 nil 则取燃料默认值。
    var unitPrice: Double?

    init(id: UUID = UUID(),
         name: String,
         fuelType: FuelType,
         consumptionPer100km: Double,
         unitPrice: Double? = nil) {
        self.id = id
        self.name = name
        self.fuelType = fuelType
        self.consumptionPer100km = consumptionPer100km
        self.unitPrice = unitPrice
    }

    var effectiveUnitPrice: Double {
        unitPrice ?? fuelType.defaultUnitPrice
    }

    /// 每公里能源成本（元 / km）。
    var energyCostPerKm: Double {
        consumptionPer100km / 100.0 * effectiveUnitPrice
    }

    var consumptionText: String {
        let value = consumptionPer100km
        let formatted = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(formatted) \(fuelType.consumptionUnit)"
    }

    /// 常见车型预设，供用户在设置页快速选择。
    static let presets: [CarProfile] = [
        CarProfile(name: "Toyota Corolla 卡罗拉", fuelType: .gasoline, consumptionPer100km: 6.0),
        CarProfile(name: "Volkswagen Passat 帕萨特", fuelType: .gasoline, consumptionPer100km: 7.5),
        CarProfile(name: "Honda CR-V", fuelType: .gasoline, consumptionPer100km: 8.5),
        CarProfile(name: "BYD 秦 PLUS DM-i", fuelType: .hybrid, consumptionPer100km: 4.0),
        CarProfile(name: "Tesla Model 3", fuelType: .electric, consumptionPer100km: 14.0),
        CarProfile(name: "BYD 海豚（纯电）", fuelType: .electric, consumptionPer100km: 12.0)
    ]

    static let `default` = presets[0]
}

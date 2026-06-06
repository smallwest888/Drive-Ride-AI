import Foundation

/// 用户持有的公共交通卡 / 票务，影响公交、地铁与 P+R 换乘段的票价。
enum TransitCard: String, Codable, CaseIterable, Identifiable {
    case none          // 无（按全价）
    case storedValue   // 储值/交通联合卡（小幅折扣）
    case discountCard  // 折扣卡（如老年/学生，半价）
    case monthlyPass   // 月票/通勤套票（公共交通段视为已覆盖，边际成本 0）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无交通卡"
        case .storedValue: return "储值卡 / 交通联合卡"
        case .discountCard: return "折扣卡（学生 / 老年）"
        case .monthlyPass: return "月票 / 通勤套票"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "按全价计算公共交通票价"
        case .storedValue: return "公共交通约 9 折"
        case .discountCard: return "公共交通约 5 折"
        case .monthlyPass: return "公共交通段边际成本视为 0"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "creditcard"
        case .storedValue: return "creditcard.fill"
        case .discountCard: return "person.text.rectangle.fill"
        case .monthlyPass: return "ticket.fill"
        }
    }

    /// 月票时公共交通段边际成本为 0。
    var coversTransitFully: Bool { self == .monthlyPass }

    /// 票价折扣系数（非月票时生效）。
    var fareMultiplier: Double {
        switch self {
        case .none: return 1.0
        case .storedValue: return 0.9
        case .discountCard: return 0.5
        case .monthlyPass: return 0.0
        }
    }
}

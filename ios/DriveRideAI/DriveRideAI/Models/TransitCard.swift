import Foundation

/// 用户持有的德国常见公共交通票务，影响公交、地铁与 P+R 换乘段的边际成本判断。
enum TransitCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case none          // 无通票
    case storedValue   // 兼容旧存档：现在表示 Deutschlandticket
    case discountCard  // 兼容旧存档：现在表示本地优惠票/学生票/Jobticket
    case monthlyPass   // 本地/区域月票

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return tr("无德国公交通票", "No German transit pass")
        case .storedValue: return tr("德国票 Deutschlandticket", "Deutschlandticket")
        case .discountCard: return tr("本地优惠票 / Jobticket / 学生票", "Local discount / Jobticket / student pass")
        case .monthlyPass: return tr("本地 / 区域月票", "Local / regional monthly pass")
        }
    }

    var subtitle: String {
        switch self {
        case .none: return tr("未设置德国通票", "No German transit pass set")
        case .storedValue: return tr("通常覆盖德国本地/区域公共交通，不含 ICE/IC/EC 等长途列车；每次规划前联网确认适用范围", "Usually covers German local/regional transit, not ICE/IC/EC; checked online for each plan")
        case .discountCard: return tr("适用范围因城市、雇主、学校或票种而异；每次规划前联网确认", "Coverage depends on the local authority, employer, school, or product; checked online for each plan")
        case .monthlyPass: return tr("通常只覆盖购买时选择的本地/区域票区；每次规划前联网确认", "Usually covers the selected local/regional zones only; checked online for each plan")
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "ticket"
        case .storedValue: return "globe.europe.africa.fill"
        case .discountCard: return "person.text.rectangle.fill"
        case .monthlyPass: return "ticket.fill"
        }
    }

    /// 通票类在本地先按边际成本 0 建模；最终推荐前由 Agent 联网检查本次路线是否在适用范围内。
    var coversTransitFully: Bool { self == .storedValue || self == .monthlyPass }

    /// 票价折扣系数（非通票时生效）。本地优惠票折扣不稳定，保守地不自动打折，由 Agent 联网说明。
    var fareMultiplier: Double {
        switch self {
        case .none: return 1.0
        case .storedValue: return 0.0
        case .discountCard: return 1.0
        case .monthlyPass: return 0.0
        }
    }
}

import SwiftUI

/// 单个出行方案卡片。
struct PlanCardView: View {
    let plan: TravelPlan
    let rank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            metrics
            Text(plan.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(plan.mode.tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(plan.mode.tint.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: plan.mode.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(plan.mode.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.mode.displayName)
                    .font(.headline)
                if rank == 1 {
                    Text("推荐")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(plan.mode.tint))
                }
            }
            Spacer()
            if let highlight = plan.highlight {
                Text(highlight)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(plan.mode.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(plan.mode.tint.opacity(0.12)))
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric(title: "费用", value: plan.costText, icon: "yensign.circle.fill", color: .green)
            divider
            metric(title: "耗时", value: plan.durationText, icon: "clock.fill", color: .blue)
            divider
            metric(title: "舒适", value: String(format: "%.1f", plan.comfortScore), icon: "star.fill", color: .orange)
        }
    }

    private func metric(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Label {
                Text(title).font(.caption2)
            } icon: {
                Image(systemName: icon).font(.caption2)
            }
            .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 1, height: 28)
    }
}

#Preview {
    PlanCardView(
        plan: TravelPlan(
            mode: .highSpeedRail,
            cost: 553,
            durationHours: 5.3,
            comfortScore: 4.5,
            carbonKg: 46.2,
            highlight: "最快",
            summary: "市中心直达、准点率高，中长途性价比之选。"
        ),
        rank: 1
    )
    .padding()
}

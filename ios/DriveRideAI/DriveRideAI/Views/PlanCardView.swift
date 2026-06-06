import SwiftUI

/// 单套出行方案卡片：总览指标 + 分段明细 + 点评 + 真实导航。
struct PlanCardView: View {
    let plan: CommutePlan
    let rank: Int

    @State private var showRoute = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            metrics
            segmentBreakdown
            Text(plan.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !plan.navLegs.isEmpty { actionButtons }
        }
        .sheet(isPresented: $showRoute) {
            RoutePreviewView(plan: plan)
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
                Circle().fill(plan.mode.tint.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: plan.mode.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(plan.mode.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.mode.displayName).font(.headline)
                if rank == 1 {
                    Text(tr("推荐", "Recommended"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(plan.mode.tint))
                }
            }
            Spacer()
            if let highlight = plan.highlight {
                Text(highlight)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(plan.mode.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(plan.mode.tint.opacity(0.12)))
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric(title: tr("总费用", "Cost"), value: plan.costText, icon: "yensign.circle.fill", color: .green)
            divider
            metric(title: tr("总耗时", "Time"), value: plan.durationText, icon: "clock.fill", color: .blue)
            divider
            metric(title: tr("碳排放", "CO₂"), value: plan.carbonText, icon: "leaf.fill", color: .mint)
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
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 1, height: 28)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                showRoute = true
            } label: {
                Label(tr("路线", "Route"), systemImage: "map.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(plan.mode.tint.opacity(0.12)))
                    .foregroundStyle(plan.mode.tint)
            }
            .buttonStyle(.plain)

            Button {
                plan.navLegs.first?.openInAppleMaps()
            } label: {
                Label(tr("导航", "Navigate"), systemImage: "location.north.line.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(plan.mode.tint))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var segmentBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(plan.segments) { segment in
                HStack(spacing: 10) {
                    Image(systemName: segment.mode.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(plan.mode.tint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(segment.detail)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                        if segment.distanceKm > 0 {
                            Text(String(format: "%.1f km · %@", segment.distanceKm, segment.durationText))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(segment.durationText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(segment.costText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(segment.cost <= 0.01 ? .secondary : .primary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

#Preview {
    PlanCardView(
        plan: CommutePlan(
            mode: .parkAndRide,
            segments: [
                PlanSegment(mode: .drive, detail: "驾车至「城郊地铁 P+R 停车场」", distanceKm: 12, durationHours: 0.25, cost: 7),
                PlanSegment(mode: .park, detail: "停车换乘（地铁直达市中心）", distanceKm: 0, durationHours: 0.07, cost: 10),
                PlanSegment(mode: .subway, detail: "公共交通进城", distanceKm: 8, durationHours: 0.56, cost: 4)
            ],
            cost: 21,
            durationHours: 0.88,
            carbonKg: 2.3,
            highlight: "最省钱",
            summary: "避开市区拥堵与高价停车，通勤推荐。"
        ),
        rank: 1
    )
    .padding()
}

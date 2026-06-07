import SwiftUI

/// 单套出行方案卡片：总览指标 + 分段明细 + 点评 + 真实导航。
struct PlanCardView: View {
    let plan: CommutePlan
    let rank: Int

    @Environment(\.openURL) private var openURL
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
            if !plan.navLegs.isEmpty || plan.rideshareURL != nil || plan.electroverseURL != nil { actionButtons }
        }
        .sheet(isPresented: $showRoute) {
            RoutePreviewView(plan: plan)
        }
        .padding(14)
        .glassPanel(cornerRadius: 24, tint: plan.mode.tint, material: .ultraThinMaterial)
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
                        .glassCapsule(tint: plan.mode.tint, filled: true)
                }
            }
            Spacer()
            if let highlight = plan.highlight {
                Text(highlight)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(plan.mode.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassCapsule(tint: plan.mode.tint)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            if plan.mode != .transit {
                metric(title: tr("汽车/停车", "Drive/Park"), value: plan.costText, icon: "yensign.circle.fill", color: .green)
                divider
            }
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if !plan.navLegs.isEmpty {
                    Button {
                        showRoute = true
                    } label: {
                        Label(tr("路线", "Route"), systemImage: "map.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(plan.mode.tint)
                            .glassCapsule(tint: plan.mode.tint)
                    }
                    .buttonStyle(.plain)

                    Button {
                        plan.navLegs.first?.openInAppleMaps()
                    } label: {
                        Label(tr("导航", "Navigate"), systemImage: "location.north.line.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white)
                            .glassCapsule(tint: plan.mode.tint, filled: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let url = plan.rideshareURL {
                Button {
                    openURL(url)
                } label: {
                    Label("BlaBlaCar Pooling", systemImage: "person.2.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.teal)
                        .glassCapsule(tint: .teal)
                }
                .buttonStyle(.plain)
            }

            if let url = plan.electroverseURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Electroverse", systemImage: "bolt.car.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.indigo)
                        .glassCapsule(tint: .indigo)
                }
                .buttonStyle(.plain)
            }
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
                        Text(segment.displayDetail)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                        if plan.mode == .transit || segment.mode == .bus || segment.mode == .subway {
                            Text(segment.transitTimeText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if segment.distanceKm > 0 {
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
                    if segment.showsCost {
                        Text(segment.costText)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(segment.cost <= 0.01 ? .secondary : .primary)
                    }
                }
            }
        }
        .padding(10)
        .glassPanel(cornerRadius: 16, tint: plan.mode.tint, material: .thinMaterial)
    }
}

#Preview {
    PlanCardView(
        plan: CommutePlan(
            mode: .parkAndRide,
            segments: [
                PlanSegment(mode: .drive, detail: "驾车至「城郊地铁 P+R 停车场」", distanceKm: 12, durationHours: 0.25, cost: 7),
                PlanSegment(mode: .park, detail: "停车换乘", distanceKm: 0, durationHours: 0.07, cost: 10),
                PlanSegment(mode: .subway, detail: "公共交通", distanceKm: 8, durationHours: 0.56, cost: 4, departureDate: Date())
            ],
            cost: 21,
            durationHours: 0.88,
            carbonKg: 2.3,
            highlight: "最省钱",
            summary: "避开市区拥堵与高价停车，通勤推荐。",
            rideshareURL: URL(string: "https://www.blablacar.de/search-car-sharing"),
            electroverseURL: URL(string: "https://electroverse.com/home")
        ),
        rank: 1
    )
    .padding()
}

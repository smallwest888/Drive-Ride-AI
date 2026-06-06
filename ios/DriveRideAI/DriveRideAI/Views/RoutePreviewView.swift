import SwiftUI
import MapKit

/// 真实路线地图预览：展示路线几何与各段起终点，并可一键发起导航。
struct RoutePreviewView: View {
    let plan: CommutePlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                navButtons
            }
            .navigationTitle(plan.mode.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("关闭", "Close")) { dismiss() }
                }
            }
        }
    }

    private var map: some View {
        Map {
            ForEach(plan.navLegs) { leg in
                if let polyline = leg.polyline {
                    MapPolyline(polyline)
                        .stroke(plan.mode.tint, lineWidth: 5)
                }
                Marker(leg.label, systemImage: leg.transport == .automobile ? "car.fill" : "tram.fill",
                       coordinate: leg.destination.placemark.coordinate)
                    .tint(plan.mode.tint)
            }
            if let first = plan.navLegs.first {
                Marker(tr("起点", "Start"), systemImage: "location.fill",
                       coordinate: first.source.placemark.coordinate)
                    .tint(.blue)
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private var navButtons: some View {
        VStack(spacing: 8) {
            ForEach(plan.navLegs) { leg in
                Button {
                    leg.openInAppleMaps()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text(tr("用 Apple 地图：\(leg.label)", "Apple Maps: \(leg.label)"))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .padding(16)
    }
}

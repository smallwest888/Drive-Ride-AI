import SwiftUI

struct AppRootView: View {
    @State private var showHome = false

    var body: some View {
        Group {
            if showHome {
                HomeView()
            } else {
                VStack(spacing: 10) {
                    Text("CityDrive-Ride")
                        .font(.system(size: 34, weight: .heavy))
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .task {
                    StartupProbe.mark("AppRoot placeholder appear")
                    await Task.yield()
                    showHome = true
                    StartupProbe.mark("AppRoot show HomeView")
                }
            }
        }
    }
}

import SwiftUI

@main
struct DriveRideAIApp: App {
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var appLocale = AppLocale.shared

    init() {
        StartupProbe.mark("App init")
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(profileStore)
                .environmentObject(appLocale)
        }
    }
}

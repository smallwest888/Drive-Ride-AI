import SwiftUI

@main
struct DriveRideAIApp: App {
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var appLocale = AppLocale.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(profileStore)
                .environmentObject(appLocale)
        }
    }
}

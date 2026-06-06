import SwiftUI

@main
struct DriveRideAIApp: App {
    @StateObject private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(profileStore)
        }
    }
}

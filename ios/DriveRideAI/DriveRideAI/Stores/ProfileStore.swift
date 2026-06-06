import Foundation
import SwiftUI

/// 用户出行信息的持久化存储（UserDefaults + JSON 编码）。
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: UserProfile {
        didSet { persist() }
    }

    private let storageKey = "DriveRideAI.UserProfile"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

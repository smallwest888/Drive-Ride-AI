import Foundation
import SwiftUI

/// 用户出行信息的持久化存储（UserDefaults + JSON 编码）。
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: UserProfile {
        didSet { schedulePersist() }
    }
    @Published private(set) var isLoaded = false

    private let storageKey = "DriveRideAI.UserProfile"
    private let markdownMemoryKey = "DriveRideAI.UserProfileMarkdownMemory"
    private let defaults: UserDefaults
    private var persistTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        StartupProbe.mark("ProfileStore init begin")
        self.defaults = defaults
        self.profile = .default
        StartupProbe.mark("ProfileStore init end")
        Task { [weak self] in
            await Task.yield()
            await self?.loadPersistedProfile()
        }
    }

    private func loadPersistedProfile() {
        StartupProbe.mark("ProfileStore load begin")
        if let data = defaults.data(forKey: storageKey),
           var decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            if let unitPrice = decoded.car.unitPrice, abs(unitPrice - 1.0) < 0.0001 {
                decoded.car.unitPrice = nil
            }
            decoded.cityParkingFee = nil
            decoded.parkRideParkingFee = nil
            self.profile = decoded
        }
        defaults.set(profile.markdownMemory, forKey: markdownMemoryKey)
        isLoaded = true
        StartupProbe.mark("ProfileStore load end")
    }

    private func schedulePersist() {
        persistTask?.cancel()
        let profile = profile
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.persist(profile)
        }
    }

    private func persist(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: storageKey)
            defaults.set(profile.markdownMemory, forKey: markdownMemoryKey)
        }
    }
}

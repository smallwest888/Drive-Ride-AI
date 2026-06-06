import Foundation
import SwiftUI

/// 用户出行信息的持久化存储（UserDefaults + JSON 编码）。
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: UserProfile {
        didSet { schedulePersist() }
    }

    private let storageKey = "DriveRideAI.UserProfile"
    private let defaults: UserDefaults
    private var persistTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           var decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            if let unitPrice = decoded.car.unitPrice, abs(unitPrice - 1.0) < 0.0001 {
                decoded.car.unitPrice = nil
            }
            decoded.cityParkingFee = nil
            decoded.parkRideParkingFee = nil
            self.profile = decoded
        } else {
            self.profile = .default
        }
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
        }
    }
}

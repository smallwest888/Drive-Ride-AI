import SwiftUI

/// 出行信息设置：语言、是否有车、车型/能耗、能源价、交通卡、默认偏好。
struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appLocale: AppLocale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                carSection
                if profileStore.profile.hasCar {
                    carDetailSection
                }
                transitSection
                preferenceSection
                costPreviewSection
            }
            .navigationTitle(tr("出行信息", "Travel Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("完成", "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 语言

    private var languageSection: some View {
        Section(tr("语言", "Language")) {
            Picker(tr("界面语言", "App language"), selection: $appLocale.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
        }
    }

    // MARK: - 车辆

    private var carSection: some View {
        Section {
            Toggle(tr("我有可用车辆", "I have a car"), isOn: $profileStore.profile.hasCar)
        } header: {
            Text(tr("车辆", "Vehicle"))
        } footer: {
            Text(profileStore.profile.hasCar
                 ? tr("用于计算自驾与 P+R 换乘的油 / 电成本。",
                      "Used to compute fuel/electricity cost for driving and Park & Ride.")
                 : tr("无车时只比较公共交通方案。",
                      "Without a car, only public-transit options are compared."))
        }
    }

    private var carDetailSection: some View {
        Section(tr("车型与能耗", "Car & Energy")) {
            Picker(tr("选择车型", "Choose a model"), selection: presetSelection) {
                ForEach(CarProfile.presets) { preset in
                    Text(preset.name).tag(preset.name)
                }
                Text(tr("自定义", "Custom")).tag("custom")
            }

            HStack {
                Text(tr("车型名称", "Model name"))
                Spacer()
                TextField(tr("如 我的车", "e.g. My car"), text: $profileStore.profile.car.name)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }

            Picker(tr("能源类型", "Fuel type"), selection: $profileStore.profile.car.fuelType) {
                ForEach(FuelType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }

            HStack {
                Text(tr("百公里能耗", "Consumption /100km"))
                Spacer()
                TextField(tr("能耗", "Value"), value: $profileStore.profile.car.consumptionPer100km, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(profileStore.profile.car.fuelType.consumptionUnit)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(tr("能源单价", "Unit price"))
                Spacer()
                TextField(tr("单价", "Price"), value: unitPriceBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(profileStore.profile.car.fuelType.priceUnit)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 交通卡

    private var transitSection: some View {
        Section(tr("交通卡", "Transit Card")) {
            Picker(tr("我持有的交通卡", "My transit card"), selection: $profileStore.profile.transitCard) {
                ForEach(TransitCard.allCases) { card in
                    Label(card.displayName, systemImage: card.systemImage).tag(card)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Text(profileStore.profile.transitCard.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 偏好

    private var preferenceSection: some View {
        Section {
            Picker(tr("默认偏好", "Default preference"), selection: $profileStore.profile.preference) {
                ForEach(CommutePreference.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(tr("默认偏好", "Default Preference"))
        } footer: {
            Text(tr("当某次行程没有明显紧急程度时，按此偏好排序方案。",
                    "When a trip has no clear urgency, plans are sorted by this preference."))
        }
    }

    private var costPreviewSection: some View {
        Section(tr("成本预览", "Cost Preview")) {
            if profileStore.profile.hasCar {
                LabeledContent(tr("每公里油/电成本", "Energy cost per km"),
                               value: String(format: "¥%.2f / km", profileStore.profile.car.energyCostPerKm))
            }
            LabeledContent(tr("公共交通折扣", "Transit discount"),
                           value: profileStore.profile.transitCard.coversTransitFully
                           ? tr("月票（边际 0）", "Pass (zero marginal)")
                           : tr(String(format: "%.0f 折", profileStore.profile.transitCard.fareMultiplier * 10),
                                String(format: "%.0f%% off", (1 - profileStore.profile.transitCard.fareMultiplier) * 100)))
        }
    }

    // MARK: - Bindings

    private var unitPriceBinding: Binding<Double> {
        Binding(
            get: { profileStore.profile.car.effectiveUnitPrice },
            set: { profileStore.profile.car.unitPrice = $0 }
        )
    }

    private var presetSelection: Binding<String> {
        Binding(
            get: {
                CarProfile.presets.first { $0.name == profileStore.profile.car.name }?.name ?? "custom"
            },
            set: { newName in
                if let preset = CarProfile.presets.first(where: { $0.name == newName }) {
                    var car = preset
                    car.id = profileStore.profile.car.id
                    profileStore.profile.car = car
                }
            }
        )
    }
}

#Preview {
    ProfileView()
        .environmentObject(ProfileStore())
        .environmentObject(AppLocale.shared)
}

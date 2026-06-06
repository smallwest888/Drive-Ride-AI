import SwiftUI

/// 出行信息设置：是否有车、车型/能耗、能源价、交通卡、默认偏好。
struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                carSection
                if profileStore.profile.hasCar {
                    carDetailSection
                }
                transitSection
                preferenceSection
                costPreviewSection
            }
            .navigationTitle("出行信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 车辆

    private var carSection: some View {
        Section {
            Toggle("我有可用车辆", isOn: $profileStore.profile.hasCar)
        } header: {
            Text("车辆")
        } footer: {
            Text(profileStore.profile.hasCar
                 ? "用于计算自驾与 P+R 换乘的油 / 电成本。"
                 : "无车时只比较公共交通方案。")
        }
    }

    private var carDetailSection: some View {
        Section("车型与能耗") {
            Picker("选择车型", selection: presetSelection) {
                ForEach(CarProfile.presets) { preset in
                    Text(preset.name).tag(preset.name)
                }
                Text("自定义").tag("custom")
            }

            HStack {
                Text("车型名称")
                Spacer()
                TextField("如 我的车", text: $profileStore.profile.car.name)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }

            Picker("能源类型", selection: $profileStore.profile.car.fuelType) {
                ForEach(FuelType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }

            HStack {
                Text("百公里能耗")
                Spacer()
                TextField("能耗", value: $profileStore.profile.car.consumptionPer100km, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(profileStore.profile.car.fuelType.consumptionUnit)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("能源单价")
                Spacer()
                TextField("单价", value: unitPriceBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(profileStore.profile.car.fuelType == .electric ? "元/kWh" : "元/L")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 交通卡

    private var transitSection: some View {
        Section("交通卡") {
            Picker("我持有的交通卡", selection: $profileStore.profile.transitCard) {
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
            Picker("默认偏好", selection: $profileStore.profile.preference) {
                ForEach(CommutePreference.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("默认偏好")
        } footer: {
            Text("当某次行程没有明显紧急程度时，按此偏好排序方案。")
        }
    }

    private var costPreviewSection: some View {
        Section("成本预览") {
            if profileStore.profile.hasCar {
                LabeledContent("每公里油/电成本",
                               value: String(format: "¥%.2f / km", profileStore.profile.car.energyCostPerKm))
            }
            LabeledContent("公共交通折扣",
                           value: profileStore.profile.transitCard.coversTransitFully
                           ? "月票（边际 0）"
                           : String(format: "%.0f 折", profileStore.profile.transitCard.fareMultiplier * 10))
        }
    }

    // MARK: - Bindings

    /// 单价绑定：nil 时回填燃料默认值，便于编辑。
    private var unitPriceBinding: Binding<Double> {
        Binding(
            get: { profileStore.profile.car.effectiveUnitPrice },
            set: { profileStore.profile.car.unitPrice = $0 }
        )
    }

    /// 预设选择：选中预设即整体替换；选「自定义」不改动当前值。
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
}

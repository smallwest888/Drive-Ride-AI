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
                priceSection
                preferenceSection
                aiSection
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

    // MARK: - 真实价格（票价 / 停车费）

    private var priceSection: some View {
        Section {
            priceRow(title: tr("公交单程票价", "Transit fare / ride"),
                     unit: CurrencyFormat.deviceCurrencySymbol,
                     binding: $profileStore.profile.transitFarePerRide)

            if profileStore.profile.hasCar {
                priceRow(title: tr("市区停车费（一口价）", "Downtown parking (flat)"),
                         unit: CurrencyFormat.deviceCurrencySymbol,
                         binding: $profileStore.profile.cityParkingFee)

                priceRow(title: tr("P+R 换乘停车费", "P+R parking fee"),
                         unit: CurrencyFormat.deviceCurrencySymbol,
                         binding: $profileStore.profile.parkRideParkingFee)
            }
        } header: {
            Text(tr("真实价格（票价 / 停车费）", "Real Prices (Fares / Parking)"))
        } footer: {
            Text(tr("苹果 / 地图不提供票价与停车费数据，请填写你所在城市的真实价格（配合上方交通卡折扣）。未填的项不计入总价，方案会标注「未填」并以「≥」显示总价，绝不编造。",
                    "Apple/Maps don't provide fare or parking data — enter your city's real prices (the transit-card discount above still applies). Unfilled items are excluded, shown as \"≥\" and marked \"not set\" — never fabricated."))
        }
    }

    private func priceRow(title: String, unit: String, binding: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(tr("未填", "not set"), text: currencyBinding(binding))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
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

    // MARK: - 后台 AI（可选）

    private var aiBinding: Binding<AISettings> {
        Binding(
            get: { profileStore.profile.ai ?? .disabled },
            set: { profileStore.profile.ai = $0 }
        )
    }

    @ViewBuilder
    private var aiSection: some View {
        Section {
            Toggle(tr("启用 AI 文案润色", "Enable AI wording"), isOn: aiBinding.enabled)

            if aiBinding.wrappedValue.enabled {
                Picker(tr("服务商", "Provider"), selection: aiBinding.provider) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                SecureField("API Key", text: aiBinding.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Text(tr("模型", "Model"))
                    Spacer()
                    TextField(aiBinding.wrappedValue.provider.defaultModel, text: aiBinding.customModel)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text(tr("后台 AI（可选）", "Backend AI (optional)"))
        } footer: {
            Text(tr("可选接入 OpenAI 或 Qwen（通义千问），仅用于把方案文案润色得更自然——不会改动真实的距离、时间和价格。API Key 仅保存在本机，默认关闭。",
                    "Optionally connect OpenAI or Qwen — used only to polish the wording of plans; it never changes the real distance, time, or price. The API key is stored on-device only. Off by default."))
        }
    }

    private var costPreviewSection: some View {
        Section(tr("成本预览", "Cost Preview")) {
            if profileStore.profile.hasCar {
                LabeledContent(tr("每公里油/电成本", "Energy cost per km"),
                               value: String(format: "\(CurrencyFormat.deviceCurrencySymbol)%.2f / km", profileStore.profile.car.energyCostPerKm))
            }
            LabeledContent(tr("公共交通折扣", "Transit discount"),
                           value: profileStore.profile.transitCard.coversTransitFully
                           ? tr("月票（边际 0）", "Pass (zero marginal)")
                           : tr(String(format: "%.0f 折", profileStore.profile.transitCard.fareMultiplier * 10),
                                String(format: "%.0f%% off", (1 - profileStore.profile.transitCard.fareMultiplier) * 100)))

            LabeledContent(tr("公交实际单程", "Actual transit fare"),
                           value: effectiveTransitFareText)
            if profileStore.profile.hasCar {
                LabeledContent(tr("市区停车费", "Downtown parking"),
                               value: priceText(profileStore.profile.cityParkingFee))
                LabeledContent(tr("P+R 换乘停车费", "P+R parking"),
                               value: priceText(profileStore.profile.parkRideParkingFee))
            }
        }
    }

    private var effectiveTransitFareText: String {
        let symbol = CurrencyFormat.deviceCurrencySymbol
        if profileStore.profile.transitCard.coversTransitFully {
            return tr("月票覆盖（\(symbol)0）", "Pass (\(symbol)0)")
        }
        guard let base = profileStore.profile.transitFarePerRide else {
            return tr("未填", "not set")
        }
        let net = base * profileStore.profile.transitCard.fareMultiplier
        return String(format: "\(symbol)%.1f", net)
    }

    private func priceText(_ value: Double?) -> String {
        guard let value else { return tr("未填", "not set") }
        return "\(CurrencyFormat.deviceCurrencySymbol)\(String(format: "%g", value))"
    }

    // MARK: - Bindings

    private var unitPriceBinding: Binding<Double> {
        Binding(
            get: { profileStore.profile.car.effectiveUnitPrice },
            set: { profileStore.profile.car.unitPrice = $0 }
        )
    }

    /// 把可选金额（Double?）桥接成文本输入：空字符串表示未填（nil）。
    private func currencyBinding(_ source: Binding<Double?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue.map { String(format: "%g", $0) } ?? "" },
            set: { text in
                let cleaned = text.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                source.wrappedValue = cleaned.isEmpty ? nil : Double(cleaned)
            }
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

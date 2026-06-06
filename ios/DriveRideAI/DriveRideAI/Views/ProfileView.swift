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
        Section {
            Picker(tr("界面语言", "App language"), selection: $appLocale.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
        } header: {
            Text(tr("语言", "Language"))
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
        Section {
            HStack {
                Text(tr("车型名称", "Model name"))
                Spacer()
                TextField(tr("如 VW Golf 1.5 TSI 2021", "e.g. VW Golf 1.5 TSI 2021"), text: $profileStore.profile.car.name)
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
                TextField(tr("能耗", "Value"), text: consumptionTextBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(profileStore.profile.car.fuelType.consumptionUnit)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(tr("能源单价", "Unit price"))
                Spacer()
                TextField(tr("可不填", "optional"), text: unitPriceTextBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(profileStore.profile.car.fuelType.priceUnit)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("CO₂")
                Spacer()
                TextField(tr("可不填", "optional"), text: co2TextBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("g/km")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(tr("车型与能耗", "Car & Energy"))
        } footer: {
            Text(tr("CO2 填了就直接用于计算，速度最快；不填时才使用本地估算。能源单价可不填，不会再自动塞入默认值。",
                    "If CO2 is entered, it is used directly for faster planning; otherwise a local fallback is used. Unit price is optional and no longer prefilled."))
        }
    }

    // MARK: - 交通卡

    private var transitSection: some View {
        Section {
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
        } header: {
            Text(tr("交通卡", "Transit Card"))
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
            Toggle(tr("启用后台 AI", "Enable backend AI"), isOn: aiBinding.enabled)

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

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("接入地址 (baseURL)", "Endpoint (baseURL)"))
                    TextField(aiBinding.wrappedValue.provider.defaultBaseURL, text: aiBinding.customBaseURL)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                HStack {
                    Text(tr("TTS 音色", "TTS voice"))
                    Spacer()
                    TextField("Cherry", text: aiBinding.ttsVoice)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text(tr("后台 AI（可选）", "Backend AI (optional)"))
        } footer: {
            Text(tr("可选接入 OpenAI 或 Qwen（通义千问）。开启后 AI 会联网查询德国票种适用范围、DB 票价和停车费，再在已用真实地图数据算好的候选里权衡、选出最佳方案并排序；语音模式使用 Qwen3-ASR + Qwen3-TTS（海外 dashscope-intl）。AI 不会改动真实的距离和时间，查不到价格会明确标注未知。CO2 优先使用你填写的 g/km，未填写则用本地估算。海外版 Qwen 用默认的 dashscope-intl 地址；国内账号请把接入地址改成 dashscope.aliyuncs.com。API Key 仅保存在本机，默认关闭。",
                    "Optionally connect OpenAI or Qwen. When on, the AI searches German ticket coverage, DB fares, and parking fees online, then weighs real map-based candidates to pick and rank the best plan; voice mode uses Qwen3-ASR + Qwen3-TTS (international dashscope-intl). It never changes real distance or time, and marks prices unknown when not found. CO2 uses your entered g/km first, otherwise a local fallback. Overseas Qwen uses the default dashscope-intl endpoint; for China-mainland, change the endpoint to dashscope.aliyuncs.com. The API key is stored on-device only. Off by default."))
        }
    }

    private var costPreviewSection: some View {
        Section {
            if profileStore.profile.hasCar {
                LabeledContent(tr("每公里油/电成本", "Energy cost per km"),
                               value: String(format: "\(CurrencyFormat.deviceCurrencySymbol)%.2f / km", profileStore.profile.car.energyCostPerKm))
            }
            LabeledContent(tr("公共交通折扣", "Transit discount"),
                           value: profileStore.profile.transitCard.coversTransitFully
                           ? tr("通票候选（联网确认范围）", "Pass candidate (coverage checked online)")
                           : tr("无自动折扣", "No automatic discount"))
            if profileStore.profile.hasCar {
                LabeledContent(tr("停车费", "Parking fees"),
                               value: tr("规划时联网搜索", "searched during planning"))
            }
        } header: {
            Text(tr("成本预览", "Cost Preview"))
        }
    }

    // MARK: - Bindings

    private var consumptionTextBinding: Binding<String> {
        Binding(
            get: { Self.localizedNumberString(profileStore.profile.car.consumptionPer100km) },
            set: { text in
                if let value = Self.parseLocalizedDouble(text), value > 0 {
                    profileStore.profile.car.consumptionPer100km = value
                }
            }
        )
    }

    private var unitPriceTextBinding: Binding<String> {
        Binding(
            get: { profileStore.profile.car.unitPrice.map(Self.localizedNumberString) ?? "" },
            set: { text in
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                profileStore.profile.car.unitPrice = cleaned.isEmpty ? nil : Self.parseLocalizedDouble(cleaned)
            }
        )
    }

    private var co2TextBinding: Binding<String> {
        Binding(
            get: { profileStore.profile.car.co2GramsPerKm.map(Self.localizedNumberString) ?? "" },
            set: { text in
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                profileStore.profile.car.co2GramsPerKm = cleaned.isEmpty ? nil : Self.parseLocalizedDouble(cleaned)
            }
        )
    }

    private static func localizedNumberString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%g", value)
    }

    private static func parseLocalizedDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }

        let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
        let normalized: String
        if noSpaces.contains(","), noSpaces.contains("."),
           let comma = noSpaces.lastIndex(of: ","),
           let dot = noSpaces.lastIndex(of: ".") {
            if comma > dot {
                normalized = noSpaces
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            } else {
                normalized = noSpaces.replacingOccurrences(of: ",", with: "")
            }
        } else {
            normalized = noSpaces.replacingOccurrences(of: ",", with: ".")
        }
        return Double(normalized)
    }
}

#Preview {
    ProfileView()
        .environmentObject(ProfileStore())
        .environmentObject(AppLocale.shared)
}

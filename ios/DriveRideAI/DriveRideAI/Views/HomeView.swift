import SwiftUI
import MapKit

/// 主界面：品牌头部 + 真实地址搜索 + 需求聊天与方案。
struct HomeView: View {
    enum Field: Hashable { case origin, destination }

    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appLocale: AppLocale
    @StateObject private var viewModel = PlannerViewModel()
    @StateObject private var originSearch = LocationSearchService()
    @StateObject private var destinationSearch = LocationSearchService()
    @StateObject private var voice = VoiceInteractionManager()

    @FocusState private var focusedField: Field?
    @State private var showProfile = false
    @State private var showLocationError = false
    @State private var isLocating = false
    @State private var locationErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            locationFields
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(height: 0.6)
                .padding(.top, 10)
            conversation
            if showSuggestions { suggestionBar }
            InputBarView(
                text: $viewModel.inputText,
                isProcessing: viewModel.isProcessing,
                placeholder: tr("补充需求，如「有点赶」「想省钱」", "Add details, e.g. \"a bit rushed\", \"save money\""),
                sendIcon: "paperplane.fill",
                voicePhase: voice.phase,
                voiceTranscript: voice.transcript,
                voiceMeterLevel: voice.meterLevel,
                onSend: { focusedField = nil; viewModel.submit() },
                onVoiceTap: toggleVoiceInput,
                onDismissVoiceError: { voice.dismissError() }
            )
        }
        .background(
            LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground).opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear {
            StartupProbe.mark("HomeView first appear")
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .environmentObject(profileStore)
                .environmentObject(appLocale)
        }
        .alert(tr("定位失败", "Location failed"), isPresented: $showLocationError) {
            Button(tr("好", "OK"), role: .cancel) {}
        } message: {
            Text(locationErrorMessage ?? tr("无法获取当前位置。", "Couldn't get your current location."))
        }
        .task {
            StartupProbe.mark("HomeView task begin")
            await Task.yield()
            while !profileStore.isLoaded {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            await MainActor.run {
                viewModel.updateProfileProvider(
                    { [weak profileStore] in profileStore?.profile ?? .default },
                    saver: { [weak profileStore] profile in profileStore?.profile = profile }
                )
                StartupProbe.mark("HomeView task end")
            }
        }
        .onChange(of: appLocale.language) { _, _ in viewModel.refreshWelcomeIfIdle() }
        .onChange(of: viewModel.originText) { _, newValue in
            viewModel.originTextChanged()
            originSearch.update(query: newValue)
        }
        .onChange(of: viewModel.destinationText) { _, newValue in
            viewModel.destinationTextChanged()
            destinationSearch.update(query: newValue)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CityDrive-Ride")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.primary)
                Text(tr("P+R 停车场 + 公共交通", "P+R Parking + Public Transit"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showProfile = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22, tint: .accentColor, material: .ultraThinMaterial)
            }
            .accessibilityLabel(tr("出行信息设置", "Travel settings"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var locationFields: some View {
        VStack(spacing: 10) {
            LocationFieldView(
                icon: "location.fill", iconColor: .blue,
                placeholder: tr("输入出发地", "Enter origin"),
                text: $viewModel.originText,
                field: .origin, focused: $focusedField,
                showLocate: true, isLocating: isLocating,
                onLocate: locateCurrent
            )
            if viewModel.originPlace == nil, !originSearch.suggestions.isEmpty {
                suggestionList(originSearch.suggestions) { completion in
                    Task { await select(completion, from: originSearch, isOrigin: true) }
                }
            }

            LocationFieldView(
                icon: "flag.fill", iconColor: .red,
                placeholder: tr("输入目的地", "Enter destination"),
                text: $viewModel.destinationText,
                field: .destination, focused: $focusedField
            )
            if viewModel.destinationPlace == nil, !destinationSearch.suggestions.isEmpty {
                suggestionList(destinationSearch.suggestions) { completion in
                    Task { await select(completion, from: destinationSearch, isOrigin: false) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func suggestionList(_ items: [MKLocalSearchCompletion],
                                onTap: @escaping (MKLocalSearchCompletion) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, item in
                Button {
                    onTap(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline).foregroundStyle(.primary)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 40)
            }
        }
        .glassPanel(cornerRadius: 20, tint: .accentColor, material: .thinMaterial)
    }

    private func select(_ completion: MKLocalSearchCompletion,
                        from service: LocationSearchService, isOrigin: Bool) async {
        service.clear()
        guard let place = await service.resolve(completion) else { return }
        if isOrigin { viewModel.setOrigin(place) } else { viewModel.setDestination(place) }
        focusedField = nil
    }

    private func locateCurrent() {
        guard !isLocating else { return }
        isLocating = true
        locationErrorMessage = nil
        Task { @MainActor in
            let manager = LocationManager()
            if let place = await manager.requestCurrentPlace() {
                originSearch.clear()
                focusedField = nil
                viewModel.setOrigin(place)
            } else {
                locationErrorMessage = manager.errorMessage
                showLocationError = true
            }
            isLocating = false
        }
    }

    private func toggleVoiceInput() {
        focusedField = nil
        if voice.phase == .speaking {
            voice.stopSpeaking()
            return
        }

        Task {
            let settings = profileStore.profile.ai ?? .disabled
            await voice.toggleRecording(settings: settings, lang: appLocale.lang) { text in
                await viewModel.submitVoice(text)
            }
        }
    }

    // MARK: - 会话与方案

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            onQuickReply: { viewModel.sendQuickReply($0) },
                            onAction: { viewModel.handleAction($0) }
                        )
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
            .onChange(of: viewModel.messages) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private var showSuggestions: Bool {
        viewModel.messages.count <= 1 && !viewModel.isProcessing
    }

    private var suggestions: [String] {
        [
            tr("有点赶时间", "A bit rushed"),
            tr("想省钱", "Save money"),
            tr("尽量环保", "Go green"),
            tr("正常通勤", "Normal commute")
        ]
    }

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        viewModel.inputText = s
                        focusedField = nil
                        viewModel.submit()
                    } label: {
                        Text(s)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassCapsule(tint: .accentColor)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private let bottomAnchor = "bottom-anchor"
}

#Preview {
    HomeView()
        .environmentObject(ProfileStore())
        .environmentObject(AppLocale.shared)
}

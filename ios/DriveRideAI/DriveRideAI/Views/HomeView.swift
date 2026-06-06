import SwiftUI

/// 主界面：品牌头部 + 起终点输入 + 需求聊天与方案。
struct HomeView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appLocale: AppLocale
    @StateObject private var viewModel = PlannerViewModel()
    @State private var showProfile = false

    var body: some View {
        VStack(spacing: 0) {
            header
            locationFields
            Divider().padding(.top, 4)
            conversation
            if showSuggestions { suggestionBar }
            InputBarView(
                text: $viewModel.inputText,
                isProcessing: viewModel.isProcessing,
                placeholder: tr("补充需求，如「有点赶」「想省钱」", "Add details, e.g. \"a bit rushed\", \"save money\""),
                sendIcon: "paperplane.fill",
                onSend: viewModel.submit
            )
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .environmentObject(profileStore)
                .environmentObject(appLocale)
        }
        .onAppear {
            viewModel.updateProfileProvider { [weak profileStore] in
                profileStore?.profile ?? .default
            }
        }
        .onChange(of: appLocale.language) { _, _ in
            // 用户尚未开始对话时，切换语言后刷新欢迎语为新语言。
            viewModel.refreshWelcomeIfIdle()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drive&Ride")
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
            }
            .accessibilityLabel(tr("出行信息设置", "Travel settings"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var locationFields: some View {
        VStack(spacing: 10) {
            LocationFieldView(icon: "location.fill", iconColor: .blue,
                              placeholder: tr("输入出发地", "Enter origin"), text: $viewModel.originText)
            LocationFieldView(icon: "flag.fill", iconColor: .red,
                              placeholder: tr("输入目的地", "Enter destination"), text: $viewModel.destinationText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - 会话与方案

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message) { reply in
                            viewModel.sendQuickReply(reply)
                        }
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
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
            tr("大概 20 公里", "About 20 km")
        ]
    }

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        viewModel.inputText = s
                        viewModel.submit()
                    } label: {
                        Text(s)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1))
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

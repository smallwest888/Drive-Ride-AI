import SwiftUI

/// 主界面：品牌头部 + 起终点输入 + 需求聊天与方案。
struct HomeView: View {
    @EnvironmentObject private var profileStore: ProfileStore
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
                placeholder: "补充需求，如「有点赶」「想省钱」",
                sendIcon: "paperplane.fill",
                onSend: viewModel.submit
            )
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .environmentObject(profileStore)
        }
        .onAppear {
            viewModel.updateProfileProvider { [weak profileStore] in
                profileStore?.profile ?? .default
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drive&Ride")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.primary)
                Text("P+R 停车场 + 公共交通")
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
            .accessibilityLabel("出行信息设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var locationFields: some View {
        VStack(spacing: 10) {
            LocationFieldView(icon: "location.fill", iconColor: .blue,
                              placeholder: "输入出发地", text: $viewModel.originText)
            LocationFieldView(icon: "flag.fill", iconColor: .red,
                              placeholder: "输入目的地", text: $viewModel.destinationText)
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

    private let suggestions = ["有点赶时间", "想省钱", "尽量环保", "大概 20 公里"]

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
}

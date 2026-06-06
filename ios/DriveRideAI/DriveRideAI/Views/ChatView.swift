import SwiftUI

/// 主聊天界面。
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                if showSuggestions {
                    suggestionBar
                }
                InputBarView(
                    text: $viewModel.inputText,
                    isProcessing: viewModel.isProcessing,
                    onSend: viewModel.sendCurrentInput
                )
            }
            .navigationTitle("出行助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("新对话")
                }
            }
        }
    }

    private var showSuggestions: Bool {
        viewModel.messages.count <= 1 && !viewModel.isProcessing
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 14)
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

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.suggestions, id: \.self) { suggestion in
                    Button {
                        viewModel.send(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private let bottomAnchor = "bottom-anchor"
}

#Preview {
    ChatView()
}

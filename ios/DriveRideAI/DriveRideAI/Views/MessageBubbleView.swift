import SwiftUI

/// 一条聊天消息（含可能的方案卡片与快捷追问选项）。
struct MessageBubbleView: View {
    let message: ChatMessage
    var onQuickReply: (String) -> Void = { _ in }
    var onAction: (MessageAction) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassCapsule(tint: .accentColor, filled: true)
        }
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 10) {
                if message.isTyping {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TypingIndicatorView()
                } else {
                    if !message.text.isEmpty {
                        MarkdownText(message.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassPanel(cornerRadius: 20, tint: .accentColor, material: .thinMaterial)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(message.plans.enumerated()), id: \.element.id) { index, plan in
                        PlanCardView(plan: plan, rank: index + 1)
                    }
                    if !message.quickReplies.isEmpty {
                        quickReplies
                    }
                    if !message.actions.isEmpty {
                        actionButtons
                    }
                }
            }
            Spacer(minLength: 16)
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.actions) { action in
                Button {
                    onAction(action)
                } label: {
                    Text(action.title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .glassCapsule(tint: .accentColor, filled: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickReplies: some View {
        FlexibleChips(items: message.quickReplies) { reply in
            Button {
                onQuickReply(reply)
            } label: {
                Text(reply)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(Color.accentColor)
                    .glassCapsule(tint: .accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 30, height: 30)
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// 简单的自动换行标签容器。
struct FlexibleChips<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows(), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }

    /// 每行最多放 2 个，避免超宽。
    private func rows() -> [[String]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)])
        }
    }
}

/// 渲染助手回复中的 Markdown（标题、列表、加粗、链接等）。
private struct MarkdownText: View {
    private enum Block: Identifiable {
        case heading(String, Int)
        case bullet(String)
        case paragraph(String)

        var id: String {
            switch self {
            case let .heading(text, level): return "h\(level)-\(text)"
            case let .bullet(text): return "b-\(text)"
            case let .paragraph(text): return "p-\(text)"
            }
        }
    }

    private let blocks: [Block]

    init(_ text: String) {
        self.blocks = Self.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                switch block {
                case let .heading(text, level):
                    inlineMarkdown(text)
                        .font(level == 1 ? .headline : .subheadline.weight(.semibold))
                        .padding(.top, 2)
                case let .bullet(text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        inlineMarkdown(text)
                    }
                    .font(.body)
                case let .paragraph(text):
                    inlineMarkdown(text)
                        .font(.body)
                }
            }
        }
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    private static func parse(_ text: String) -> [Block] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(String(line.dropFirst(3)), 2))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(String(line.dropFirst(2)), 1))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraph.append(raw)
            }
        }
        flushParagraph()
        return blocks
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(message: ChatMessage(role: .user, text: "家 → 公司　·　有点赶"))
            MessageBubbleView(message: ChatMessage(
                role: .assistant,
                text: "我已记录行程。方便告诉我大致距离吗？",
                quickReplies: ["约 5 公里", "约 15 公里", "约 30 公里", "约 50 公里"]
            ))
            MessageBubbleView(message: ChatMessage(
                role: .assistant,
                text: """
                ## 交通卡建议
                - **Deutschlandticket**：适合本地/区域交通
                - 州票：适合偶尔跨城市出行
                """
            ))
            MessageBubbleView(message: ChatMessage(role: .assistant, text: "", isTyping: true))
        }
        .padding()
    }
}

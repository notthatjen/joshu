import SwiftUI
import JoshuKit

/// Floating chat window for one discovered session: transcript, live tail,
/// and continue-conversation (Claude; Codex is read-only in the MVP).
struct ChatWindowView: View {
    @State private var engine: ChatEngine
    @State private var draft = ""

    init(session: DiscoveredSession) {
        _engine = State(initialValue: ChatEngine(session: session, tools: sharedToolAvailability))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            transcript
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: engine.session.tool == .claude ? "sparkle" : "terminal")
                .foregroundStyle(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.session.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.9))
                if let forkedFrom = engine.forkedFromID {
                    Text("forked from \(forkedFrom.prefix(8))")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.9))
                }
            }
            Spacer()
            if engine.driftCount > 0 {
                Text("\(engine.driftCount) unrecognized")
                    .font(.caption2)
                    .foregroundStyle(.yellow.opacity(0.7))
                    .help("Transcript may be incomplete — the CLI's file format has entries this build doesn't know.")
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(engine.messages.suffix(200)) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: engine.messages.count) {
                if let last = engine.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = engine.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let statusText = engine.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.9))
            }

            if engine.session.tool == .claude {
                HStack(spacing: 8) {
                    TextField("Message Claude…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                        .disabled(engine.isSending)

                    if engine.isSending {
                        Button {
                            engine.cancelSend()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.isEmpty)
                    }
                }
            } else {
                Text("Codex sessions are read-only for now — watching live.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        engine.send(text)
    }
}

private struct MessageBubble: View {
    let message: TranscriptMessage
    @State private var showThinking = false

    var body: some View {
        switch message.role {
        case .user:
            bubble(text: message.plainText, alignment: .trailing,
                   background: Color.accentColor.opacity(0.45))
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool, .system:
            toolRow(summary: message.plainText.isEmpty ? summaryOfBlocks : message.plainText,
                    icon: "wrench.adjustable")
        }
    }

    private var summaryOfBlocks: String {
        message.blocks.compactMap { block in
            switch block {
            case .toolResult(let summary): summary
            case .text(let text): text
            default: nil
            }
        }.joined(separator: " ")
    }

    @ViewBuilder
    private func blockView(_ block: ContentBlock) -> some View {
        switch block {
        case .text(let text):
            if !text.isEmpty {
                bubble(text: text, alignment: .leading, background: .white.opacity(0.08))
            }
        case .thinking(let text):
            DisclosureGroup(isExpanded: $showThinking) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .textSelection(.enabled)
            } label: {
                Label("thinking", systemImage: "brain")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        case .toolUse(let name, let summary):
            toolRow(summary: "\(name) \(summary)", icon: "hammer")
        case .toolResult(let summary):
            toolRow(summary: summary, icon: "arrow.turn.down.right")
        case .unknown(let type):
            toolRow(summary: "unrecognized block: \(type)", icon: "questionmark.diamond")
        }
    }

    private func bubble(text: String, alignment: Alignment, background: Color) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.9))
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func toolRow(summary: String, icon: String) -> some View {
        Label(summary.isEmpty ? "…" : summary, systemImage: icon)
            .font(.caption.monospaced())
            .lineLimit(2)
            .foregroundStyle(.white.opacity(0.45))
    }
}

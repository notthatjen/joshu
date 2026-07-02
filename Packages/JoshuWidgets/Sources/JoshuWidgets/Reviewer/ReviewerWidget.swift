import SwiftUI
import JoshuKit

public struct ReviewerConfig: WidgetConfig {
    public init() {}
}

/// Paste a PR URL → AI review → history with staleness. Empty state is just
/// the input field; with entries, input + list of latest run per PR.
public enum ReviewerWidget: WidgetDescriptor {
    public static let typeID = WidgetTypeID(rawValue: "com.wren.joshu.reviewer")

    public static let metadata = WidgetMetadata(
        displayName: "Reviewer",
        systemImage: "checkmark.seal",
        summary: "AI code review for GitHub PRs, with history and staleness tracking.",
        defaultSize: CGSize(width: 360, height: 420),
        allowsMultipleInstances: false
    )

    public static func makeView(model: WidgetModel<ReviewerConfig>) -> some View {
        ReviewerView(model: model)
    }
}

@MainActor
private func makeEngine() -> ReviewerEngine {
    let store = (try? ReviewStore(path: ReviewStore.defaultPath())) ?? (try! ReviewStore())
    return ReviewerEngine(store: store)
}

private struct ReviewerView: View {
    let model: WidgetModel<ReviewerConfig>
    @State private var engine = makeEngine()
    @State private var urlDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Reviewer", systemImage: "checkmark.seal")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                if engine.runningCount > 0 {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                TextField("Paste a GitHub PR URL…", text: $urlDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(urlDraft.isEmpty)
            }

            if let errorText = engine.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            }

            if engine.runs.isEmpty {
                Spacer()
                Text("No reviews yet. Paste a PR URL to run one.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(engine.runs) { run in
                            ReviewRow(run: run, engine: engine, model: model)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func submit() {
        engine.startReview(urlText: urlDraft)
        urlDraft = ""
    }
}

private struct ReviewRow: View {
    let run: ReviewRun
    let engine: ReviewerEngine
    let model: WidgetModel<ReviewerConfig>

    var body: some View {
        Button {
            model.shell.presentAuxiliaryWindow(
                key: "review-\(run.subjectKey)",
                options: AuxiliaryWindowOptions(
                    size: CGSize(width: 440, height: 520),
                    attachment: .anchored(edge: .trailing, gap: 12))
            ) {
                ReviewDetailView(run: run)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(run.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    StatusChip(status: run.status)
                }
                HStack(spacing: 8) {
                    Text(run.subjectKey)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.45))
                    severityCounts
                    Spacer()
                    if run.status == .stale || run.status == .failed {
                        Button("Re-run") { engine.rerun(run) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var severityCounts: some View {
        let counts = Dictionary(grouping: run.findings, by: \.severity)
            .mapValues(\.count)
        return HStack(spacing: 6) {
            ForEach(FindingSeverity.allCases, id: \.self) { severity in
                if let count = counts[severity], count > 0 {
                    Text("\(count) \(severity.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(severity.color.opacity(0.9))
                }
            }
        }
    }
}

struct StatusChip: View {
    let status: ReviewStatus

    private var color: Color {
        switch status {
        case .queued: .gray
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .stale: .orange
        case .cancelled: .gray
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }
}

extension FindingSeverity {
    var color: Color {
        switch self {
        case .blocker: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .nit: .gray
        }
    }
}

private struct ReviewDetailView: View {
    let run: ReviewRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.title)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                    Text("\(run.subjectKey) · \(run.headSHA.prefix(8)) · by \(run.author)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                StatusChip(status: run.status)
            }

            if let summary = run.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = run.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            }

            Divider().overlay(.white.opacity(0.15))

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(run.findings) { finding in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(finding.severity.rawValue.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(finding.severity.color)
                                Text(finding.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            Text(finding.line.map { "\(finding.file):\($0)" } ?? finding.file)
                                .font(.caption.monospaced())
                                .foregroundStyle(.white.opacity(0.5))
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if run.findings.isEmpty, run.status == .completed {
                        Text("No findings 🎉")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(16)
    }
}

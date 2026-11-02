import SwiftUI

struct LinearCard: View {
    @ObservedObject private var store = LinearStore.shared
    let onOpenURL: (URL) -> Void

    private static let tint = Color(red: 0.37, green: 0.42, blue: 0.82)

    var body: some View {
        NotchCard(title: "Linear", systemImage: "square.stack.3d.up.fill", tint: Self.tint) {
            RefreshButton(isSpinning: store.isRefreshing) {
                Task { await store.refresh() }
            }
        } content: {
            content
        }
        // Polls only while the card is on screen; SwiftUI cancels the task on close.
        .task {
            while !Task.isCancelled {
                await store.refreshIfStale()
                try? await Task.sleep(for: .seconds(LinearStore.refreshInterval))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.status {
        case .cliMissing:
            CardPlaceholder(
                systemImage: "terminal",
                title: "Linear CLI Not Found",
                message: "Install it with Homebrew, then run `linear auth login`."
            )
        case .failed(let message) where store.issues.isEmpty:
            CardPlaceholder(systemImage: "exclamationmark.triangle", title: "Couldn't Load Issues", message: message) {
                Button("Try Again") { Task { await store.refresh() } }
                    .controlSize(.small)
            }
        case .idle:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading where store.issues.isEmpty:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if store.issues.isEmpty {
                CardPlaceholder(systemImage: "checkmark.circle", title: "Nothing Assigned", message: "No Todo, In Progress or In Review issues.")
            } else {
                issueList
            }
        }
    }

    private var issueList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(LinearGroup.allCases) { group in
                    let issues = store.issues(in: group)
                    if !issues.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(group.rawValue)
                                Text("\(issues.count)").foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 2)

                            ForEach(issues) { issue in
                                IssueRow(issue: issue) {
                                    if let url = issue.url { onOpenURL(url) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, -6)
    }
}

private struct IssueRow: View {
    let issue: LinearIssue
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LinearStateIcon(group: issue.group, color: Color(hex: issue.stateColorHex))
                    .frame(width: 12, height: 12)
                Text(issue.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(issue.id)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(issue.title)
    }
}

/// Mirrors Linear's own state glyphs: an empty ring for Todo, a half-filled ring
/// for In Progress and a mostly-filled ring for In Review.
private struct LinearStateIcon: View {
    let group: LinearGroup
    let color: Color

    private var fraction: Double {
        switch group {
        case .todo: return 0
        case .inProgress: return 0.5
        case .inReview: return 0.75
        }
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.5)
            if fraction > 0 {
                PieSlice(fraction: fraction)
                    .fill(color)
                    .padding(3)
            }
        }
    }
}

private struct PieSlice: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct RefreshButton: View {
    let isSpinning: Bool
    let action: () -> Void

    var body: some View {
        NotchIconButton(systemName: "arrow.clockwise", help: "Refresh", action: action)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(isSpinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: isSpinning)
            .disabled(isSpinning)
    }
}

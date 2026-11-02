import SwiftUI

// MARK: - Notch shape

/// The hardware notch silhouette: flat top, small concave "ears" that blend into
/// the menu bar, and rounded bottom corners. Both radii animate as it expands.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, (rect.width - top * 2) / 2, rect.height - top)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var viewModel: TelemetryViewModel
    let onToggleSettings: () -> Void
    let onOpenURL: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        let size = state.isExpanded ? state.openSize : state.closedSize
        let shape = NotchShape(
            topRadius: state.isExpanded ? NotchState.earRadius : 6,
            bottomRadius: state.isExpanded ? 30 : 10
        )

        ZStack(alignment: .top) {
            shape.fill(Color.black)

            if state.isExpanded {
                NotchContent(
                    viewModel: viewModel,
                    headerHeight: state.closedSize.height,
                    showingSettings: state.showingSettings,
                    onToggleSettings: onToggleSettings,
                    onOpenURL: onOpenURL,
                    onDismiss: onDismiss
                )
                .padding(.horizontal, NotchState.earRadius)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                            .animation(.spring(response: 0.42, dampingFraction: 0.85).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    )
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(state.isExpanded ? 0.45 : 0), radius: 18, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Content

private struct NotchContent: View {
    @ObservedObject var viewModel: TelemetryViewModel
    let headerHeight: CGFloat
    let showingSettings: Bool
    let onToggleSettings: () -> Void
    let onOpenURL: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: headerHeight)

            Group {
                if showingSettings {
                    NotchSettingsView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        PowerCard(viewModel: viewModel)
                        RemindersCard()
                        LinearCard(onOpenURL: onOpenURL)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }

    /// The strip beside the camera housing. Its middle sits under the notch, so
    /// content lives at the two ends, as on the Dynamic Island.
    private var header: some View {
        let snap = viewModel.currentSnapshot
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: BatteryGlyph.name(percent: snap.batteryPercent, charging: snap.isCharging || snap.hasChargerConnected))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(snap.isCharging ? Color.green : Color.white, Color.white.opacity(0.35))
                    .font(.system(size: 13, weight: .medium))
                Text("\(snap.batteryPercent)%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.leading, 22)

            Spacer()

            HStack(spacing: 12) {
                SlackBadgeView(onOpen: onDismiss)
                Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                NotchIconButton(
                    systemName: showingSettings ? "xmark" : "gearshape",
                    help: showingSettings ? "Done" : "Settings",
                    action: onToggleSettings
                )
            }
            .padding(.trailing, 22)
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Shared building blocks

enum BatteryGlyph {
    static func name(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// A card on the notch's black surface, styled like widgets on a dark Desktop.
struct NotchCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                accessory()
            }
            .frame(height: 18)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

struct NotchIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// Centred placeholder for empty / permission / error states.
struct CardPlaceholder<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension CardPlaceholder where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

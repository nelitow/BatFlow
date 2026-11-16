import SwiftUI

/// Rough split of system power across running apps. See `AppPowerSampler`.
struct AppsCard: View {
    @ObservedObject var viewModel: TelemetryViewModel

    private static let rowLimit = 6

    var body: some View {
        NotchCard(title: "Apps", systemImage: "square.grid.2x2.fill", tint: .blue) {
            Text("Estimated")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .help("macOS doesn't report power per app. BatFlow splits the system draw above its recent idle level by each app's CPU time.")
        } content: {
            if let estimates = viewModel.appEstimates {
                list(estimates)
            } else {
                CardPlaceholder(systemImage: "gauge.with.dots.needle.33percent", title: "Measuring", message: "Sampling app activity…")
            }
        }
    }

    @ViewBuilder
    private func list(_ estimates: [AppPowerEstimate]) -> some View {
        let shown = Array(estimates.prefix(Self.rowLimit))
        let appTotal = shown.reduce(0) { $0 + $1.watts }
        let rest = max(0, viewModel.currentSnapshot.systemWatts - appTotal)
        let scale = max(shown.first?.watts ?? 0, rest, 0.1)

        VStack(spacing: 8) {
            if shown.isEmpty {
                Text("No app is doing much right now.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(shown) { app in
                AppPowerRow(icon: Image(nsImage: app.icon), name: app.name, watts: app.watts, fraction: app.watts / scale, tint: .blue)
            }
            Spacer(minLength: 0)
            AppPowerRow(
                icon: Image(systemName: "display"),
                name: "Everything else",
                watts: rest,
                fraction: rest / scale,
                tint: .secondary
            )
        }
    }
}

private struct AppPowerRow: View {
    let icon: Image
    let name: String
    let watts: Double
    let fraction: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(String(format: "%.1f W", watts))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint.opacity(0.8))
                                .frame(width: max(2, proxy.size.width * min(1, fraction)))
                        }
                }
                .frame(height: 3)
            }
        }
    }
}

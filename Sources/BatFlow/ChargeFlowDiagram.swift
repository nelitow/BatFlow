import SwiftUI

public struct ChargeFlowDiagram: View {
    let snapshot: PowerSnapshot
    let viewModel: TelemetryViewModel
    
    @State private var phase: CGFloat = 0
    
    public init(snapshot: PowerSnapshot, viewModel: TelemetryViewModel) {
        self.snapshot = snapshot
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Section Header
            HStack {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.cyan)
                    .font(.title3)
                Text("Real-Time Power Flow")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text(snapshot.hasChargerConnected ? "AC Connected" : "Battery Mode")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(snapshot.hasChargerConnected ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(snapshot.hasChargerConnected ? .green : .orange)
                    .clipShape(Capsule())
            }
            
            ZStack {
                // Background glass container
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(LinearGradient(colors: [.cyan.opacity(0.4), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                
                VStack(spacing: 20) {
                    // TOP: Power Source Node (Charger or Main Battery)
                    HStack {
                        Spacer()
                        PowerNodeCard(
                            title: snapshot.hasChargerConnected ? snapshot.chargerName : "Internal Battery",
                            subtitle: snapshot.hasChargerConnected
                                ? String(format: "Drawing of %.0f W available", snapshot.chargerWattsNegotiated)
                                : "Discharging",
                            value: String(format: "%.1f W", snapshot.hasChargerConnected ? snapshot.chargerWattsActual : abs(snapshot.batteryWatts)),
                            icon: snapshot.hasChargerConnected ? "powerplug.fill" : "battery.100bolt",
                            accentColor: snapshot.hasChargerConnected ? .green : .orange
                        )
                        .frame(maxWidth: 240)
                        Spacer()
                    }
                    
                    // Animated Flow Lines Divider
                    FlowLinesView(
                        phase: phase,
                        hasCharger: snapshot.hasChargerConnected,
                        isCharging: snapshot.isCharging,
                        hasOutput: snapshot.outputPortsWatts > 0.05
                    )
                    .frame(height: 36)
                    
                    // BOTTOM: Distribution Targets (CPU/Mac, Battery, USB-C Ports)
                    HStack(alignment: .top, spacing: 12) {
                        // 1. Mac System / CPU
                        PowerNodeCard(
                            title: "Mac & CPU",
                            subtitle: "System Usage",
                            value: String(format: "%.1f W", snapshot.systemWatts),
                            icon: "cpu.fill",
                            accentColor: .blue
                        )
                        
                        // 2. Battery Storage
                        PowerNodeCard(
                            title: snapshot.isCharging ? "Battery Charge" : "Battery Level",
                            subtitle: "\(snapshot.batteryPercent)% • \(viewModel.formattedTemp(snapshot.batteryTempC))",
                            value: String(format: "%@%.1f W", snapshot.batteryWatts > 0 ? "+" : "", snapshot.batteryWatts),
                            icon: snapshot.isCharging ? "battery.100.bolt" : "battery.75",
                            accentColor: snapshot.isCharging ? .green : (snapshot.batteryWatts < 0 ? .orange : .gray)
                        )
                        
                        // 3. Output Ports (iPhone / Accessories)
                        PowerNodeCard(
                            title: "Output Ports",
                            subtitle: snapshot.outputPortsWatts > 0.05 ? "iPhone / Peripherals" : "No Output Draw",
                            value: String(format: "%.1f W", snapshot.outputPortsWatts),
                            icon: "cable.connector",
                            accentColor: snapshot.outputPortsWatts > 0.05 ? .purple : .secondary
                        )
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

// MARK: - Power Node Card View

private struct PowerNodeCard: View {
    let title: String
    let subtitle: String
    let value: String
    let icon: String
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                    .font(.body)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: accentColor.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Animated Flow Lines View

private struct FlowLinesView: View {
    let phase: CGFloat
    let hasCharger: Bool
    let isCharging: Bool
    let hasOutput: Bool
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let topMid = CGPoint(x: width / 2, y: 0)
            
            let bottom1 = CGPoint(x: width * 0.18, y: height)
            let bottom2 = CGPoint(x: width * 0.50, y: height)
            let bottom3 = CGPoint(x: width * 0.82, y: height)
            
            ZStack {
                // Line 1: Main -> Mac/CPU
                FlowPath(from: topMid, to: bottom1, phase: phase, color: .blue)
                
                // Line 2: Main -> Battery
                FlowPath(from: topMid, to: bottom2, phase: phase, color: isCharging ? .green : .orange)
                
                // Line 3: Main -> Output Ports
                FlowPath(from: topMid, to: bottom3, phase: phase, color: hasOutput ? .purple : .gray.opacity(0.3))
            }
        }
    }
}

private struct FlowPath: View {
    let from: CGPoint
    let to: CGPoint
    let phase: CGFloat
    let color: Color
    
    var body: some View {
        Path { path in
            path.move(to: from)
            let midY = (from.y + to.y) / 2
            path.addCurve(to: to, control1: CGPoint(x: from.x, y: midY), control2: CGPoint(x: to.x, y: midY))
        }
        .stroke(
            color.opacity(0.4),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6], dashPhase: -phase * 24)
        )
    }
}

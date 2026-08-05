import SwiftUI

public struct PopoverView: View {
    @ObservedObject var viewModel: TelemetryViewModel
    @State private var showingSettings = false
    
    public init(viewModel: TelemetryViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // App Header Bar
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Image(systemName: "bolt.batteryblock.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BatFlow")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("Power Telemetry & Flow")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        showingSettings.toggle()
                    }
                } label: {
                    Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
                        .font(.body)
                        .foregroundColor(showingSettings ? .cyan : .secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 18) {
                    if showingSettings {
                        // Settings Section
                        SettingsPanel(viewModel: viewModel)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Battery Overview Header Card
                    BatteryHeaderCard(snapshot: viewModel.currentSnapshot, viewModel: viewModel)
                    
                    // Real-Time Charge Flow Diagram
                    ChargeFlowDiagram(snapshot: viewModel.currentSnapshot, viewModel: viewModel)
                    
                    // USB-C Output Ports
                    PortInspectorView(ports: viewModel.currentSnapshot.ports, totalOutputWatts: viewModel.currentSnapshot.outputPortsWatts)
                    
                    // Telemetry Charts
                    TelemetryChartsView(history: viewModel.history, viewModel: viewModel)
                }
                .padding(16)
            }
        }
        .frame(width: 440, height: 680)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

// MARK: - Battery Header Card View

private struct BatteryHeaderCard: View {
    let snapshot: PowerSnapshot
    let viewModel: TelemetryViewModel
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            snapshot.isCharging ? Color.green.opacity(0.15) : Color.blue.opacity(0.15),
                            Color(nsColor: .windowBackgroundColor).opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(snapshot.isCharging ? Color.green.opacity(0.4) : Color.blue.opacity(0.3), lineWidth: 1)
                )
            
            HStack(spacing: 16) {
                // Left: Ring Gauge for Battery Level %
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 64, height: 64)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(snapshot.batteryPercent) / 100.0)
                        .stroke(
                            snapshot.batteryPercent > 20 ? Color.green : Color.red,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 64, height: 64)
                    
                    VStack(spacing: 0) {
                        Text("\(snapshot.batteryPercent)%")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(snapshot.isFullyCharged ? "Fully Charged" : (snapshot.isCharging ? "Charging" : "Discharging"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(snapshot.isCharging ? .green : .primary)
                        
                        Spacer()
                        
                        // Battery Temp Badge
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .foregroundColor(snapshot.batteryTempC > 38.0 ? .red : .orange)
                            Text(viewModel.formattedTemp(snapshot.batteryTempC))
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    
                    // Health & Cycles — gated by user preference
                    if viewModel.showHealthAndCycles {
                        HStack(spacing: 12) {
                            Label("Health: \(String(format: "%.0f%%", snapshot.healthPercent))", systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Label("Cycles: \(snapshot.cycleCount)", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // ETA — always visible when data is available
                    if let tFull = snapshot.timeToFullMin {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text(etaString(minutes: tFull, label: "until full"))
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else if let tEmpty = snapshot.timeToEmptyMin {
                        HStack(spacing: 4) {
                            Image(systemName: "battery.25")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(etaString(minutes: tEmpty, label: "remaining"))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
    
    private func etaString(minutes: Int, label: String) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h)h \(m)m \(label)"
        } else {
            return "\(m)m \(label)"
        }
    }
}

// MARK: - Settings Panel View

private struct SettingsPanel: View {
    @ObservedObject var viewModel: TelemetryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Preferences")
                .font(.headline)
            
            HStack {
                Text("Temperature Unit")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $viewModel.tempUnit) {
                    ForEach(TempUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            
            HStack {
                Text("Polling Interval")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $viewModel.pollingInterval) {
                    Text("1 sec").tag(1.0)
                    Text("2 sec").tag(2.0)
                    Text("5 sec").tag(5.0)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            
            HStack {
                Text("Menu Bar Format")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $viewModel.statusBarFormat) {
                    ForEach(StatusBarFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            
            Divider()
            
            Toggle(isOn: $viewModel.showHealthAndCycles) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Health & Cycle Count")
                        .font(.subheadline)
                    Text("Displays battery health % and charge cycle count")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        )
    }
}

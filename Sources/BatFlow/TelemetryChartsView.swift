import SwiftUI
import Charts

public struct TelemetryChartsView: View {
    let history: [PowerSnapshot]
    let viewModel: TelemetryViewModel
    
    @State private var selectedTab = 0
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                    .font(.title3)
                Text("Telemetry History")
                    .font(.headline)
                
                Spacer()
                
                Picker("", selection: $selectedTab) {
                    Text("Power (W)").tag(0)
                    Text("Battery & Temp").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            
            if history.count < 2 {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Collecting telemetry history...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor).opacity(0.4)))
            } else {
                VStack(spacing: 8) {
                    if selectedTab == 0 {
                        // Power Breakdown Chart
                        Chart {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, item in
                                LineMark(
                                    x: .value("Sample", index),
                                    y: .value("Mac Usage", item.systemWatts),
                                    series: .value("Metric", "Mac Usage (W)")
                                )
                                .foregroundStyle(.blue)
                                .interpolationMethod(.catmullRom)
                                
                                LineMark(
                                    x: .value("Sample", index),
                                    y: .value("Battery Power", abs(item.batteryWatts)),
                                    series: .value("Metric", item.isCharging ? "Battery Charge (W)" : "Battery Discharge (W)")
                                )
                                .foregroundStyle(item.isCharging ? .green : .orange)
                                .interpolationMethod(.catmullRom)
                                
                                if item.outputPortsWatts > 0.05 {
                                    LineMark(
                                        x: .value("Sample", index),
                                        y: .value("Output Ports", item.outputPortsWatts),
                                        series: .value("Metric", "Output Ports (W)")
                                    )
                                    .foregroundStyle(.purple)
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartXAxis(.hidden)
                        .chartLegend(position: .bottom, alignment: .center)
                        .frame(height: 150)
                    } else {
                        // Battery & Temp Chart
                        Chart {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, item in
                                LineMark(
                                    x: .value("Sample", index),
                                    y: .value("Battery %", item.batteryPercent),
                                    series: .value("Metric", "Battery %")
                                )
                                .foregroundStyle(.green)
                                
                                LineMark(
                                    x: .value("Sample", index),
                                    y: .value("Temp °C", item.batteryTempC),
                                    series: .value("Metric", "Battery Temp (°C)")
                                )
                                .foregroundStyle(.red)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartXAxis(.hidden)
                        .chartLegend(position: .bottom, alignment: .center)
                        .frame(height: 150)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
    }
}

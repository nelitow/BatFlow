import SwiftUI

public struct PortInspectorView: View {
    let ports: [PortInfo]
    let totalOutputWatts: Double
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(.purple)
                    .font(.title3)
                Text("USB-C Output Ports")
                    .font(.headline)
                Spacer()
                Text(String(format: "Total Output: %.1f W", totalOutputWatts))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(totalOutputWatts > 0.05 ? .purple : .secondary)
            }
            
            if ports.isEmpty {
                HStack {
                    Spacer()
                    Text("No USB-C Port telemetry reported by IOKit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(ports) { port in
                        HStack(spacing: 12) {
                            Image(systemName: port.isConnected ? "bolt.port.a.fill" : "port.a.fill")
                                .foregroundColor(port.isConnected ? .purple : .gray)
                                .font(.body)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("USB-C Port \(port.index)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(port.isConnected ? String(format: "%.2f V • %.2f A", port.voltageVolts, port.currentAmps) : "Idle / Disconnected")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f W", port.watts))
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(port.isConnected ? .purple : .secondary)
                                
                                Text(port.isConnected ? "Active Output" : "Off")
                                    .font(.caption2)
                                    .foregroundColor(port.isConnected ? .green : .secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(port.isConnected ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
    }
}

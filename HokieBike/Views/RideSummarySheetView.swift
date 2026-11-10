import SwiftUI

struct RideSummarySheetView: View {
    let summary: RideSummary
    let onShareToCommunity: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var didShareToCommunity = false

    init(summary: RideSummary, onShareToCommunity: (() -> Void)? = nil) {
        self.summary = summary
        self.onShareToCommunity = onShareToCommunity
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary.didArrive ? "Destination reached" : "Route complete")
                    .font(.title3.bold())

                if let destinationName = summary.destinationName {
                    Label(destinationName, systemImage: "mappin.and.ellipse")
                        .foregroundColor(.secondary)
                }

                statCard(title: "Distance", value: String(format: "%.2f mi / %.2f km", miles, kilometers), icon: "figure.outdoor.cycle")
                statCard(title: "Duration", value: formattedDuration(summary.durationSeconds), icon: "clock")
                statCard(title: "Average Speed", value: String(format: "%.1f mph / %.1f kph", mph, summary.averageSpeedKph), icon: "speedometer")

                if let onShareToCommunity {
                    Button {
                        onShareToCommunity()
                        didShareToCommunity = true
                    } label: {
                        Label(didShareToCommunity ? "Posted" : "Post", systemImage: didShareToCommunity ? "checkmark.circle.fill" : "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(didShareToCommunity)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("VTMaroon"))
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Journey Stats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var kilometers: Double {
        summary.distanceMeters / 1000.0
    }

    private var miles: Double {
        kilometers * 0.621371
    }

    private var mph: Double {
        summary.averageSpeedKph * 0.621371
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color("VTMaroon"))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formattedDuration(_ value: TimeInterval) -> String {
        let total = Int(value)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    RideSummarySheetView(
        summary: RideSummary(
            endedAt: Date(),
            destinationName: "Lane Stadium",
            durationSeconds: 1140,
            distanceMeters: 3200,
            averageSpeedKph: 10.1,
            didArrive: true
        )
    )
}

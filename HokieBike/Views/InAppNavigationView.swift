import SwiftUI
import MapKit
import CoreLocation

struct InAppNavigationView: View {
    @EnvironmentObject var rideTrackingManager: RideTrackingManager

    let onOpenAppleMaps: () -> Void
    let onEndRide: () -> Void
    let onClose: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                if let route = rideTrackingManager.plannedRoute {
                    MapPolyline(route.polyline)
                        .stroke(Color("VTOrange"), lineWidth: 5)
                }

                if trackedPathPolyline.pointCount > 1 {
                    MapPolyline(trackedPathPolyline)
                        .stroke(Color("VTMaroon"), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                if let destination = rideTrackingManager.destinationCoordinate {
                    Marker("Destination", coordinate: destination)
                        .tint(Color("VTOrange"))
                }

                UserAnnotation()
            }
            .ignoresSafeArea()
            .onReceive(rideTrackingManager.$currentCoordinate) { coordinate in
                guard let coordinate else { return }
                withAnimation {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                }
            }

            VStack(spacing: 10) {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }

                    Spacer()

                    if rideTrackingManager.isTracking {
                        Text("LIVE")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    if let destination = rideTrackingManager.destinationName {
                        Text("To: \(destination)")
                            .font(.headline)
                    }

                    if let nextInstruction = rideTrackingManager.nextInstruction {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbolName(for: nextInstruction))
                                .font(.title3.weight(.semibold))
                                .foregroundColor(maneuverColor(for: nextInstruction))
                                .frame(width: 24)

                            Text(nextInstruction)
                                .font(.title3.weight(.semibold))
                                .lineLimit(2)

                            Spacer()
                        }
                    }

                    if !rideTrackingManager.upcomingDirectionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Directions")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            ForEach(Array(rideTrackingManager.upcomingDirectionItems.dropFirst().prefix(3).enumerated()), id: \.element.id) { index, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Image(systemName: symbolName(for: item.instruction))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(maneuverColor(for: item.instruction))
                                        .frame(width: 14)
                                    Text(item.instruction)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                    Text(stepDistanceText(item.distanceMeters))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.gray.opacity(0.15))
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        if let remaining = rideTrackingManager.remainingDistanceMeters {
                            Label(String(format: "%.1f km", remaining / 1000.0), systemImage: "ruler")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let eta = rideTrackingManager.remainingETASeconds {
                            Label(eta.formattedDuration, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            onOpenAppleMaps()
                        } label: {
                            Label("Apple Maps", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onEndRide()
                            onClose()
                        } label: {
                            Label("End", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("VTMaroon"))
                    }
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .onChange(of: rideTrackingManager.arrivalEventID) { _, newValue in
            guard newValue != nil else { return }
            onClose()
        }
    }

    private var trackedPathPolyline: MKPolyline {
        MKPolyline(coordinates: rideTrackingManager.trackedPath, count: rideTrackingManager.trackedPath.count)
    }

    private func symbolName(for instruction: String) -> String {
        let value = instruction.lowercased()

        if value.contains("arrived") || value.contains("destination") {
            return "mappin.and.ellipse"
        }
        if value.contains("u-turn") {
            return "arrow.uturn.left"
        }
        if value.contains("slight right") {
            return "arrow.up.right"
        }
        if value.contains("slight left") {
            return "arrow.up.left"
        }
        if value.contains("right") {
            return "arrow.turn.up.right"
        }
        if value.contains("left") {
            return "arrow.turn.up.left"
        }
        if value.contains("merge") {
            return "arrow.triangle.merge"
        }
        if value.contains("roundabout") {
            return "arrow.clockwise"
        }
        if value.contains("continue") || value.contains("head") || value.contains("straight") {
            return "arrow.up"
        }

        return "location.north.line"
    }

    private func maneuverColor(for instruction: String) -> Color {
        let value = instruction.lowercased()
        if value.contains("arrived") || value.contains("destination") {
            return Color.green
        }
        if value.contains("left") || value.contains("u-turn") {
            return Color.orange
        }
        if value.contains("right") {
            return Color.blue
        }
        return Color("VTMaroon")
    }

    private func stepDistanceText(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000.0)
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: self) ?? "N/A"
    }
}

#Preview {
    InAppNavigationView(onOpenAppleMaps: {}, onEndRide: {}, onClose: {})
        .environmentObject(RideTrackingManager())
}

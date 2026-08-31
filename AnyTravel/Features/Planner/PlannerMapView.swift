import MapKit
import SwiftUI

struct PlannerMapView: View {
    @Bindable var model: PlannerViewModel
    let mapScope: Namespace.ID

    var body: some View {
        Map(position: $model.cameraPosition, interactionModes: .all, scope: mapScope) {
            UserAnnotation()

            ForEach(model.visibleLegs) { leg in
                MapPolyline(leg.route)
                    .stroke(.white.opacity(0.92), lineWidth: 10)
                MapPolyline(leg.route)
                    .stroke(
                        AnyTravelPalette.routeColor(for: leg.dayIndex),
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(Array(model.currentStops.enumerated()), id: \.element.id) { index, stop in
                Annotation(coordinate: stop.coordinate.clLocationCoordinate, anchor: .center) {
                    StopMarker(
                        index: index + 1,
                        stop: stop,
                        color: AnyTravelPalette.routeColor(for: model.selectedDayIndex),
                        isSelected: model.selectedPlaceID == stop.id
                    ) {
                        model.selectPlace(stop)
                    }
                } label: {
                    EmptyView()
                }
            }

            ForEach(model.visibleAccommodations) { option in
                Annotation(coordinate: option.coordinate.clLocationCoordinate, anchor: .center) {
                    AccommodationMarker(
                        option: option,
                        isSelected: model.selectedAccommodationID == option.id
                    ) {
                        model.selectAccommodation(option)
                    }
                } label: {
                    EmptyView()
                }
            }

            ForEach(model.visibleAccessPoints) { point in
                Annotation(coordinate: point.coordinate.clLocationCoordinate, anchor: .bottom) {
                    AccessPointMarker(point: point)
                } label: {
                    EmptyView()
                }
            }
        }
        .mapStyle(model.mapAppearance.mapStyle)
        .mapScope(mapScope)
        .ignoresSafeArea()
        .onChange(of: model.cameraPosition.positionedByUser) { _, positionedByUser in
            if positionedByUser {
                model.userMovedMap()
            }
        }
    }
}

private struct AccommodationMarker: View {
    let option: AccommodationOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "bed.double.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? AnyTravelPalette.warm : AnyTravelPalette.route, in: Circle())
                if isSelected {
                    Text(option.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AnyTravelPalette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: 180, minHeight: 34)
                        .background(.background.opacity(0.96), in: Capsule())
                }
            }
            .padding(5)
            .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityLabel("住宿，\(option.name)")
    }
}

private struct AccessPointMarker: View {
    let point: AccessPoint

    var body: some View {
        VStack(spacing: 4) {
            Label(point.name, systemImage: point.kind.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AnyTravelPalette.ink)
                .padding(.horizontal, 9)
                .frame(minHeight: 32)
                .background(.background.opacity(0.96), in: Capsule())
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.background.opacity(0.96))
                .rotationEffect(.degrees(180))
                .offset(y: -6)
        }
        .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
        .accessibilityElement(children: .combine)
    }
}

private struct StopMarker: View {
    let index: Int
    let stop: TravelPlace
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(index.formatted())
                    .font(.caption.bold())
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(.background, in: Circle())
                    .overlay {
                        Circle().strokeBorder(color, lineWidth: isSelected ? 4 : 3)
                    }

                if isSelected {
                    Text(stop.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(AnyTravelPalette.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(.background.opacity(0.96), in: Capsule())
                        .overlay { Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1) }
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                }
            }
            .padding(6)
            .scaleEffect(isSelected ? 1.08 : 1)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityLabel("第 \(index) 站，\(stop.name)")
        .accessibilityHint("轻点后地图会聚焦这个地点")
        .animation(.snappy(duration: 0.24), value: isSelected)
    }
}

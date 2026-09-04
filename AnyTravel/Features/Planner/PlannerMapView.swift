import MapKit
import SwiftUI

struct PlannerMapView: View {
    @Bindable var model: PlannerViewModel
    let mapScope: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Map(position: $model.cameraPosition, interactionModes: .all, scope: mapScope) {
            UserAnnotation()

            if let transferRoute = model.visibleTransferRoute {
                MapPolyline(transferRoute)
                    .stroke(AnyTravelPalette.mapRouteHalo, lineWidth: 11)
                MapPolyline(transferRoute)
                    .stroke(
                        model.focusedTransportDirection == .outbound
                            ? AnyTravelPalette.route
                            : AnyTravelPalette.warm,
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round, dash: [4, 7])
                    )
            }

            ForEach(model.visibleLegs) { leg in
                MapPolyline(leg.route)
                    .stroke(AnyTravelPalette.mapRouteHalo, lineWidth: 10)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    SelectionPulse(color: AnyTravelPalette.warm, isActive: isSelected)
                    Image(systemName: "bed.double.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(isSelected ? AnyTravelPalette.warm : AnyTravelPalette.route, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                if isSelected {
                    Text(option.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AnyTravelPalette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: 180, minHeight: 34)
                        .background(.background.opacity(0.96), in: Capsule())
                        .transition(.scale(scale: 0.86, anchor: .leading).combined(with: .opacity))
                }
            }
            .padding(5)
            .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
            .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityLabel("住宿，\(option.name)")
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: isSelected)
    }
}

private struct AccessPointMarker: View {
    let point: AccessPoint
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .scaleEffect(appeared || reduceMotion ? 1 : 0.82, anchor: .bottom)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(AnyTravelMotion.settle(reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StopMarker: View {
    let index: Int
    let stop: TravelPlace
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    SelectionPulse(color: color, isActive: isSelected)
                    Text(index.formatted())
                        .font(.caption.bold())
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .frame(width: 32, height: 32)
                        .background(.background, in: Circle())
                        .overlay {
                            Circle().strokeBorder(color, lineWidth: isSelected ? 4 : 3)
                        }
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
            .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityLabel("第 \(index) 站，\(stop.name)")
        .accessibilityHint("轻点后地图会聚焦这个地点")
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: isSelected)
    }
}

private struct SelectionPulse: View {
    let color: Color
    let isActive: Bool

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(color.opacity(expanded ? 0 : 0.48), lineWidth: 2)
            .frame(width: 36, height: 36)
            .scaleEffect(expanded ? 1.58 : 0.92)
            .opacity(isActive ? 1 : 0)
            .task(id: isActive) {
                expanded = false
                guard isActive, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(24))
                withAnimation(.easeOut(duration: 0.68)) {
                    expanded = true
                }
            }
            .accessibilityHidden(true)
    }
}

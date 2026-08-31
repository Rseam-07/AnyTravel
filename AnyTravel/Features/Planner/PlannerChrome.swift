import MapKit
import SwiftUI

struct PlannerChrome: View {
    @Bindable var model: PlannerViewModel
    let mapScope: Namespace.ID

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Button {
                    model.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(AnyTravelPressStyle())
                .anyTravelGlassCircle()
                .accessibilityLabel("重新规划")

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.topTitle)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text(model.topSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 15)
                .anyTravelGlassCard(cornerRadius: 18)

                Button {
                    model.settingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(AnyTravelPressStyle())
                .anyTravelGlassCircle()
                .accessibilityLabel("旅途偏好与价格渠道")

                Button {
                    model.libraryPresented = true
                } label: {
                    Image(systemName: "suitcase.rolling")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(AnyTravelPressStyle())
                .anyTravelGlassCircle()
                .accessibilityLabel("已保存行程")
            }

            ProgressDots(currentStep: model.progressStep)

            HStack(alignment: .top) {
                if let status = model.routeStatusText {
                    Label(status, systemImage: model.isRouteLoading ? "arrow.trianglehead.2.clockwise.rotate.90" : "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AnyTravelPalette.routeDark)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .anyTravelGlassCapsule(interactive: false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 12)

                VStack(spacing: 9) {
                    MapUserLocationButton(scope: mapScope)
                        .frame(width: 48, height: 48)
                        .tint(AnyTravelPalette.ink)
                        .foregroundStyle(AnyTravelPalette.ink)
                        .overlay {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AnyTravelPalette.ink)
                                .allowsHitTesting(false)
                        }
                        .anyTravelGlassCircle()
                        .accessibilityLabel("回到当前位置")

                    Menu {
                        ForEach(MapAppearance.allCases) { appearance in
                            Button {
                                model.mapAppearance = appearance
                            } label: {
                                Label(appearance.title, systemImage: appearance.symbolName)
                            }
                        }
                    } label: {
                        Image(systemName: model.mapAppearance.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(AnyTravelPressStyle())
                    .anyTravelGlassCircle()
                    .accessibilityLabel("地图样式，当前为\(model.mapAppearance.title)")

                    MapCompass(scope: mapScope)
                        .frame(width: 48, height: 48)
                        .anyTravelGlassCircle()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.32), value: model.routeStatusText)
        .allowsHitTesting(true)
    }
}

private struct ProgressDots: View {
    let currentStep: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? AnyTravelPalette.route : Color.secondary.opacity(0.30))
                    .frame(width: index == currentStep ? 22 : 7, height: 7)
            }
        }
        .padding(6)
        .anyTravelGlassCapsule(interactive: false)
        .animation(.snappy(duration: 0.3), value: currentStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("规划进度，第 \(currentStep + 1) 步，共 4 步")
    }
}

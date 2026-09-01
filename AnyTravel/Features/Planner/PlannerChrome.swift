import SwiftUI

struct PlannerChrome: View {
    @Bindable var model: PlannerViewModel
    let panelDetent: PlannerPanelDetent
    let openSettings: () -> Void
    let openLibrary: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Button {
                    model.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(AnyTravelPressStyle())
                .anyTravelGlassCircle()
                .accessibilityLabel("重新规划")
                .accessibilityIdentifier("global-reset")

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.topTitle)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Text(model.topSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 15)
                .anyTravelGlassCard(cornerRadius: 18, interactive: false)

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(AnyTravelPressStyle())
                .anyTravelGlassCircle()
                .accessibilityLabel("旅途偏好与价格渠道")
                .accessibilityIdentifier("global-settings")

                Button {
                    openLibrary()
                } label: {
                    Image(systemName: "suitcase.rolling")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(AnyTravelPressStyle())
                .anyTravelGlassCircle()
                .accessibilityLabel("已保存行程")
                .accessibilityIdentifier("global-library")
            }

            if panelDetent != .expanded {
                ProgressDots(currentStep: model.progressStep)

                HStack(alignment: .top) {
                    if let status = model.routeStatusText {
                        HStack(spacing: 7) {
                            RouteStatusIcon(isLoading: model.isRouteLoading || model.isLogisticsLoading)
                            Text(status)
                                .contentTransition(.opacity)
                        }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AnyTravelPalette.routeDark)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .anyTravelGlassCapsule(interactive: false)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer(minLength: 12)

                    VStack(spacing: 9) {
                        Button {
                            model.focusUserLocation()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .contentShape(Circle())
                        }
                        .buttonStyle(AnyTravelPressStyle())
                        .anyTravelGlassCircle()
                        .accessibilityLabel("回到当前位置")
                        .accessibilityHint("若尚未授权定位，系统会先询问；否则回到当前旅程")
                        .accessibilityIdentifier("global-location")

                        Button {
                            model.cycleMapAppearance()
                        } label: {
                            Image(systemName: model.mapAppearance.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 48, height: 48)
                                .contentShape(Circle())
                        }
                        .buttonStyle(AnyTravelPressStyle())
                        .anyTravelGlassCircle()
                        .contextMenu {
                            ForEach(MapAppearance.allCases) { appearance in
                                Button {
                                    model.mapAppearance = appearance
                                    model.mapActionFeedbackTrigger += 1
                                } label: {
                                    Label(appearance.title, systemImage: appearance.symbolName)
                                }
                            }
                        }
                        .accessibilityLabel("切换地图样式")
                        .accessibilityValue(model.mapAppearance.title)
                        .accessibilityHint("轻点依次切换标准、卫星与混合地图；长按可直接选择")
                        .accessibilityIdentifier("global-map-style")

                        Button {
                            model.orientMapNorth()
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(AnyTravelPalette.ink.opacity(0.22), lineWidth: 1)
                                    .frame(width: 35, height: 35)
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AnyTravelPalette.ink)
                            }
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                        }
                        .buttonStyle(AnyTravelPressStyle())
                        .anyTravelGlassCircle()
                        .accessibilityLabel("地图回到北向")
                        .accessibilityIdentifier("global-north")
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.routeStatusText)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.topSubtitle)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.mapAppearance)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: panelDetent)
    }
}

private struct ProgressDots: View {
    let currentStep: Int
    @Namespace private var selectionMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                ZStack {
                    Capsule()
                        .fill(Color.secondary.opacity(0.24))
                    if index == currentStep {
                        Capsule()
                            .fill(AnyTravelPalette.route)
                            .matchedGeometryEffect(id: "planner-progress", in: selectionMotion)
                    }
                }
                    .frame(width: index == currentStep ? 22 : 7, height: 7)
            }
        }
        .padding(6)
        .anyTravelGlassCapsule(interactive: false)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: currentStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("规划进度，第 \(currentStep + 1) 步，共 4 步")
    }
}

private struct RouteStatusIcon: View {
    let isLoading: Bool

    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: isLoading ? "arrow.trianglehead.2.clockwise.rotate.90" : "point.topleft.down.to.point.bottomright.curvepath")
            .contentTransition(.symbolEffect(.replace))
            .rotationEffect(.degrees(rotation))
            .onAppear { updateRotation() }
            .onChange(of: isLoading) { _, _ in updateRotation() }
    }

    private func updateRotation() {
        guard isLoading, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.16)) { rotation = 0 }
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 0.92).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

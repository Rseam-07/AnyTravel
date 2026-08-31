import SwiftUI

struct PlannerPanel: View {
    @Bindable var model: PlannerViewModel
    @State private var readyExpanded = false
    @FocusState private var destinationFocused: Bool
    @FocusState private var adjustmentFocused: Bool

    var body: some View {
        Group {
            switch model.phase {
            case .destination:
                destinationPanel
            case .preferences:
                preferencesPanel
            case .discovering:
                discoveringPanel
            case .ready:
                readyPanel
            case .failure:
                failurePanel
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .anyTravelGlassCard(cornerRadius: 31)
        .animation(.snappy(duration: 0.42), value: model.phase)
    }

    private var handle: some View {
        Capsule()
            .fill(.secondary.opacity(0.28))
            .frame(width: 38, height: 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var destinationPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            handle
            VStack(alignment: .leading, spacing: 4) {
                Text("从地图开始，不填长表格")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AnyTravelPalette.route)
                Text("想把哪里变成一段行程？")
                    .font(.title2.bold())
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AnyTravelPalette.route)
                TextField(
                    "输入城市、区域或目的地",
                    text: Binding(
                        get: { model.draft.destination },
                        set: { model.draft.destination = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
                .focused($destinationFocused)
                .onSubmit {
                    guard model.canContinueDestination else { return }
                    Task { await model.resolveDestination() }
                }

                if !model.draft.destination.isEmpty {
                    Button {
                        model.draft.destination = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空目的地")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(AnyTravelPalette.softSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(AnyTravelPalette.route.opacity(0.26), lineWidth: 1)
            }

            HStack(spacing: 8) {
                ForEach(["苏州", "杭州", "成都"], id: \.self) { city in
                    Button(city) {
                        model.draft.destination = city
                        destinationFocused = false
                        Task { await model.resolveDestination() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(AnyTravelPalette.route.opacity(0.10), in: Capsule())
                }
            }

            primaryButton(title: "在地图上定位", systemImage: "location.magnifyingglass") {
                destinationFocused = false
                Task { await model.resolveDestination() }
            }
            .disabled(!model.canContinueDestination)
            .opacity(model.canContinueDestination ? 1 : 0.45)
        }
    }

    private var preferencesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            handle
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("地图已定位到 \(model.destination?.title ?? model.draft.destination)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AnyTravelPalette.route)
                    Text("再加几个条件")
                        .font(.title2.bold())
                }
                Spacer()
                Button("改目的地") {
                    model.returnToEditing()
                    model.destination = nil
                    model.phase = .destination
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }

            HStack(spacing: 10) {
                compactStepper(
                    title: "天数",
                    valueText: "\(model.draft.dayCount)天",
                    decrementDisabled: model.draft.dayCount <= 1,
                    incrementDisabled: model.draft.dayCount >= 7,
                    decrement: { model.draft.dayCount = max(1, model.draft.dayCount - 1) },
                    increment: { model.draft.dayCount = min(7, model.draft.dayCount + 1) }
                )

                compactStepper(
                    title: "人均预算",
                    valueText: "¥\(model.draft.budgetPerPerson.formatted(.number.grouping(.automatic)))",
                    decrementDisabled: model.draft.budgetPerPerson <= 1_000,
                    incrementDisabled: model.draft.budgetPerPerson >= 30_000,
                    decrement: { model.draft.budgetPerPerson = max(1_000, model.draft.budgetPerPerson - 500) },
                    increment: { model.draft.budgetPerPerson = min(30_000, model.draft.budgetPerPerson + 500) }
                )
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(TripInterest.allCases) { interest in
                        interestChip(interest)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                Menu {
                    ForEach(TripPace.allCases) { pace in
                        Button(pace.title) { model.draft.pace = pace }
                    }
                } label: {
                    Label(model.draft.pace.title, systemImage: "speedometer")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Menu {
                    ForEach(TravelMode.allCases) { mode in
                        Button {
                            model.draft.travelMode = mode
                        } label: {
                            Label(mode.title, systemImage: mode.symbolName)
                        }
                    }
                } label: {
                    Label(model.draft.travelMode.title, systemImage: model.draft.travelMode.symbolName)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .font(.caption.weight(.semibold))

            primaryButton(title: "让地图生成路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                Task { await model.generatePlan() }
            }
        }
    }

    private var discoveringPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            handle
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AnyTravelPalette.route)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.activityTitle)
                        .font(.headline)
                    Text(model.activityDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 7) {
                activityStep("筛地点", active: true)
                activityStep("排顺序", active: model.activityTitle.contains("顺序"))
                activityStep("画路线", active: model.isRouteLoading)
            }

            Button("返回修改") {
                model.returnToEditing()
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.plain)
        }
    }

    private var failurePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            handle
            Label("这一步没有完成", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AnyTravelPalette.warm)
            Text(model.errorMessage ?? "发生了未知错误。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("返回修改") {
                    model.returnToEditing()
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .buttonStyle(.plain)
                .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("重试") {
                    Task { await model.retry() }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .background(AnyTravelPalette.route, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .fontWeight(.semibold)
        }
    }

    private var readyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.35)) {
                    readyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(.secondary.opacity(0.28))
                        .frame(width: 38, height: 4)
                    Image(systemName: readyExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(readyExpanded ? "收起行程详情" : "展开行程详情")

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(model.itineraryDays) { day in
                        Button(day.title) {
                            model.selectDay(day.index)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.selectedDayIndex == day.index ? .white : AnyTravelPalette.routeDark)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 38)
                        .background(
                            model.selectedDayIndex == day.index
                                ? AnyTravelPalette.routeColor(for: day.index)
                                : AnyTravelPalette.softSurface,
                            in: Capsule()
                        )
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.destination?.title ?? model.draft.destination) · \(model.currentDay?.title ?? "行程")")
                        .font(.title3.bold())
                    if let routeSummary = model.routeSummary {
                        Text(routeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.isRouteLoading {
                        Text("正在加载真实路线…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    model.saveCurrentTrip()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            if let selectedPlace = model.selectedPlace {
                selectedPlaceCard(selectedPlace)
            } else if readyExpanded {
                stopsList
            } else {
                compactStopsStrip
            }

            if let notice = model.noticeMessage {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "info.circle")
                    Text(notice)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.currentLegs.isEmpty,
                       (model.failedSegmentsByDay[model.selectedDayIndex] ?? 0) > 0 {
                        Button("重试") { model.retryCurrentDayRoute() }
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(AnyTravelPalette.secondaryInk)
            }

            HStack(spacing: 8) {
                TextField(
                    "比如：轻松一点，多安排美食",
                    text: Binding(
                        get: { model.adjustmentText },
                        set: { model.adjustmentText = $0 }
                    )
                )
                .focused($adjustmentFocused)
                .submitLabel(.send)
                .onSubmit {
                    adjustmentFocused = false
                    Task { await model.applyAdjustment() }
                }

                Button {
                    adjustmentFocused = false
                    Task { await model.applyAdjustment() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(AnyTravelPalette.route, in: Circle())
                }
                .buttonStyle(AnyTravelPressStyle())
                .disabled(model.adjustmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(model.adjustmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("应用路线修改")
            }
            .padding(.leading, 13)
            .padding(.trailing, 7)
            .frame(minHeight: 50)
            .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if readyExpanded {
                Text("地点与路线来自 Apple Maps；营业时间、票价与临时闭馆信息请在出发前再次核对。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var compactStopsStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(model.currentStops.enumerated()), id: \.element.id) { index, stop in
                    Button {
                        model.selectPlace(stop)
                    } label: {
                        HStack(spacing: 7) {
                            Text((index + 1).formatted())
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(AnyTravelPalette.routeColor(for: model.selectedDayIndex), in: Circle())
                            Text(stop.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .frame(minHeight: 42)
                        .background(AnyTravelPalette.softSurface, in: Capsule())
                    }
                    .buttonStyle(AnyTravelPressStyle())
                    .accessibilityLabel("第 \(index + 1) 站，\(stop.name)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var stopsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.currentStops.enumerated()), id: \.element.id) { index, stop in
                    Button {
                        model.selectPlace(stop)
                    } label: {
                        HStack(spacing: 10) {
                            Text((index + 1).formatted())
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(AnyTravelPalette.routeColor(for: model.selectedDayIndex), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(stop.interest.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "scope")
                                .foregroundStyle(AnyTravelPalette.route)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < model.currentStops.count - 1 {
                        Divider().padding(.leading, 38)
                    }
                }
            }
        }
        .frame(maxHeight: 156)
    }

    private func selectedPlaceCard(_ place: TravelPlace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.headline)
                    Text(place.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    model.dismissSelectedPlace()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭地点详情")
            }

            HStack {
                Label(place.source, systemImage: "map")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.openInMaps(place)
                } label: {
                    Label("在地图中打开", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AnyTravelPalette.route)
            }
        }
        .padding(12)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func primaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(AnyTravelPalette.route, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(AnyTravelPressStyle())
    }

    private func interestChip(_ interest: TripInterest) -> some View {
        let selected = model.draft.interests.contains(interest)
        return Button {
            model.toggleInterest(interest)
        } label: {
            Label(interest.title, systemImage: interest.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
                .background(selected ? AnyTravelPalette.route : AnyTravelPalette.softSurface, in: Capsule())
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func compactStepper(
        title: String,
        valueText: String,
        decrementDisabled: Bool,
        incrementDisabled: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                }
                .disabled(decrementDisabled)
                Text(valueText)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button(action: increment) {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .disabled(incrementDisabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func activityStep(_ title: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(active ? AnyTravelPalette.route : Color.secondary.opacity(0.25))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(active ? AnyTravelPalette.routeDark : .secondary)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(AnyTravelPalette.softSurface, in: Capsule())
    }
}

import SwiftUI

struct PlannerPanel: View {
    @Bindable var model: PlannerViewModel
    let panelDetent: PlannerPanelDetent
    @State private var selectedTransportDirection: TransportDirection = .outbound
    @FocusState private var destinationFocused: Bool
    @FocusState private var adjustmentFocused: Bool
    @Namespace private var sectionMotion
    @Namespace private var dayMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if panelDetent == .compact {
                compactPanel
                    .transition(AnyTravelMotion.panelTransition(reduceMotion: reduceMotion))
            } else {
                switch model.phase {
                case .destination:
                    destinationPanel
                        .transition(AnyTravelMotion.panelTransition(reduceMotion: reduceMotion))
                case .preferences:
                    preferencesPanel
                        .transition(AnyTravelMotion.panelTransition(reduceMotion: reduceMotion))
                case .discovering:
                    discoveringPanel
                        .transition(AnyTravelMotion.panelTransition(reduceMotion: reduceMotion))
                case .ready:
                    readyPanel
                        .transition(AnyTravelMotion.panelTransition(reduceMotion: reduceMotion))
                case .failure:
                    failurePanel
                        .transition(AnyTravelMotion.panelTransition(reduceMotion: reduceMotion))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .anyTravelGlassCard(cornerRadius: 31)
        .animation(AnyTravelMotion.settle(reduceMotion: reduceMotion), value: model.phase)
    }

    private var handle: some View {
        Color.clear
            .frame(height: 20)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var readyExpanded: Bool {
        panelDetent == .expanded
    }

    private var compactPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            handle

            switch model.phase {
            case .destination:
                compactRequestComposer(
                    text: Binding(get: { model.travelRequestText }, set: { model.travelRequestText = $0 }),
                    placeholder: "下一次旅行，你想前往哪里？",
                    isInitialRequest: true
                )
            case .preferences:
                compactRequestComposer(
                    text: Binding(get: { model.adjustmentText }, set: { model.adjustmentText = $0 }),
                    placeholder: "补充人数、日期、预算或交通偏好",
                    isInitialRequest: false
                )
            case .discovering:
                HStack(spacing: 11) {
                    ProgressView().tint(AnyTravelPalette.route)
                    Text(model.activityTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal, 14)
                .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            case .ready:
                adjustmentComposer
            case .failure:
                HStack(spacing: 10) {
                    Label("这一段路暂时没有接上", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AnyTravelPalette.warm)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("重试") { Task { await model.retry() } }
                        .font(.caption.weight(.bold))
                        .frame(minHeight: 44)
                        .buttonStyle(AnyTravelPressStyle())
                }
                .padding(.horizontal, 13)
                .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
        }
    }

    private func compactRequestComposer(
        text: Binding<String>,
        placeholder: String,
        isInitialRequest: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(AnyTravelPalette.route)
            TextField(placeholder, text: text)
                .focused(isInitialRequest ? $destinationFocused : $adjustmentFocused)
                .submitLabel(.send)
                .onSubmit { submitCompactRequest(isInitialRequest: isInitialRequest) }
                .accessibilityIdentifier(isInitialRequest ? "compact-travel-request-input" : "compact-adjustment-input")

            Button {
                submitCompactRequest(isInitialRequest: isInitialRequest)
            } label: {
                Group {
                    if model.isAssistantResponding {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(AnyTravelPalette.route, in: Circle())
            }
            .buttonStyle(AnyTravelPressStyle())
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAssistantResponding)
            .opacity(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel(isInitialRequest ? "理解旅行愿望" : "应用旅行修改")
        }
        .padding(.leading, 13)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(AnyTravelPalette.route.opacity(0.24), lineWidth: 1)
        }
    }

    private func submitCompactRequest(isInitialRequest: Bool) {
        destinationFocused = false
        adjustmentFocused = false
        Task {
            if isInitialRequest {
                await model.submitTravelRequest()
            } else {
                await model.applyAdjustment()
            }
        }
    }

    private var destinationPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            handle
            VStack(alignment: .leading, spacing: 4) {
                Text("从地图出发")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AnyTravelPalette.route)
                Text("下一次旅行，你想前往哪里？")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("把想法随意写下来", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AnyTravelPalette.routeDark)
                ZStack(alignment: .topLeading) {
                    if model.travelRequestText.isEmpty {
                        Text("例如：从上海出发，两个人去苏州三天，想慢慢逛园林，住宿每晚不超过 600 元，优先高铁。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.travelRequestText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 82, maxHeight: 116)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(false)
                        .focused($destinationFocused)
                        .accessibilityLabel("自由描述旅行愿望")
                        .accessibilityIdentifier("travel-request-input")
                }
                HStack {
                    Text("智能向导会提取目的地、日期、预算、人数与交通偏好，并让地图回应。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !model.travelRequestText.isEmpty {
                        Button {
                            model.travelRequestText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AnyTravelPressStyle())
                        .accessibilityLabel("清空旅行愿望")
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(AnyTravelPalette.route.opacity(0.26), lineWidth: 1)
            }

            HStack(spacing: 8) {
                ForEach(["苏州", "杭州", "成都"], id: \.self) { city in
                    Button(city) {
                        model.travelRequestText = city
                        destinationFocused = false
                        Task { await model.submitTravelRequest() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(AnyTravelPressStyle())
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(AnyTravelPalette.route.opacity(0.10), in: Capsule())
                }
            }

            primaryButton(
                title: model.isAssistantResponding ? "正在听懂这段旅途" : "让地图读懂这段话",
                systemImage: model.isAssistantResponding ? "ellipsis.message" : "location.magnifyingglass"
            ) {
                destinationFocused = false
                Task { await model.submitTravelRequest() }
            }
            .disabled(!model.canSubmitTravelRequest || model.isAssistantResponding)
            .opacity(model.canSubmitTravelRequest ? 1 : 0.45)
        }
    }

    private var preferencesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            handle
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("地图已抵达 \(model.destination?.title ?? model.draft.destination)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AnyTravelPalette.route)
                    Text("再告诉我一点旅途偏好")
                        .font(.title2.bold())
                }
                Spacer()
                Button("改目的地") {
                    model.returnToEditing()
                    model.destination = nil
                    model.phase = .destination
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(AnyTravelPressStyle())
                .frame(minHeight: 44)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        compactStepper(
                            title: "天数",
                            valueText: "\(model.draft.dayCount)天",
                            decrementDisabled: model.draft.dayCount <= 1,
                            incrementDisabled: model.draft.dayCount >= 7,
                            decrement: { model.adjustDayCount(by: -1) },
                            increment: { model.adjustDayCount(by: 1) }
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

                    logisticsInputCard

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
                        .buttonStyle(AnyTravelPressStyle())
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
                        .buttonStyle(AnyTravelPressStyle())
                        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.hidden)

            primaryButton(title: "让旅程在地图上展开", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                Task { await model.requestPlan() }
            }
        }
    }

    private var logisticsInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("出发与落脚", systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AnyTravelPalette.routeDark)
                Spacer()
                Text("都可留白，路上再决定")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 9) {
                Image(systemName: "location.circle")
                    .foregroundStyle(AnyTravelPalette.route)
                TextField("常用出发地（可不填）", text: $model.draft.logistics.origin)
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            inlineCounter(
                title: "同行人数",
                symbol: "person.2.fill",
                valueText: "\(model.draft.logistics.travelers) 人",
                decrementLabel: "减少人数",
                incrementLabel: "增加人数",
                decrementDisabled: model.draft.logistics.travelers <= 1,
                incrementDisabled: model.draft.logistics.travelers >= 8,
                decrement: { model.draft.logistics.travelers = max(1, model.draft.logistics.travelers - 1) },
                increment: { model.draft.logistics.travelers = min(8, model.draft.logistics.travelers + 1) },
                valueIdentifier: "preferences-travelers-value"
            )

            if model.draft.logistics.hasDates,
               let startDate = model.draft.logistics.startDate,
               let endDate = model.draft.logistics.endDate {
                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Label("出发", systemImage: "sunrise.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AnyTravelPalette.routeDark)
                            .frame(width: 58, alignment: .leading)
                        Spacer(minLength: 2)
                        dateShiftButton(symbol: "minus", label: "出发日提前一天", disabled: Calendar.current.isDate(startDate, inSameDayAs: .now)) {
                            model.adjustStartDate(by: -1)
                        }
                        DatePicker(
                            "出发",
                            selection: Binding(get: { startDate }, set: model.updateStartDate),
                            in: Calendar.current.startOfDay(for: .now)...,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("preferences-start-date")
                        dateShiftButton(symbol: "plus", label: "出发日推后一天") {
                            model.adjustStartDate(by: 1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 54)
                    .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack(spacing: 5) {
                        Label("返程", systemImage: "sunset.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AnyTravelPalette.routeDark)
                            .frame(width: 58, alignment: .leading)
                        Spacer(minLength: 2)
                        dateShiftButton(
                            symbol: "minus",
                            label: "返程日提前一天",
                            disabled: (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1) <= 1
                        ) {
                            model.adjustEndDate(by: -1)
                        }
                        DatePicker(
                            "返程",
                            selection: Binding(get: { endDate }, set: model.updateEndDate),
                            in: (Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate)...(Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? endDate),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("preferences-end-date")
                        dateShiftButton(
                            symbol: "plus",
                            label: "返程日推后一天",
                            disabled: (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1) >= 6
                        ) {
                            model.adjustEndDate(by: 1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 54)
                    .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack {
                        Text("共 \(model.draft.dayCount) 天；日期左右的 − / + 都可用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清除") { model.setDatesEnabled(false) }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
            } else {
                Button {
                    model.setDatesEnabled(true)
                } label: {
                    Label("添上日期，听见当天的价格", systemImage: "calendar.badge.plus")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(AnyTravelPressStyle())
                .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    modePreferenceChip(nil, title: "让地图推荐", symbol: "wand.and.stars")
                    ForEach(LongDistanceMode.allCases) { mode in
                        modePreferenceChip(mode, title: mode.shortTitle, symbol: mode.symbolName)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 14) {
                Toggle("住处稍后再定", isOn: $model.draft.logistics.skipAccommodation)
                Toggle("大交通稍后再定", isOn: $model.draft.logistics.skipTransport)
            }
            .font(.caption)
            .toggleStyle(.switch)
        }
        .padding(12)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
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
            .buttonStyle(AnyTravelPressStyle())
        }
    }

    private var failurePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            handle
            Label("这一段路暂时没有接上", systemImage: "exclamationmark.triangle.fill")
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
                .buttonStyle(AnyTravelPressStyle())
                .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("重试") {
                    Task { await model.retry() }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .buttonStyle(AnyTravelPressStyle())
                .background(AnyTravelPalette.route, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .fontWeight(.semibold)
        }
    }

    private var readyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            handle

            planSectionTabs

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(readySectionTitle)
                        .font(.title3.bold())
                        .contentTransition(.opacity)
                    Text(readySectionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }
                Spacer()
                Menu {
                    Button {
                        model.beginItineraryEditing()
                    } label: {
                        Label("增删与调整路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    Button {
                        model.conditionsEditorPresented = true
                    } label: {
                        Label("修改日期与出发条件", systemImage: "calendar.badge.clock")
                    }
                } label: {
                    Label("调整", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(AnyTravelPressStyle())

                Menu {
                    Button {
                        model.exportCurrentPlan(.pdf)
                    } label: {
                        Label("分享完整 PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        model.exportCurrentPlan(.calendar)
                    } label: {
                        Label("导出日历文件", systemImage: "calendar.badge.plus")
                    }
                    .disabled(!model.canExportCalendar)
                    Button {
                        model.exportCurrentPlan(.pdfAndCalendar)
                    } label: {
                        Label("PDF 与日历一起带走", systemImage: "square.and.arrow.up.on.square")
                    }
                    .disabled(!model.canExportCalendar)
                } label: {
                    Group {
                        if model.isExportingPlan {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AnyTravelPressStyle())
                .disabled(model.isExportingPlan)
                .accessibilityLabel(model.isExportingPlan ? "正在导出行程" : "导出与分享")
                .accessibilityIdentifier("plan-export-menu")

                Button {
                    model.saveCurrentTrip()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(AnyTravelPressStyle())
            }

            if let exportStatusMessage = model.exportStatusMessage {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(exportStatusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Group {
                switch model.planMapFocus {
                case .itinerary:
                    itineraryReadyContent
                case .accommodation:
                    accommodationReadyContent
                case .transport:
                    transportReadyContent
                case .budget:
                    budgetReadyContent
                }
            }
            .id(model.planMapFocus)
            .transition(AnyTravelMotion.contentTransition(reduceMotion: reduceMotion))

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

            if readyExpanded {
                Text("地图给出方向，价格留下来路：地点与路线来自 Apple Maps；每条报价都标注渠道、口径与抓取时间。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.planMapFocus)
    }

    private var planSectionTabs: some View {
        HStack(spacing: 6) {
            ForEach(PlanMapFocus.allCases) { section in
                let selected = model.planMapFocus == section
                Button {
                    model.setPlanMapFocus(section)
                    if section == .transport {
                        model.setTransportDirectionFocus(selectedTransportDirection)
                    }
                } label: {
                    Label(section.title, systemImage: section.symbolName)
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
                        .contentTransition(.symbolEffect(.replace))
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(AnyTravelPalette.softSurface)
                                if selected {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(AnyTravelPalette.route)
                                        .matchedGeometryEffect(id: "plan-section", in: sectionMotion)
                                }
                            }
                        }
                }
                .buttonStyle(AnyTravelPressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.planMapFocus)
    }

    private var readySectionTitle: String {
        let destination = model.destination?.title ?? model.draft.destination
        return switch model.planMapFocus {
        case .itinerary: "\(destination) · \(model.currentDay?.title ?? "行程")"
        case .accommodation: "住宿比价 · \(model.filteredAccommodations.count)/\(model.accommodations.count)家"
        case .transport: "\(selectedTransportDirection.title)方式 · \(activeTransportSelection?.mode.shortTitle ?? "待选择")"
        case .budget: "完整费用 · \(model.draft.logistics.travelers)人"
        }
    }

    private var activeTransportSelection: TransportOption? {
        selectedTransportDirection == .outbound
            ? model.selectedTransport
            : model.selectedReturnTransport
    }

    private var activeTransferOptions: [LocalTransferOption] {
        selectedTransportDirection == .outbound
            ? model.outboundTransferOptions
            : model.returnTransferOptions
    }

    private var activeTransferSelection: LocalTransferOption? {
        selectedTransportDirection == .outbound
            ? model.selectedOutboundTransfer
            : model.selectedReturnTransfer
    }

    private var readySectionSubtitle: String {
        switch model.planMapFocus {
        case .itinerary:
            model.routeSummary ?? (model.isRouteLoading ? "路线正沿着地图醒来…" : "默认把脚步放慢，想改随时说")
        case .accommodation:
            model.selectedAccommodation.map { "已选\($0.name) · 到景点平均\($0.attractionDistanceMeters.anyTravelDistanceText)" }
                ?? (model.isLogisticsLoading ? "正在地图上查找真实住宿" : "按景点分布与枢纽距离排序")
        case .transport:
            activeTransportSelection.map { option in
                option.durationMinutes.map {
                    let quoteState = option.quotes.contains(where: { $0.kind == .live })
                        ? "班次与票价已更新"
                        : "等待实时报价"
                    return "\(transportDurationText($0)) · \(quoteState)"
                }
                    ?? "补充出发地和日期后比较班次与价格"
            } ?? "补充条件后自动推荐，也可以先指定方式"
        case .budget:
            "计划¥\(model.plannedExpenseTotal.formatted(.number.grouping(.automatic))) / 预算¥\(model.totalBudget.formatted(.number.grouping(.automatic)))"
        }
    }

    private var itineraryReadyContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let paceStatusMessage = model.paceStatusMessage {
                pacingSuccessCard(paceStatusMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            if model.planPacingAssessment.needsAttention {
                pacingAdvisoryCard(model.planPacingAssessment)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            if let assessment = model.currentDayTourismAssessment {
                planningRationaleCard(assessment)
                    .id(model.selectedDayIndex)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(model.itineraryDays) { day in
                        let selected = model.selectedDayIndex == day.index
                        Button(day.title) { model.selectDay(day.index) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .background {
                                ZStack {
                                    Capsule().fill(AnyTravelPalette.softSurface)
                                    if selected {
                                        Capsule()
                                            .fill(AnyTravelPalette.routeColor(for: day.index))
                                            .matchedGeometryEffect(id: "selected-day", in: dayMotion)
                                    }
                                }
                            }
                            .buttonStyle(AnyTravelPressStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.selectedDayIndex)

            if let selectedPlace = model.selectedPlace {
                selectedPlaceCard(selectedPlace)
            } else if readyExpanded {
                itineraryTimeline
            } else {
                compactStopsStrip
            }

            if let assistantReply = model.assistantReply {
                assistantReplyCard(assistantReply)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            adjustmentComposer
        }
        .animation(AnyTravelMotion.settle(reduceMotion: reduceMotion), value: model.planPacingAssessment.level)
        .animation(AnyTravelMotion.settle(reduceMotion: reduceMotion), value: model.assistantReply)
    }

    private var adjustmentComposer: some View {
        HStack(spacing: 8) {
            TextField(
                "说出想改变的脚步、预算或地图焦点",
                text: Binding(get: { model.adjustmentText }, set: { model.adjustmentText = $0 })
            )
            .focused($adjustmentFocused)
            .submitLabel(.send)
            .onSubmit {
                adjustmentFocused = false
                Task { await model.applyAdjustment() }
            }
            .accessibilityIdentifier("route-adjustment-input")

            Button {
                adjustmentFocused = false
                Task { await model.applyAdjustment() }
            } label: {
                Group {
                    if model.isAssistantResponding {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(AnyTravelPalette.route, in: Circle())
            }
            .buttonStyle(AnyTravelPressStyle())
            .disabled(model.adjustmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAssistantResponding)
            .opacity(model.adjustmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("应用路线修改")
        }
        .padding(.leading, 13)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AnyTravelPalette.route.opacity(0.18), lineWidth: 1)
        }
    }

    private func assistantReplyCard(_ reply: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .foregroundStyle(AnyTravelPalette.route)
                .symbolEffect(.variableColor.iterative, value: model.assistantFeedbackTrigger)
            Text(reply)
                .font(.caption)
                .foregroundStyle(AnyTravelPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AnyTravelPalette.route.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistant-reply")
    }

    private func pacingSuccessCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(AnyTravelPalette.route)
                .symbolEffect(.bounce, value: model.paceFeedbackTrigger)
            VStack(alignment: .leading, spacing: 3) {
                Text("脚步已经慢下来")
                    .font(.subheadline.weight(.bold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(AnyTravelPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AnyTravelPalette.route.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(AnyTravelPalette.route.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("relaxed-plan-success")
    }

    private func pacingAdvisoryCard(_ assessment: PlanPacingAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: assessment.level == .rushed ? "wind" : "clock.badge.exclamationmark")
                    .foregroundStyle(assessment.level == .rushed ? AnyTravelPalette.warm : AnyTravelPalette.route)
                Text(assessment.title)
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 4)
                if assessment.suggestedDayCount > model.itineraryDays.count {
                    Text("建议 \(assessment.suggestedDayCount) 天")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AnyTravelPalette.routeDark)
                }
            }

            Text(assessment.detail)
                .font(.caption2)
                .foregroundStyle(AnyTravelPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.relaxCurrentPlan()
            } label: {
                Label("让行程松一口气", systemImage: "leaf.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(AnyTravelPalette.route, in: Capsule())
            }
            .buttonStyle(AnyTravelPressStyle())
            .accessibilityIdentifier("relax-plan-action")
        }
        .padding(12)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(AnyTravelPalette.route.opacity(0.16), lineWidth: 1)
        }
    }

    private func planningRationaleCard(_ assessment: TourismDayAssessment) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: assessment.isOverCapacity
                      ? "hourglass.badge.plus"
                      : "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(assessment.isOverCapacity ? AnyTravelPalette.warm : AnyTravelPalette.route)
                    .symbolEffect(.bounce, value: model.selectedDayIndex)
                Text(assessment.title)
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
            }

            Text(assessment.detail)
                .font(.caption2)
                .foregroundStyle(AnyTravelPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(assessment.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AnyTravelPalette.routeDark)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 28)
                            .background(AnyTravelPalette.route.opacity(0.09), in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(AnyTravelPalette.route.opacity(0.16), lineWidth: 1)
        }
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.selectedDayIndex)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planning-rationale")
    }

    private var itineraryTimeline: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.currentSchedule) { item in
                    Button {
                        guard let placeID = item.placeID,
                              let place = model.currentStops.first(where: { $0.id == placeID }) else { return }
                        model.selectPlace(place)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.timeText)
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(AnyTravelPalette.routeDark)
                                .frame(width: 78, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AnyTravelPressStyle())
                }
            }
        }
        .frame(maxHeight: 238)
        .scrollIndicators(.hidden)
    }

    private var accommodationReadyContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.draft.logistics.skipAccommodation {
                skippedModule(title: "已跳过住宿", detail: "仍会保留路线与交通方案，返回条件页即可补上住宿。", symbol: "bed.double")
            } else if model.isLogisticsLoading && model.accommodations.isEmpty {
                loadingModule("正沿着景点的分布，寻找今晚的窗与灯")
            } else if model.accommodations.isEmpty {
                emptyLogisticsModule(title: "暂时没有住宿结果", actionTitle: "重新查找")
                quoteRefreshBanner
            } else {
                accommodationFilterBar

                if model.filteredAccommodations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(AnyTravelPalette.route)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("这些条件下还没有合适住处")
                                .font(.subheadline.weight(.semibold))
                            Text("放宽一项筛选，更多窗灯会重新回到地图上。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("清除") { resetAccommodationFilters() }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                            .buttonStyle(AnyTravelPressStyle())
                    }
                    .padding(11)
                    .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(model.filteredAccommodations) { option in
                                accommodationCard(option)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                }

                quoteRefreshBanner

                if let selected = model.selectedAccommodation {
                    quoteStrip(selected.quotes)
                }
            }
        }
    }

    private var accommodationFilterBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("显示 \(model.filteredAccommodations.count) / \(model.accommodations.count) 家")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AnyTravelPalette.secondaryInk)
                Spacer()
                if model.activeAccommodationFilterCount > 0 {
                    Button("清除 \(model.activeAccommodationFilterCount) 项") { resetAccommodationFilters() }
                        .font(.caption2.weight(.semibold))
                        .frame(minHeight: 44)
                        .buttonStyle(AnyTravelPressStyle())
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    Menu {
                        ForEach(AccommodationSort.allCases) { sort in
                            Button {
                                model.accommodationSort = sort
                            } label: {
                                if model.accommodationSort == sort {
                                    Label(sort.title, systemImage: "checkmark")
                                } else {
                                    Text(sort.title)
                                }
                            }
                        }
                    } label: {
                        filterChipLabel(title: model.accommodationSort.shortTitle, symbol: "arrow.up.arrow.down", selected: model.accommodationSort != .recommended)
                    }

                    Menu {
                        Button("不限每晚价格") { model.accommodationMaxNightlyPrice = nil }
                        ForEach([400, 600, 800, 1_200], id: \.self) { amount in
                            Button("每晚不超过 ¥\(amount)") { model.accommodationMaxNightlyPrice = amount }
                        }
                    } label: {
                        filterChipLabel(
                            title: model.accommodationMaxNightlyPrice.map { "≤¥\($0)/晚" } ?? "价格",
                            symbol: "yensign",
                            selected: model.accommodationMaxNightlyPrice != nil
                        )
                    }

                    Menu {
                        Button("不限景点距离") { model.accommodationMaxAttractionDistanceMeters = nil }
                        Button("平均 2 公里内") { model.accommodationMaxAttractionDistanceMeters = 2_000 }
                        Button("平均 5 公里内") { model.accommodationMaxAttractionDistanceMeters = 5_000 }
                        Button("平均 10 公里内") { model.accommodationMaxAttractionDistanceMeters = 10_000 }
                    } label: {
                        filterChipLabel(
                            title: model.accommodationMaxAttractionDistanceMeters.map { "景点≤\($0.anyTravelDistanceText)" } ?? "景点距离",
                            symbol: "scope",
                            selected: model.accommodationMaxAttractionDistanceMeters != nil
                        )
                    }

                    Button {
                        model.accommodationLivePricesOnly.toggle()
                    } label: {
                        filterChipLabel(title: "有实时价", symbol: "bolt.fill", selected: model.accommodationLivePricesOnly)
                    }
                    .buttonStyle(AnyTravelPressStyle())

                    Button {
                        model.accommodationOfficialSiteOnly.toggle()
                    } label: {
                        filterChipLabel(title: "有官网", symbol: "building.2.crop.circle", selected: model.accommodationOfficialSiteOnly)
                    }
                    .buttonStyle(AnyTravelPressStyle())
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func filterChipLabel(title: String, symbol: String, selected: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
            .background(selected ? AnyTravelPalette.route : AnyTravelPalette.elevatedSurface, in: Capsule())
    }

    private func resetAccommodationFilters() {
        model.accommodationSort = .recommended
        model.accommodationMaxNightlyPrice = nil
        model.accommodationMaxAttractionDistanceMeters = nil
        model.accommodationLivePricesOnly = false
        model.accommodationOfficialSiteOnly = false
    }

    private var transportReadyContent: some View {
        let options = selectedTransportDirection == .outbound
            ? model.transportOptions
            : model.returnTransportOptions
        let selectedOption = selectedTransportDirection == .outbound
            ? model.selectedTransport
            : model.selectedReturnTransport

        return VStack(alignment: .leading, spacing: 9) {
            if model.draft.logistics.skipTransport {
                skippedModule(title: "已跳过大交通", detail: "景点与住宿仍可继续规划，之后补出发地即可重算。", symbol: "tram")
            } else if model.isLogisticsLoading && model.transportOptions.isEmpty && model.returnTransportOptions.isEmpty {
                loadingModule("正在比较每一种抵达远方的方式")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        if model.draft.logistics.endDate != nil || !model.returnTransportOptions.isEmpty {
                            Picker("选择去程或返程", selection: $selectedTransportDirection) {
                                Text("去程").tag(TransportDirection.outbound)
                                Text("返程").tag(TransportDirection.returnTrip)
                            }
                            .pickerStyle(.segmented)
                            .tint(AnyTravelPalette.route)
                            .accessibilityIdentifier("transport-direction-picker")
                        }

                        if options.isEmpty {
                            let title = selectedTransportDirection == .returnTrip ? "返程班次暂未抵达" : "暂时没有交通结果"
                            let detail = selectedTransportDirection == .returnTrip
                                ? "保留当前去程；刷新后会继续查询返程当天的班次与票价。"
                                : "补充出发地与日期，或稍后重新查询。"
                            HStack(spacing: 10) {
                                Image(systemName: selectedTransportDirection == .returnTrip ? "arrow.uturn.backward.circle" : "tram")
                                    .foregroundStyle(AnyTravelPalette.route)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).font(.subheadline.weight(.semibold))
                                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(options) { option in
                                        transportCard(option)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollIndicators(.hidden)
                            .scrollTargetBehavior(.viewAligned)
                        }
                        localTransferSection
                        quoteRefreshBanner
                        if let selectedOption {
                            quoteStrip(selectedOption.quotes)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: readyExpanded ? 410 : 300)
                .scrollIndicators(.hidden)
            }
        }
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: selectedTransportDirection)
        .onChange(of: selectedTransportDirection) { _, direction in
            model.setTransportDirectionFocus(direction)
        }
        .onChange(of: model.returnTransportOptions.isEmpty) { _, returnIsEmpty in
            if returnIsEmpty && selectedTransportDirection == .returnTrip {
                selectedTransportDirection = .outbound
            }
        }
    }

    private var localTransferSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(
                    selectedTransportDirection == .outbound ? "抵达接驳" : "返程接驳",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(AnyTravelPalette.routeDark)
                Spacer()
                if model.isTransferLoading {
                    ProgressView().controlSize(.small)
                    Text("正在丈量")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        model.refreshLocalTransfersInBackground()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(AnyTravelPressStyle())
                    .accessibilityLabel("重新查询接驳路线")
                }
            }

            if activeTransferOptions.isEmpty {
                Text(model.transferStatusMessage ?? "选定车站与住宿后，会比较地铁公交、打车和步行。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(activeTransferOptions) { option in
                            localTransferCard(option)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }

            if let status = model.transferStatusMessage, !activeTransferOptions.isEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.isTransferLoading)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: activeTransferSelection?.id)
    }

    private var budgetReadyContent: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(model.expenseLines) { line in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.title).font(.subheadline.weight(.semibold))
                            Text("\(line.detail) · \(line.source.title)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text("¥\(line.amountCNY.formatted(.number.grouping(.automatic)))")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                    }
                    .padding(10)
                    .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(maxHeight: 260)
        .scrollIndicators(.hidden)
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
                        .frame(minHeight: 44)
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
                    .buttonStyle(AnyTravelPressStyle())

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
                .buttonStyle(AnyTravelPressStyle())
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
                .buttonStyle(AnyTravelPressStyle())
                .foregroundStyle(AnyTravelPalette.route)
            }

            if let quote = place.ticketQuote {
                Divider()
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "ticket.fill")
                        .foregroundStyle(AnyTravelPalette.warm)
                        .frame(width: 30, height: 30)
                        .background(AnyTravelPalette.warm.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(quote.provider.title) · \(quote.priceText)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text([quote.kind.title, quote.freshnessText].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if let bookingURL = quote.bookingURL {
                        Link(destination: bookingURL) {
                            Label("查看", systemImage: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .frame(minHeight: 44)
                        }
                        .foregroundStyle(AnyTravelPalette.route)
                        .accessibilityLabel("到\(quote.provider.title)查看\(place.name)门票")
                    }
                }
                Text(quote.note)
                    .font(.caption2)
                    .foregroundStyle(AnyTravelPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func accommodationCard(_ option: AccommodationOption) -> some View {
        let selected = model.selectedAccommodationID == option.id
        let pricedQuote = option.bestPricedQuote
        let channelCount = Set(option.quotes.filter { $0.amountCNY != nil }.map(\.provider)).count
        return Button {
            model.selectAccommodation(option)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Image(systemName: "bed.double.fill")
                        .foregroundStyle(selected ? .white : AnyTravelPalette.route)
                        .frame(width: 30, height: 30)
                        .background(selected ? AnyTravelPalette.route : AnyTravelPalette.route.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(option.address)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 6) {
                    if let brand = option.brand, !brand.isEmpty {
                        Label(brand, systemImage: "building.2")
                    }
                    if let starRating = option.starRating, starRating > 0 {
                        Label("\(starRating.formatted(.number.precision(.fractionLength(0...1))))星", systemImage: "star.fill")
                    }
                    if let guestRating = option.guestRating, guestRating > 0 {
                        Label(guestRating.formatted(.number.precision(.fractionLength(1))), systemImage: "hand.thumbsup.fill")
                    }
                    if option.officialWebsiteURL != nil {
                        Label("官网", systemImage: "checkmark.seal.fill")
                    }
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AnyTravelPalette.routeDark)
                .lineLimit(1)

                Text(option.recommendationReasons.prefix(2).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(AnyTravelPalette.secondaryInk)
                    .lineLimit(2)

                HStack {
                    Text(pricedQuote?.priceText ?? "多渠道正在核价")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(pricedQuote == nil ? AnyTravelPalette.routeDark : AnyTravelPalette.warm)
                    Spacer()
                    if let pricedQuote {
                        Text("\(pricedQuote.provider.title) · \(pricedQuote.kind.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if channelCount > 1 {
                        Text("\(channelCount)家比价")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AnyTravelPalette.routeDark)
                    }
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AnyTravelPalette.route : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(11)
            .frame(width: 278, alignment: .leading)
            .frame(minHeight: 136)
            .scaleEffect(selected && !reduceMotion ? 1 : 0.975)
            .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(selected ? AnyTravelPalette.route : .clear, lineWidth: 2)
            }
            .shadow(color: selected ? AnyTravelPalette.route.opacity(0.16) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityLabel(
            [
                option.name,
                pricedQuote?.priceText ?? "等待报价",
                pricedQuote.map { "\($0.provider.title)，\($0.kind.title)" }
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: selected)
    }

    private func transportCard(_ option: TransportOption) -> some View {
        let selected = option.journeyDirection == .returnTrip
            ? model.selectedReturnTransportID == option.id
            : model.selectedTransportID == option.id
        let duration = option.durationMinutes.map(transportDurationText) ?? "耗时待比较"
        let pricedQuote = option.quotes
            .filter(\.isCurrentPrice)
            .min { ($0.amountCNY ?? .max) < ($1.amountCNY ?? .max) }
        return Button {
            model.selectTransport(option)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: option.mode.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(option.isRecommended ? AnyTravelPalette.warm : AnyTravelPalette.route, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        Text(duration).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if option.isRecommended {
                        Text("推荐")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AnyTravelPalette.warm)
                    }
                }

                Text(option.recommendationReasons.prefix(2).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(AnyTravelPalette.secondaryInk)
                    .lineLimit(2)

                HStack {
                    if let pricedQuote {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pricedQuote.priceText)
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(AnyTravelPalette.warm)
                            Text(
                                [pricedQuote.provider.title, pricedQuote.freshnessText]
                                    .compactMap { $0 }
                                    .joined(separator: " · ")
                            )
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(pricedQuote.isStale ? AnyTravelPalette.warm : .secondary)
                        }
                    } else {
                        Text("班次与价格待核")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AnyTravelPalette.routeDark)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AnyTravelPalette.route : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(11)
            .frame(width: 265, alignment: .leading)
            .frame(minHeight: 132)
            .scaleEffect(selected && !reduceMotion ? 1 : 0.975)
            .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(selected ? AnyTravelPalette.route : .clear, lineWidth: 2)
            }
            .shadow(color: selected ? AnyTravelPalette.route.opacity(0.16) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityIdentifier("transport-option-\(option.journeyDirection.rawValue)-\(option.id.uuidString)")
        .accessibilityLabel(
            [
                option.title,
                pricedQuote?.priceText ?? "等待报价",
                pricedQuote.map { "\($0.provider.title)，\($0.kind.title)" }
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: selected)
    }

    private func localTransferCard(_ option: LocalTransferOption) -> some View {
        let selected = option.direction == .outbound
            ? model.selectedOutboundTransferID == option.id
            : model.selectedReturnTransferID == option.id
        let cost = option.estimatedCostCNY == 0 ? "无需费用" : "约¥\(option.estimatedCostCNY)"
        return Button {
            model.selectLocalTransfer(option)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: option.mode.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selected ? .white : AnyTravelPalette.route)
                        .frame(width: 28, height: 28)
                        .background(selected ? AnyTravelPalette.route : AnyTravelPalette.route.opacity(0.10), in: Circle())
                    Text(option.mode.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 2)
                    if option.isRecommended {
                        Text("推荐")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AnyTravelPalette.warm)
                    }
                }
                Text("\(transportDurationText(option.durationMinutes)) · \(option.distanceMeters.anyTravelDistanceText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Text(cost)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(option.estimatedCostCNY == 0 ? AnyTravelPalette.routeDark : AnyTravelPalette.warm)
                    Spacer()
                    Text(option.routeKind.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(option.routeKind == .distanceEstimate ? AnyTravelPalette.warm : .secondary)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AnyTravelPalette.route : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(9)
            .frame(width: 178, alignment: .leading)
            .frame(minHeight: 92, alignment: .leading)
            .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(selected ? AnyTravelPalette.route : .clear, lineWidth: 1.8)
            }
            .scaleEffect(selected && !reduceMotion ? 1 : 0.98)
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityIdentifier("local-transfer-\(option.direction.rawValue)-\(option.mode.rawValue)")
        .accessibilityLabel("\(option.direction.title)接驳，\(option.mode.title)，\(transportDurationText(option.durationMinutes))，\(cost)，\(option.routeKind.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: selected)
    }

    private func transportDurationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "约\(minutes)分钟" }
        let remainder = minutes % 60
        return remainder == 0
            ? "约\(minutes / 60)小时"
            : "约\(minutes / 60)小时\(remainder)分钟"
    }

    private func quoteStrip(_ quotes: [ProviderQuote]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(quotes) { quote in
                    Button {
                        model.openQuote(quote)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(quote.provider.title).font(.caption2.weight(.semibold))
                                if let sourceLabel = quote.sourceLabel, !sourceLabel.isEmpty {
                                    Text("· \(sourceLabel)")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Image(systemName: quote.bookingURL == nil ? "clock" : "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Text(quote.priceText)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(quote.amountCNY == nil ? AnyTravelPalette.routeDark : AnyTravelPalette.warm)
                            if let roomName = quote.roomName, !roomName.isEmpty {
                                Text(roomName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(AnyTravelPalette.secondaryInk)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 3) {
                                Text(quote.kind.title)
                                if let freshnessText = quote.freshnessText {
                                    Text("·")
                                    Text(freshnessText)
                                        .foregroundStyle(quote.isStale ? AnyTravelPalette.warm : .secondary)
                                }
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 118, minHeight: 58, alignment: .leading)
                        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(AnyTravelPressStyle())
                    .accessibilityHint(quote.note)
                }

                Button {
                    model.handleQuoteRefreshAction()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        RefreshPriceIcon(isLoading: model.isLogisticsLoading)
                        Text("刷新此刻价格")
                            .font(.caption2.weight(.semibold))
                        Text(model.draft.logistics.hasDates ? "按当前日期" : "请先添上日期")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(AnyTravelPalette.routeDark)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 112, minHeight: 58, alignment: .leading)
                    .background(AnyTravelPalette.route.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(AnyTravelPressStyle())
                .disabled(model.isLogisticsLoading)
                .opacity(model.isLogisticsLoading ? 0.55 : 1)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var quoteRefreshBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(quoteStatusColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                if model.quoteRefreshState == .refreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(quoteStatusColor)
                } else {
                    Image(systemName: model.quoteRefreshState.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(quoteStatusColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.quoteRefreshState.title)
                    .font(.caption.weight(.bold))
                Text(model.quoteRefreshState.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if let actionTitle = model.quoteRefreshState.actionTitle {
                Button(actionTitle) {
                    model.handleQuoteRefreshAction()
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(quoteStatusColor)
                .frame(minWidth: 52, minHeight: 44)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 58)
        .background(quoteStatusColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(quoteStatusColor.opacity(0.12), lineWidth: 1)
        }
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.quoteRefreshState)
    }

    private var quoteStatusColor: Color {
        switch model.quoteRefreshState {
        case .updated:
            AnyTravelPalette.route
        case .partial, .noResults, .failed:
            AnyTravelPalette.warm
        case .idle, .needsDates, .needsService, .stale, .refreshing:
            AnyTravelPalette.routeDark
        }
    }

    private func skippedModule(title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(AnyTravelPalette.route)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadingModule(_ title: String) -> some View {
        HStack(spacing: 11) {
            TravelLoadingGlyph()
            Text(title).font(.subheadline.weight(.medium))
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyLogisticsModule(title: String, actionTitle: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Button(actionTitle) { model.refreshLogisticsInBackground() }
                .font(.caption.weight(.bold))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 68)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func modePreferenceChip(
        _ mode: LongDistanceMode?,
        title: String,
        symbol: String
    ) -> some View {
        let selected = model.draft.logistics.preferredLongDistanceMode == mode
        return Button {
            model.draft.logistics.preferredLongDistanceMode = mode
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
                .background(selected ? AnyTravelPalette.route : AnyTravelPalette.elevatedSurface, in: Capsule())
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(decrementDisabled)
                .accessibilityLabel("减少\(title)")
                Text(valueText)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button(action: increment) {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(incrementDisabled)
                .accessibilityLabel("增加\(title)")
            }
            .buttonStyle(AnyTravelPressStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func inlineCounter(
        title: String,
        symbol: String,
        valueText: String,
        decrementLabel: String,
        incrementLabel: String,
        decrementDisabled: Bool,
        incrementDisabled: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        valueIdentifier: String
    ) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AnyTravelPalette.routeDark)
            Spacer(minLength: 6)
            dateShiftButton(
                symbol: "minus",
                label: decrementLabel,
                disabled: decrementDisabled,
                action: decrement
            )
            Text(valueText)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 54)
                .contentTransition(.numericText())
                .accessibilityIdentifier(valueIdentifier)
            dateShiftButton(
                symbol: "plus",
                label: incrementLabel,
                disabled: incrementDisabled,
                action: increment
            )
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(AnyTravelPalette.inputSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func dateShiftButton(
        symbol: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(AnyTravelPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.30 : 1)
        .accessibilityLabel(label)
    }

    private func activityStep(_ title: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(active ? AnyTravelPalette.route : Color.secondary.opacity(0.25))
                .frame(width: 7, height: 7)
                .scaleEffect(active && !reduceMotion ? 1.30 : 1)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(active ? AnyTravelPalette.routeDark : .secondary)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(AnyTravelPalette.softSurface, in: Capsule())
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: active)
    }
}

private struct RefreshPriceIcon: View {
    let isLoading: Bool

    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: isLoading ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
            .font(.caption.weight(.bold))
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
        withAnimation(.linear(duration: 0.84).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

struct TravelLoadingGlyph: View {
    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(AnyTravelPalette.route.opacity(0.16), lineWidth: 3)
            Circle()
                .trim(from: 0.08, to: 0.43)
                .stroke(AnyTravelPalette.route, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 24, height: 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.90).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .accessibilityHidden(true)
    }
}

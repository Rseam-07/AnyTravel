import SwiftUI

struct TripConditionsView: View {
    @Bindable var model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var originalDraft: TripDraft?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：上海", text: $model.draft.logistics.origin)
                        .textInputAutocapitalization(.never)
                    Stepper(
                        "同行人数：\(model.draft.logistics.effectiveTotalTravelers)人",
                        value: Binding(
                            get: { model.draft.logistics.effectiveTotalTravelers },
                            set: model.setTotalTravelerCount
                        ),
                        in: 1...8
                    )
                    Stepper(
                        "人均预算：¥\(model.draft.budgetPerPerson.formatted(.number.grouping(.automatic)))",
                        value: $model.draft.budgetPerPerson,
                        in: 1_000...30_000,
                        step: 500
                    )
                    Stepper(
                        "旅行天数：\(model.draft.dayCount)天",
                        value: Binding(
                            get: { model.draft.dayCount },
                            set: { model.adjustDayCount(by: $0 - model.draft.dayCount) }
                        ),
                        in: 1...7
                    )
                    .accessibilityIdentifier("trip-conditions-day-count")
                } header: {
                    Text("从哪里出发，和谁同行")
                }

                Section {
                    Stepper(
                        "成人：\(model.draft.logistics.effectiveAdults)人",
                        value: Binding(
                            get: { model.draft.logistics.effectiveAdults },
                            set: model.setAdultCount
                        ),
                        in: 1...8
                    )
                    ForEach(Array(model.draft.logistics.effectiveChildrenAges.enumerated()), id: \.offset) { index, age in
                        HStack {
                            Stepper(
                                "儿童 \(index + 1)：\(age)岁",
                                value: Binding(
                                    get: { age },
                                    set: { model.setChildAge(at: index, age: $0) }
                                ),
                                in: 0...17
                            )
                            Button {
                                model.removeChild(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .accessibilityLabel("删除第\(index + 1)名儿童")
                        }
                    }
                    Button {
                        model.addChild()
                    } label: {
                        Label("添加儿童年龄", systemImage: "plus.circle")
                    }
                    .disabled(model.draft.logistics.effectiveChildrenAges.count >= 6)
                    Stepper(
                        "房间：\(model.draft.logistics.effectiveRooms)间",
                        value: Binding(
                            get: { model.draft.logistics.effectiveRooms },
                            set: model.setRoomCount
                        ),
                        in: 1...4
                    )
                    Stepper(
                        "老人：\(model.draft.logistics.effectiveSeniorTravelers)人",
                        value: Binding(
                            get: { model.draft.logistics.effectiveSeniorTravelers },
                            set: model.setSeniorTravelerCount
                        ),
                        in: 0...max(model.draft.logistics.effectiveAdults, 1)
                    )
                    Picker("步行与无障碍偏好", selection: Binding(
                        get: { model.draft.logistics.mobilityNeed ?? .none },
                        set: model.setMobilityNeed
                    )) {
                        ForEach(MobilityNeed.allCases) { need in
                            Text(need.title).tag(need)
                        }
                    }
                } header: {
                    Text("成人、儿童与房间")
                } footer: {
                    Text("儿童年龄会发送给支持该字段的住宿渠道；儿童票与无障碍设施仍需在购买前复核。")
                }

                Section {
                    Toggle(
                        "按具体日期查询",
                        isOn: Binding(
                            get: { model.draft.logistics.hasDates },
                            set: model.setDatesEnabled
                        )
                    )

                    if let startDate = model.draft.logistics.startDate,
                       let endDate = model.draft.logistics.endDate {
                        DatePicker(
                            "抵达日",
                            selection: Binding(get: { startDate }, set: model.updateStartDate),
                            in: Calendar.current.startOfDay(for: .now)...,
                            displayedComponents: .date
                        )
                        dateAdjustmentRow(
                            title: "抵达日",
                            value: startDate.formatted(date: .abbreviated, time: .omitted),
                            decrementDisabled: Calendar.current.isDate(startDate, inSameDayAs: .now),
                            decrement: { model.adjustStartDate(by: -1) },
                            increment: { model.adjustStartDate(by: 1) }
                        )
                        DatePicker(
                            "返程日",
                            selection: Binding(get: { endDate }, set: model.updateEndDate),
                            in: (Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate)...(Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? endDate),
                            displayedComponents: .date
                        )
                        dateAdjustmentRow(
                            title: "返程日",
                            value: endDate.formatted(date: .abbreviated, time: .omitted),
                            decrementDisabled: Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1 <= 1,
                            decrement: { model.adjustEndDate(by: -1) },
                            increment: { model.adjustEndDate(by: 1) }
                        )
                    }
                } header: {
                    Text("让价格落在真正的那一天")
                } footer: {
                    Text("这里的日期用于住宿和交通核价，不会擅自打乱已经排好的景点。")
                }

                Section {
                    Picker("市内脚步", selection: $model.draft.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbolName).tag(mode)
                        }
                    }

                    Picker("抵达方式", selection: $model.draft.logistics.preferredLongDistanceMode) {
                        Text("让地图推荐").tag(nil as LongDistanceMode?)
                        ForEach(LongDistanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbolName).tag(Optional(mode))
                        }
                    }

                    Toggle("这次先不安排住宿", isOn: $model.draft.logistics.skipAccommodation)
                        .accessibilityLabel("这次先不安排住宿")
                        .accessibilityIdentifier("trip-conditions-skip-accommodation")
                    Toggle("这次先不安排大交通", isOn: $model.draft.logistics.skipTransport)
                        .accessibilityLabel("这次先不安排大交通")
                        .accessibilityIdentifier("trip-conditions-skip-transport")
                } header: {
                    Text("行走与抵达")
                }

                if !changeImpacts.isEmpty {
                    Section {
                        ForEach(Array(changeImpacts.enumerated()), id: \.offset) { _, impact in
                            Label(impact, systemImage: "arrow.triangle.branch")
                                .font(.subheadline)
                                .foregroundStyle(AnyTravelPalette.secondaryInk)
                        }
                    } header: {
                        Text("应用前先看会改变什么")
                    } footer: {
                        Text("锁定与已确认的景点、住处和班次会优先保留；应用后可从主面板整次撤回。")
                    }
                }
            }
            .navigationTitle("调整旅行条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if let originalDraft { model.draft = originalDraft }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(changeImpacts.isEmpty ? "没有改动" : "应用 \(changeImpacts.count) 项") {
                        model.applyConditionChanges(from: originalDraft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(changeImpacts.isEmpty)
                    .accessibilityIdentifier("trip-conditions-apply")
                }
            }
        }
        .onAppear {
            if originalDraft == nil { originalDraft = model.draft }
        }
    }

    private var changeImpacts: [String] {
        guard let originalDraft else { return [] }
        return model.conditionChangeImpacts(from: originalDraft)
    }

    private func dateAdjustmentRow(
        title: String,
        value: String,
        decrementDisabled: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack {
            Text("用按钮调整\(title)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: decrement) {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
            }
            .disabled(decrementDisabled)
            .accessibilityLabel("\(title)提前一天")
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 82)
                .accessibilityIdentifier(title == "抵达日" ? "trip-conditions-arrival-date-value" : "trip-conditions-return-date-value")
            Button(action: increment) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("\(title)推后一天")
        }
        .buttonStyle(AnyTravelPressStyle())
    }
}

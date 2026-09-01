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
                        "同行人数：\(model.draft.logistics.travelers)人",
                        value: $model.draft.logistics.travelers,
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
                    Button("重新计算") {
                        model.applyConditionChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if originalDraft == nil { originalDraft = model.draft }
        }
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

import SwiftUI

struct ItineraryEditorView: View {
    @Bindable var model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDayIndex = 0
    @State private var searchText = ""
    @State private var searchInterest: TripInterest = .culture
    @State private var searchResults: [TravelPlace] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @FocusState private var searchFocused: Bool

    private var selectedDay: ItineraryDay? {
        model.itineraryDays.first { $0.index == selectedDayIndex }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayPicker

                if let notice = model.noticeMessage {
                    Label(notice, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(AnyTravelPalette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(AnyTravelPalette.route.opacity(0.08))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                List {
                    Section {
                        if let selectedDay {
                            ForEach(Array(selectedDay.stops.enumerated()), id: \.element.id) { index, place in
                                stopRow(place, index: index, count: selectedDay.stops.count)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            performAnimatedEdit {
                                                model.removePlace(place, from: selectedDayIndex)
                                            }
                                        } label: {
                                            Label("移出行程", systemImage: "trash")
                                        }
                                    }
                            }
                            .onMove { offsets, destination in
                                performAnimatedEdit {
                                    model.moveStops(
                                        fromOffsets: offsets,
                                        toOffset: destination,
                                        in: selectedDayIndex
                                    )
                                }
                            }
                        }
                    } header: {
                        Text("当天的脚步")
                    } footer: {
                        Text("拖动或使用每一站右侧的菜单调整顺序；改变后，地图路线会自动重新铺开。")
                    }

                    Section {
                        searchField

                        if isSearching {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在地图上寻找相近的地方")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let searchError {
                            ContentUnavailableView(
                                "暂时没有找到",
                                systemImage: "magnifyingglass",
                                description: Text(searchError)
                            )
                        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  searchResults.isEmpty {
                            ContentUnavailableView(
                                "没有合适的结果",
                                systemImage: "mappin.slash",
                                description: Text("换一个名字或类别再试试。")
                            )
                        } else {
                            ForEach(searchResults) { place in
                                searchResultRow(place)
                            }
                        }
                    } header: {
                        Text("再添一处停靠")
                    } footer: {
                        Text("搜索结果来自 Apple Maps，并限制在目的地周边约 60 公里。")
                    }
                }
                .listStyle(.insetGrouped)
                .animation(
                    AnyTravelMotion.snappy(reduceMotion: reduceMotion),
                    value: model.itineraryDays
                )
            }
            .navigationTitle("编排行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    EditButton()

                    Button {
                        performAnimatedEdit {
                            model.undoItineraryChange()
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndoItineraryChange)
                    .accessibilityLabel("撤销")

                    Button {
                        performAnimatedEdit {
                            model.redoItineraryChange()
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!model.canRedoItineraryChange)
                    .accessibilityLabel("重做")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        model.finishItineraryEditing()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            selectedDayIndex = model.selectedDayIndex
        }
        .onDisappear {
            model.finishItineraryEditing()
        }
        .task(id: "\(searchInterest.rawValue)|\(searchText)") {
            await performSearch()
        }
    }

    private var dayPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.itineraryDays) { day in
                    let selected = day.index == selectedDayIndex
                    Button {
                        selectedDayIndex = day.index
                        model.selectDay(day.index)
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.title)
                                .font(.caption.weight(.bold))
                            Text("\(day.stops.count)处")
                                .font(.caption2)
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(selected ? AnyTravelPalette.route : AnyTravelPalette.softSurface, in: Capsule())
                    }
                    .buttonStyle(AnyTravelPressStyle())
                    .accessibilityLabel(day.title)
                    .accessibilityValue("\(day.stops.count)处")
                    .accessibilityIdentifier("itinerary-day-\(day.index)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    private var searchField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AnyTravelPalette.route)
                TextField("搜索景点、餐厅或想去的地方", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(AnyTravelPressStyle())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("清空地点搜索")
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(TripInterest.allCases) { interest in
                        let selected = searchInterest == interest
                        Button {
                            searchInterest = interest
                        } label: {
                            Label(interest.title, systemImage: interest.symbolName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(selected ? AnyTravelPalette.route : AnyTravelPalette.route.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(AnyTravelPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func stopRow(_ place: TravelPlace, index: Int, count: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(AnyTravelPalette.routeColor(for: selectedDayIndex), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                Text(place.address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    performAnimatedEdit {
                        model.movePlace(place, by: -1, in: selectedDayIndex)
                    }
                } label: {
                    Label("向前一站", systemImage: "arrow.up")
                }
                .disabled(index == 0)

                Button {
                    performAnimatedEdit {
                        model.movePlace(place, by: 1, in: selectedDayIndex)
                    }
                } label: {
                    Label("向后一站", systemImage: "arrow.down")
                }
                .disabled(index == count - 1)

                if model.itineraryDays.count > 1 {
                    Divider()

                    Menu {
                        ForEach(otherDays) { day in
                            Button {
                                performAnimatedEdit {
                                    model.movePlace(
                                        place,
                                        from: selectedDayIndex,
                                        to: day.index
                                    )
                                }
                            } label: {
                                Label(day.title, systemImage: "arrow.right")
                            }
                            .accessibilityIdentifier("move-stop-to-day-\(day.index)")
                        }
                    } label: {
                        Label("移到另一天", systemImage: "calendar")
                    }

                    Menu {
                        ForEach(otherDays) { day in
                            Button {
                                performAnimatedEdit {
                                    model.duplicatePlace(
                                        place,
                                        from: selectedDayIndex,
                                        to: day.index
                                    )
                                }
                            } label: {
                                Label(day.title, systemImage: "plus.rectangle.on.rectangle")
                            }
                            .accessibilityIdentifier("copy-stop-to-day-\(day.index)")
                        }
                    } label: {
                        Label("复制到另一天", systemImage: "square.on.square")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    performAnimatedEdit {
                        model.removePlace(place, from: selectedDayIndex)
                    }
                } label: {
                    Label("移出行程", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("调整\(place.name)")
        }
        .frame(minHeight: 56)
    }

    private func searchResultRow(_ place: TravelPlace) -> some View {
        let alreadyIncluded = model.isPlaceIncluded(place)
        return Button {
            var added = false
            performAnimatedEdit {
                added = model.addPlace(place, to: selectedDayIndex)
            }
            guard added else { return }
            searchResults.removeAll { $0.id == place.id }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: place.interest.symbolName)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AnyTravelPalette.route, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(place.address)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: alreadyIncluded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(alreadyIncluded ? .secondary : AnyTravelPalette.route)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AnyTravelPressStyle())
        .disabled(alreadyIncluded)
        .accessibilityLabel(alreadyIncluded ? "\(place.name)已在行程" : "添加\(place.name)")
    }

    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(360))
            try Task.checkCancellation()
            isSearching = true
            searchError = nil
            let results = try await model.searchAdditionalPlaces(
                matching: query,
                interest: searchInterest
            )
            try Task.checkCancellation()
            searchResults = results
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            isSearching = false
            searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var otherDays: [ItineraryDay] {
        model.itineraryDays.filter { $0.index != selectedDayIndex }
    }

    private func performAnimatedEdit(_ edit: () -> Void) {
        withAnimation(AnyTravelMotion.snappy(reduceMotion: reduceMotion)) {
            edit()
        }
    }
}

import SwiftUI

struct ItineraryEditorView: View {
    @Bindable var model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
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

                List {
                    Section {
                        if let selectedDay {
                            ForEach(Array(selectedDay.stops.enumerated()), id: \.element.id) { index, place in
                                stopRow(place, index: index, count: selectedDay.stops.count)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            model.removePlace(place, from: selectedDayIndex)
                                        } label: {
                                            Label("移出行程", systemImage: "trash")
                                        }
                                    }
                            }
                            .onMove { offsets, destination in
                                model.moveStops(
                                    fromOffsets: offsets,
                                    toOffset: destination,
                                    in: selectedDayIndex
                                )
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
            }
            .navigationTitle("编排行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EditButton()
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
                        }
                        .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(selected ? AnyTravelPalette.route : AnyTravelPalette.softSurface, in: Capsule())
                    }
                    .buttonStyle(AnyTravelPressStyle())
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
                    .buttonStyle(.plain)
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
                                .frame(minHeight: 36)
                                .background(selected ? AnyTravelPalette.route : AnyTravelPalette.route.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
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
                    model.movePlace(place, by: -1, in: selectedDayIndex)
                } label: {
                    Label("向前一站", systemImage: "arrow.up")
                }
                .disabled(index == 0)

                Button {
                    model.movePlace(place, by: 1, in: selectedDayIndex)
                } label: {
                    Label("向后一站", systemImage: "arrow.down")
                }
                .disabled(index == count - 1)

                Divider()

                Button(role: .destructive) {
                    model.removePlace(place, from: selectedDayIndex)
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
        let alreadyIncluded = model.itineraryDays.flatMap(\.stops).contains { existing in
            existing.name.localizedCaseInsensitiveCompare(place.name) == .orderedSame
        }
        return Button {
            guard model.addPlace(place, to: selectedDayIndex) else { return }
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
        .buttonStyle(.plain)
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
}

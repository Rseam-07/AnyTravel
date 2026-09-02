import SwiftUI

struct AttractionSelectionView: View {
    @Bindable var model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: TripInterest?
    @State private var selectionFeedback = 0

    private var visibleCandidates: [TravelPlace] {
        guard let filter else { return model.attractionCandidates }
        return model.attractionCandidates.filter { $0.interest == filter }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isAttractionDiscoveryLoading {
                    loadingView
                } else if model.attractionCandidates.isEmpty {
                    emptyView
                } else {
                    candidateList
                }
            }
            .background(AnyTravelPalette.softSurface.ignoresSafeArea())
            .navigationTitle("先挑想去的地方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") {
                        model.attractionPickerPresented = false
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.attractionCandidates.isEmpty, !model.isAttractionDiscoveryLoading {
                    actionBar
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .interactiveDismissDisabled(model.isAttractionDiscoveryLoading)
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            TravelLoadingGlyph()
            Text("正在翻阅这座城的热门去处")
                .font(.headline)
            Text("同时检索热门景点、必去地标与偏好分类，再按线上名次、评分和空间分布去重排序。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("暂时没有找到景点", systemImage: "map")
        } description: {
            Text(model.attractionSelectionMessage ?? "地图与在线资料暂时没有回应。")
        } actions: {
            Button("重新寻找") { Task { await model.beginAttractionSelection() } }
                .buttonStyle(.borderedProminent)
                .tint(AnyTravelPalette.route)
        }
    }

    private var candidateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                introduction
                filters

                if let pressure = model.attractionSelectionPressureMessage {
                    Label(pressure, systemImage: "wind")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AnyTravelPalette.warm)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AnyTravelPalette.warm.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ForEach(visibleCandidates) { place in
                    candidateRow(place)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 118)
        }
        .scrollIndicators(.hidden)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: model.selectedAttractionIDs)
        .animation(AnyTravelMotion.snappy(reduceMotion: reduceMotion), value: filter)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(model.attractionCandidates.count) 处去处，已由热门到小众排好")
                .font(.title3.bold())
            Text("勾选的地方会成为主游览点并留出更长停留；选得少会顺路补齐，全部跳过则由 AnyTravel 依热度与距离安排。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label("建议约 \(model.suggestedAttractionCount) 处", systemImage: "leaf")
                if !model.selectedAttractionIDs.isEmpty {
                    Text("已选 \(model.selectedAttractionIDs.count) 处")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AnyTravelPalette.routeDark)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnyTravelPalette.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterChip(nil, title: "全部")
                ForEach(TripInterest.allCases) { interest in
                    if model.attractionCandidates.contains(where: { $0.interest == interest }) {
                        filterChip(interest, title: interest.title)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(_ interest: TripInterest?, title: String) -> some View {
        let selected = filter == interest
        return Button(title) { filter = interest }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? .white : AnyTravelPalette.routeDark)
            .padding(.horizontal, 13)
            .frame(minHeight: 42)
            .background(selected ? AnyTravelPalette.route : AnyTravelPalette.softSurface, in: Capsule())
            .buttonStyle(AnyTravelPressStyle())
    }

    private func candidateRow(_ place: TravelPlace) -> some View {
        let selected = model.selectedAttractionIDs.contains(place.id)
        return Button {
            model.toggleAttractionSelection(place)
            selectionFeedback += 1
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selected ? AnyTravelPalette.route : AnyTravelPalette.route.opacity(0.10))
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("\(place.popularity?.rank ?? 0)")
                            .font(.caption.bold())
                            .foregroundStyle(AnyTravelPalette.routeDark)
                    }
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(place.name)
                            .font(.headline)
                            .foregroundStyle(AnyTravelPalette.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        if let rating = place.popularity?.rating {
                            Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                .font(.caption.bold())
                                .foregroundStyle(AnyTravelPalette.warm)
                        }
                    }
                    Text(place.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 7) {
                        Label(place.interest.title, systemImage: place.interest.symbolName)
                        if let evidence = place.popularity?.evidence.first {
                            Text(evidence).lineLimit(1)
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AnyTravelPalette.routeDark)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? AnyTravelPalette.route.opacity(0.10) : AnyTravelPalette.elevatedSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AnyTravelPalette.route.opacity(selected ? 0.50 : 0.12), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(AnyTravelPressStyle())
        .accessibilityLabel("\(place.popularity?.rank ?? 0)名，\(place.name)")
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private var actionBar: some View {
        VStack(spacing: 9) {
            if model.selectedAttractionIDs.isEmpty {
                Text("还没勾选也没关系，可以把这一城交给路线来判断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await model.confirmAttractionSelection(automatic: true) }
                } label: {
                    Text("跳过，替我挑")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(AnyTravelPressStyle())
                .background(AnyTravelPalette.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    Task { await model.confirmAttractionSelection(automatic: false) }
                } label: {
                    Label(
                        model.selectedAttractionIDs.isEmpty ? "按热度生成" : "按已选生成",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AnyTravelPalette.route, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(AnyTravelPressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

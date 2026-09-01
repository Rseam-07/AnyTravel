import SwiftUI

struct SavedTripsView: View {
    @Bindable var model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: SavedTrip?

    var body: some View {
        NavigationStack {
            Group {
                if model.tripStore.trips.isEmpty {
                    ContentUnavailableView(
                        "旅册还是空白",
                        systemImage: "book.closed",
                        description: Text("把一段路线收进行囊，它就会留在这里，等你再次翻开。")
                    )
                } else {
                    List {
                        if let message = model.tripStore.lastErrorMessage {
                            Section {
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(AnyTravelPalette.warm)
                            }
                        }

                        Section("收进这台设备的旅程") {
                            ForEach(model.tripStore.trips) { trip in
                                Button {
                                    model.loadSavedTrip(trip)
                                    dismiss()
                                } label: {
                                    SavedTripRow(trip: trip)
                                }
                                .buttonStyle(AnyTravelPressStyle())
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeletion = trip
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("我的旅册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "删除“\(pendingDeletion?.title ?? "这条行程")”？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDeletion {
                    model.deleteSavedTrip(pendingDeletion)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("删除后无法从这台设备恢复。")
        }
    }
}

private struct SavedTripRow: View {
    let trip: SavedTrip

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AnyTravelPalette.route, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(trip.days.count)天 · \(trip.days.reduce(0) { $0 + $1.stops.count })个地点 · \(trip.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

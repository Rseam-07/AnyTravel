import CoreLocation
import Foundation
import MapKit

struct LocalTransferResult {
    var options: [LocalTransferOption]
    var routesByOptionID: [LocalTransferOption.ID: MKRoute]
    var failedModes: [LocalTransferMode]
}

struct LocalTransferPolicy {
    func estimatedCost(
        for mode: LocalTransferMode,
        distanceMeters: Double,
        durationMinutes: Int,
        travelers: Int
    ) -> Int {
        switch mode {
        case .walking:
            return 0
        case .publicTransit:
            let distanceBands = max(Int(ceil(distanceMeters / 6_000)), 1)
            let perPerson = min(2 + (distanceBands - 1) * 2, 14)
            return perPerson * max(travelers, 1)
        case .taxi:
            let kilometersBeyondBase = max(distanceMeters / 1_000 - 3, 0)
            let estimate = 14 + kilometersBeyondBase * 2.7 + Double(durationMinutes) * 0.25
            return max(Int(estimate.rounded()), 14)
        }
    }

    func recommendedMode(
        from options: [LocalTransferOption],
        referenceDate: Date?,
        travelers: Int,
        calendar: Calendar = .current
    ) -> LocalTransferMode? {
        guard !options.isEmpty else { return nil }
        if let walking = options.first(where: { $0.mode == .walking }),
           walking.distanceMeters <= 1_600,
           walking.durationMinutes <= 28 {
            return .walking
        }

        let hour = referenceDate.map { calendar.component(.hour, from: $0) }
        if let hour, (hour < 6 || hour >= 22), options.contains(where: { $0.mode == .taxi }) {
            return .taxi
        }

        if travelers >= 3,
           let taxi = options.first(where: { $0.mode == .taxi }),
           let transit = options.first(where: { $0.mode == .publicTransit && $0.routeKind == .appleMaps }),
           taxi.estimatedCostCNY <= transit.estimatedCostCNY + 18 {
            return .taxi
        }

        if options.contains(where: { $0.mode == .publicTransit && $0.routeKind == .appleMaps }) {
            return .publicTransit
        }
        if options.contains(where: { $0.mode == .taxi }) { return .taxi }
        if options.contains(where: { $0.mode == .walking }) { return .walking }
        return options.first?.mode
    }
}

struct LocalTransferService {
    private let policy = LocalTransferPolicy()

    func buildOptions(
        direction: TransportDirection,
        accessPoint: AccessPoint,
        accommodation: AccommodationOption,
        travelers: Int,
        referenceDate: Date?
    ) async -> LocalTransferResult {
        let sourceName = direction == .outbound ? accessPoint.name : accommodation.name
        let destinationName = direction == .outbound ? accommodation.name : accessPoint.name
        let sourceCoordinate = direction == .outbound ? accessPoint.coordinate : accommodation.coordinate
        let destinationCoordinate = direction == .outbound ? accommodation.coordinate : accessPoint.coordinate
        var options: [LocalTransferOption] = []
        var routes: [LocalTransferOption.ID: MKRoute] = [:]
        var failedModes: [LocalTransferMode] = []

        for mode in LocalTransferMode.allCases {
            let request = MKDirections.Request()
            request.source = mapItem(name: sourceName, coordinate: sourceCoordinate)
            request.destination = mapItem(name: destinationName, coordinate: destinationCoordinate)
            request.transportType = transportType(for: mode)
            request.requestsAlternateRoutes = false
            if mode == .publicTransit {
                request.departureDate = max(referenceDate ?? .now, .now)
            }

            do {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.first else {
                    failedModes.append(mode)
                    continue
                }
                let durationMinutes = max(Int((route.expectedTravelTime / 60).rounded()), 1)
                let cost = policy.estimatedCost(
                    for: mode,
                    distanceMeters: route.distance,
                    durationMinutes: durationMinutes,
                    travelers: travelers
                )
                let option = LocalTransferOption(
                    direction: direction,
                    mode: mode,
                    originName: sourceName,
                    destinationName: destinationName,
                    durationMinutes: durationMinutes,
                    distanceMeters: route.distance,
                    estimatedCostCNY: cost,
                    costNote: costNote(for: mode, travelers: travelers),
                    recommendationReasons: [
                        "Apple Maps 路线约 \(route.distance.anyTravelDistanceText)",
                        timingReason(for: mode, referenceDate: referenceDate)
                    ]
                )
                options.append(option)
                routes[option.id] = route
            } catch is CancellationError {
                return LocalTransferResult(options: options, routesByOptionID: routes, failedModes: failedModes)
            } catch {
                failedModes.append(mode)
            }
        }

        appendTransitEstimateIfNeeded(
            to: &options,
            failedModes: failedModes,
            direction: direction,
            sourceName: sourceName,
            destinationName: destinationName,
            travelers: travelers,
            referenceDate: referenceDate
        )

        let recommended = policy.recommendedMode(
            from: options,
            referenceDate: referenceDate,
            travelers: travelers
        )
        for index in options.indices {
            options[index].isRecommended = options[index].mode == recommended
            if options[index].isRecommended {
                options[index].recommendationReasons.insert(
                    recommendationReason(for: options[index], referenceDate: referenceDate, travelers: travelers),
                    at: 0
                )
            }
        }
        options.sort {
            if $0.isRecommended != $1.isRecommended { return $0.isRecommended }
            return $0.durationMinutes < $1.durationMinutes
        }
        return LocalTransferResult(options: options, routesByOptionID: routes, failedModes: failedModes)
    }

    private func appendTransitEstimateIfNeeded(
        to options: inout [LocalTransferOption],
        failedModes: [LocalTransferMode],
        direction: TransportDirection,
        sourceName: String,
        destinationName: String,
        travelers: Int,
        referenceDate: Date?
    ) {
        guard failedModes.contains(.publicTransit),
              !options.contains(where: { $0.mode == .publicTransit }),
              let distanceReference = options.first(where: { $0.mode == .taxi })
                ?? options.first(where: { $0.mode == .walking }) else { return }

        let distance = distanceReference.distanceMeters
        let durationMinutes = max(Int((distance / 350).rounded()) + 12, 18)
        let cost = policy.estimatedCost(
            for: .publicTransit,
            distanceMeters: distance,
            durationMinutes: durationMinutes,
            travelers: travelers
        )
        let clock = referenceDate?.formatted(date: .omitted, time: .shortened)
        let timing = clock.map { "参考 \($0) 左右的抵达时刻" } ?? "参考当前规划时刻"
        options.append(
            LocalTransferOption(
                direction: direction,
                mode: .publicTransit,
                originName: sourceName,
                destinationName: destinationName,
                durationMinutes: durationMinutes,
                distanceMeters: distance,
                estimatedCostCNY: cost,
                routeKind: .distanceEstimate,
                costNote: "Apple Maps 暂未返回公交路径；按距离估算，出发前请在地图复核",
                recommendationReasons: [
                    "这是距离估算，不是已查询到的公交路线",
                    timing
                ]
            )
        )
    }

    private func transportType(for mode: LocalTransferMode) -> MKDirectionsTransportType {
        switch mode {
        case .publicTransit: .transit
        case .taxi: .automobile
        case .walking: .walking
        }
    }

    private func costNote(for mode: LocalTransferMode, travelers: Int) -> String {
        switch mode {
        case .publicTransit: "按 \(max(travelers, 1)) 人与里程估算，实际票制以当地为准"
        case .taxi: "按里程与行车时间估算，不是网约车实时报价"
        case .walking: "无需交通费用"
        }
    }

    private func timingReason(for mode: LocalTransferMode, referenceDate: Date?) -> String {
        guard let referenceDate else { return "按当前可用路线计算" }
        let clock = referenceDate.formatted(date: .omitted, time: .shortened)
        return mode == .publicTransit ? "按 \(clock) 左右的公共交通查询" : "结合 \(clock) 左右的抵达时间"
    }

    private func recommendationReason(
        for option: LocalTransferOption,
        referenceDate: Date?,
        travelers: Int
    ) -> String {
        let hour = referenceDate.map { Calendar.current.component(.hour, from: $0) }
        if option.mode == .walking { return "距离不远，慢慢走也轻松" }
        if option.mode == .taxi, let hour, hour < 6 || hour >= 22 { return "抵达较晚，少一次换乘更从容" }
        if option.mode == .taxi, travelers >= 3 { return "同行人数较多，合乘更省心" }
        return "时间、费用与换乘负担更均衡"
    }

    private func mapItem(name: String, coordinate: Coordinate) -> MKMapItem {
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clLocationCoordinate))
        }
        item.name = name
        return item
    }
}

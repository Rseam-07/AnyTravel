import Foundation

struct TransportRecommendationEngine {
    func buildOptions(
        origin: DestinationResolution?,
        destination: DestinationResolution,
        accessPoints: [AccessPoint],
        selectedAccommodation: AccommodationOption?,
        draft: TripDraft
    ) -> [TransportOption] {
        guard !draft.logistics.skipTransport else { return [] }

        let distanceKM = origin.map {
            LogisticsSearchService.distance(from: $0.coordinate, to: destination.coordinate) / 1_000
        }
        let modes: [LongDistanceMode] = [.train, .flight, .driving, .coach]
        let preferred = draft.logistics.preferredLongDistanceMode
        let automaticRecommendation = preferred ?? recommendedMode(for: distanceKM)

        return modes.map { mode in
            let accessKind: AccessPointKind? = switch mode {
            case .train: .rail
            case .flight: .airport
            case .driving, .coach: nil
            }
            let arrivalPoint = accessKind.flatMap { kind in
                accessPoints
                    .filter { $0.kind == kind }
                    .min {
                        LogisticsSearchService.distance(from: $0.coordinate, to: destination.coordinate)
                            < LogisticsSearchService.distance(from: $1.coordinate, to: destination.coordinate)
                    }
            }
            let transferMeters = arrivalPoint.flatMap { point in
                selectedAccommodation.map {
                    LogisticsSearchService.distance(from: point.coordinate, to: $0.coordinate)
                }
            }

            var reasons: [String] = []
            if let distanceKM {
                reasons.append("两地直线约 \(Int(distanceKM.rounded())) 公里")
                reasons.append("总耗时为距离规则估算，接入班次后替换")
            } else {
                reasons.append("补充出发地后比较门到门时间")
            }
            if preferred == mode { reasons.insert("你已优先选择这种方式", at: 0) }
            if let arrivalPoint, let transferMeters {
                reasons.append("\(arrivalPoint.name)到住宿约 \(transferMeters.anyTravelDistanceText)")
            }

            return TransportOption(
                mode: mode,
                title: title(for: mode, destinationName: destination.title),
                originName: origin?.title ?? draft.logistics.origin.nonEmptyForLogistics ?? "出发地待定",
                destinationName: destination.title,
                durationMinutes: durationMinutes(for: mode, distanceKM: distanceKM),
                arrivalAccessPoint: arrivalPoint,
                hotelTransferMeters: transferMeters,
                quotes: quotes(for: mode, hasDates: draft.logistics.hasDates),
                recommendationReasons: reasons,
                isRecommended: mode == automaticRecommendation
            )
        }
        .sorted {
            if $0.isRecommended != $1.isRecommended { return $0.isRecommended }
            return ($0.durationMinutes ?? .max) < ($1.durationMinutes ?? .max)
        }
    }

    private func recommendedMode(for distanceKM: Double?) -> LongDistanceMode {
        guard let distanceKM else { return .train }
        if distanceKM <= 220 { return .driving }
        if distanceKM <= 900 { return .train }
        return .flight
    }

    private func durationMinutes(for mode: LongDistanceMode, distanceKM: Double?) -> Int? {
        guard let distanceKM else { return nil }
        let hours: Double = switch mode {
        case .train: distanceKM / 220 + 1.4
        case .flight: distanceKM / 720 + 3.6
        case .driving: distanceKM / 78 * 1.18
        case .coach: distanceKM / 68 * 1.25 + 0.5
        }
        return max(Int((hours * 60).rounded()), 30)
    }

    private func title(for mode: LongDistanceMode, destinationName: String) -> String {
        switch mode {
        case .train: "高铁抵达 \(destinationName)"
        case .flight: "航班抵达 \(destinationName)"
        case .driving: "自驾前往 \(destinationName)"
        case .coach: "客运前往 \(destinationName)"
        }
    }

    private func quotes(for mode: LongDistanceMode, hasDates: Bool) -> [ProviderQuote] {
        let note = hasDates ? "按出行日期到渠道核对班次与含税总价" : "补充日期后查询班次与价格"
        switch mode {
        case .train:
            return [
                ProviderQuote(
                    provider: .railway12306,
                    unit: .perPerson,
                    kind: .checkOnProvider,
                    bookingURL: URL(string: "https://kyfw.12306.cn/otn/leftTicket/init"),
                    note: "铁路票只在官方渠道购买；\(note)"
                )
            ]
        case .flight:
            return [
                ProviderQuote(provider: .ctrip, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://flights.ctrip.com/"), note: note),
                ProviderQuote(provider: .qunar, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://flight.qunar.com/"), note: note),
                ProviderQuote(provider: .skyscanner, unit: .perPerson, kind: .requiresPartnerAccess, bookingURL: URL(string: "https://www.skyscanner.com/flights"), note: "实时航班适配器已预留")
            ]
        case .driving:
            return [
                ProviderQuote(provider: .anyTravelEstimate, unit: .total, kind: .budgetEstimate, note: "路线确定后按实际里程补充油费与高速费")
            ]
        case .coach:
            return [
                ProviderQuote(provider: .ctrip, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://bus.ctrip.com/"), note: note),
                ProviderQuote(provider: .qunar, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://bus.qunar.com/"), note: note)
            ]
        }
    }
}

struct ExpensePlanner {
    func buildLines(
        draft: TripDraft,
        accommodation: AccommodationOption?,
        transport: TransportOption?
    ) -> [ExpenseLine] {
        let totalBudget = draft.budgetPerPerson * max(draft.logistics.travelers, 1)
        let rooms = max((draft.logistics.travelers + 1) / 2, 1)
        let nights = draft.logistics.skipAccommodation ? 0 : max(draft.logistics.nights, max(draft.dayCount - 1, 0))

        let transportQuote = transport?.quotes.bestUsableQuote
        let quotedOutboundAmount = transportQuote?.amountCNY.map { amount in
            transportQuote?.unit == .perPerson ? amount * max(draft.logistics.travelers, 1) : amount
        }
        let roundTripEnvelope = Int(Double(totalBudget) * 0.24)
        let outboundAmount = quotedOutboundAmount ?? roundTripEnvelope / 2
        let returnAmount = quotedOutboundAmount ?? (roundTripEnvelope - outboundAmount)

        let hotelQuote = accommodation?.quotes.bestUsableQuote
        let accommodationAmount: Int
        if nights == 0 {
            accommodationAmount = 0
        } else if let nightly = hotelQuote?.amountCNY {
            accommodationAmount = nightly * nights * rooms
        } else {
            accommodationAmount = Int(Double(totalBudget) * 0.34)
        }

        let transportLines: [ExpenseLine]
        if draft.logistics.skipTransport {
            transportLines = [
                ExpenseLine(
                    id: "transport",
                    title: "大交通",
                    detail: "已按你的选择暂时跳过",
                    amountCNY: 0,
                    source: .budgetEnvelope
                )
            ]
        } else {
            transportLines = [
                ExpenseLine(
                    id: "outbound-transport",
                    title: "去程大交通",
                    detail: transportQuote.map { "\($0.provider.title) · \($0.kind.title) · 当前去程" }
                        ?? "先留出往返交通预算的一半",
                    amountCNY: outboundAmount,
                    source: transportQuote?.kind == .live ? .live : .budgetEnvelope
                ),
                ExpenseLine(
                    id: "return-transport",
                    title: "返程大交通",
                    detail: quotedOutboundAmount == nil
                        ? "先留出往返交通预算的一半"
                        : "按当前去程价格预留 · 尚非返程实时报价",
                    amountCNY: returnAmount,
                    source: .budgetEnvelope
                )
            ]
        }

        return transportLines + [
            ExpenseLine(
                id: "accommodation",
                title: "住宿",
                detail: nights == 0 ? "已跳过或无需过夜" : hotelQuote.map { "\(nights)晚 × \(rooms)间 · \($0.provider.title)" } ?? "\(nights)晚 · 等待多渠道报价",
                amountCNY: accommodationAmount,
                source: hotelQuote?.kind == .live ? .live : .budgetEnvelope
            ),
            ExpenseLine(id: "tickets", title: "景点与预约", detail: "按景点逐项核价前的额度", amountCNY: Int(Double(totalBudget) * 0.13), source: .budgetEnvelope),
            ExpenseLine(id: "meals", title: "餐饮", detail: "默认轻松节奏，预留正餐与休息", amountCNY: Int(Double(totalBudget) * 0.17), source: .budgetEnvelope),
            ExpenseLine(id: "local", title: "市内交通", detail: "地铁、公交与必要打车", amountCNY: Int(Double(totalBudget) * 0.07), source: .budgetEnvelope),
            ExpenseLine(id: "buffer", title: "机动金", detail: "价格波动与临时调整", amountCNY: Int(Double(totalBudget) * 0.05), source: .budgetEnvelope)
        ]
    }
}

struct ScheduleBuilder {
    func build(for day: ItineraryDay, pace: TripPace, accommodation: AccommodationOption?) -> [ScheduleItem] {
        let slots: [(String, String)] = switch pace {
        case .relaxed: [("10:00–12:00", "慢慢参观"), ("14:30–16:30", "午休后继续")]
        case .balanced: [("09:30–11:30", "上午参观"), ("13:30–15:30", "午后参观"), ("16:00–18:00", "傍晚参观")]
        case .full: [("09:00–10:30", "上午第一站"), ("11:00–12:30", "上午第二站"), ("14:00–15:30", "午后第一站"), ("16:00–17:30", "午后第二站")]
        }
        var result: [ScheduleItem] = []
        for (index, stop) in day.stops.enumerated() {
            if index == 1 {
                let lunchTime = pace == .relaxed ? "12:00–14:30" : "12:30–13:30"
                result.append(ScheduleItem(id: "\(day.index)-lunch", timeText: lunchTime, title: "午餐与休息", detail: "在相邻景点附近用餐，留出缓冲时间", placeID: nil))
            }
            let slot = slots[min(index, slots.count - 1)]
            result.append(
                ScheduleItem(
                    id: "\(day.index)-\(stop.id)",
                    timeText: slot.0,
                    title: stop.name,
                    detail: "\(stop.interest.visitIntroduction) · \(slot.1)",
                    placeID: stop.id
                )
            )
        }
        if let accommodation {
            result.append(
                ScheduleItem(
                    id: "\(day.index)-hotel",
                    timeText: pace == .full ? "18:30后" : "17:30后",
                    title: day.index == 0 ? "办理入住并休息" : "返回住宿",
                    detail: accommodation.name,
                    placeID: nil
                )
            )
        }
        return result
    }
}

private extension Array where Element == ProviderQuote {
    var bestUsableQuote: ProviderQuote? {
        filter { $0.amountCNY != nil && $0.kind != .demo }
            .min { ($0.amountCNY ?? .max) < ($1.amountCNY ?? .max) }
    }
}

private extension TripInterest {
    var visitIntroduction: String {
        switch self {
        case .gardens: "园林与建筑类地点，适合放慢速度看空间和细节"
        case .culture: "人文类地点，建议把主要展陈和现场说明一起看"
        case .food: "本地饮食体验，给排队和点餐留出余量"
        case .nature: "自然慢逛地点，路线以舒适和少折返为先"
        case .family: "亲子体验地点，安排了更完整的休息间隔"
        case .night: "夜间体验地点，出发前复核开放时间"
        }
    }
}

private extension String {
    var nonEmptyForLogistics: String? { isEmpty ? nil : self }
}

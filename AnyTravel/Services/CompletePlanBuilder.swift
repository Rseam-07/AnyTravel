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
                ProviderQuote(provider: .tongcheng, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://m.ly.com/flight/"), note: note),
                ProviderQuote(provider: .skyscanner, unit: .perPerson, kind: .requiresPartnerAccess, bookingURL: URL(string: "https://www.skyscanner.com/flights"), note: "实时航班适配器已预留")
            ]
        case .driving:
            return [
                ProviderQuote(provider: .anyTravelEstimate, unit: .total, kind: .budgetEstimate, note: "路线确定后按实际里程补充油费与高速费")
            ]
        case .coach:
            return [
                ProviderQuote(provider: .ctrip, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://bus.ctrip.com/"), note: note),
                ProviderQuote(provider: .qunar, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://bus.qunar.com/"), note: note),
                ProviderQuote(provider: .tongcheng, unit: .perPerson, kind: .checkOnProvider, bookingURL: URL(string: "https://m.ly.com/bus/"), note: note)
            ]
        }
    }
}

struct ExpensePlanner {
    func buildLines(
        draft: TripDraft,
        accommodation: AccommodationOption?,
        transport: TransportOption?,
        returnTransport: TransportOption? = nil,
        outboundTransfer: LocalTransferOption? = nil,
        returnTransfer: LocalTransferOption? = nil,
        itineraryDays: [ItineraryDay] = [],
        bookingConfirmations: [BookingConfirmation] = []
    ) -> [ExpenseLine] {
        let totalBudget = draft.budgetPerPerson * max(draft.logistics.travelers, 1)
        let rooms = max((draft.logistics.travelers + 1) / 2, 1)
        let nights = draft.logistics.skipAccommodation ? 0 : max(draft.logistics.nights, max(draft.dayCount - 1, 0))

        let transportQuote = transport?.quotes.bestUsableQuote
        let returnTransportQuote = returnTransport?.quotes.bestUsableQuote
        let outboundConfirmation = transport.flatMap { option in
            bookingConfirmations.first { $0.kind == .transport && $0.itemID == option.id }
        }
        let returnConfirmation = returnTransport.flatMap { option in
            bookingConfirmations.first { $0.kind == .transport && $0.itemID == option.id }
        }
        let quotedOutboundAmount = totalAmount(for: transportQuote, travelers: draft.logistics.travelers)
        let quotedReturnAmount = totalAmount(for: returnTransportQuote, travelers: draft.logistics.travelers)
        let roundTripEnvelope = Int(Double(totalBudget) * 0.24)
        let outboundAmount = outboundConfirmation?.actualAmountCNY ?? quotedOutboundAmount ?? roundTripEnvelope / 2
        let returnAmount = returnConfirmation?.actualAmountCNY ?? quotedReturnAmount ?? quotedOutboundAmount ?? (roundTripEnvelope - outboundAmount)

        let hotelQuote = accommodation?.quotes.bestUsableQuote
        let hotelConfirmation = accommodation.flatMap { option in
            bookingConfirmations.first { $0.kind == .accommodation && $0.itemID == option.id }
        }
        let accommodationAmount: Int
        if nights == 0 {
            accommodationAmount = 0
        } else if let confirmed = hotelConfirmation?.actualAmountCNY {
            accommodationAmount = confirmed
        } else if let quote = hotelQuote, let quoted = accommodationTotal(for: quote, travelers: draft.logistics.travelers, nights: nights, rooms: rooms) {
            accommodationAmount = quoted
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
                    detail: outboundConfirmation?.actualAmountCNY != nil
                        ? "\(outboundConfirmation?.title ?? transport?.title ?? "当前去程") · 用户记录的订单总额"
                        : transportQuote.map { "\($0.provider.title) · \($0.kind.title) · 当前去程\(outboundConfirmation == nil ? "" : " · 已确认购票，实付未记录")" }
                        ?? "先留出往返交通预算的一半",
                    amountCNY: outboundAmount,
                    source: outboundConfirmation?.actualAmountCNY != nil ? .confirmed : expenseSource(for: transportQuote),
                    unpricedComponents: transportQuote == nil ? ["去程票价"] : []
                ),
                ExpenseLine(
                    id: "return-transport",
                    title: "返程大交通",
                    detail: returnConfirmation?.actualAmountCNY != nil
                        ? "\(returnConfirmation?.title ?? returnTransport?.title ?? "当前返程") · 用户记录的订单总额"
                        : returnTransportQuote.map { "\($0.provider.title) · \($0.kind.title) · 当前返程\(returnConfirmation == nil ? "" : " · 已确认购票，实付未记录")" }
                        ?? (quotedOutboundAmount == nil
                            ? "先留出往返交通预算的一半"
                            : "按当前去程价格预留 · 尚非返程实时报价"),
                    amountCNY: returnAmount,
                    source: returnConfirmation?.actualAmountCNY != nil ? .confirmed : expenseSource(for: returnTransportQuote),
                    unpricedComponents: returnTransportQuote == nil ? ["返程票价"] : []
                )
            ]
        }

        let transferLines: [ExpenseLine]
        if draft.logistics.skipTransport {
            transferLines = []
        } else {
            transferLines = [outboundTransfer, returnTransfer].compactMap { option in
                guard let option else { return nil }
                return ExpenseLine(
                    id: option.direction == .outbound ? "outbound-transfer" : "return-transfer",
                    title: option.direction == .outbound ? "抵达接驳" : "返程接驳",
                    detail: "\(option.mode.title) · \(durationText(option.durationMinutes)) · \(option.costNote)",
                    amountCNY: option.estimatedCostCNY,
                    source: .estimate
                )
            }
        }
        let transferTotal = transferLines.reduce(0) { $0 + $1.amountCNY }
        let localTransportEnvelope = Int(Double(totalBudget) * 0.07)
        let remainingLocalTransport = max(localTransportEnvelope - transferTotal, 0)
        let ticketLine = ticketExpenseLine(
            for: itineraryDays,
            totalBudget: totalBudget,
            travelers: draft.logistics.travelers
        )

        let accommodationPending: [String]
        if nights == 0 {
            accommodationPending = []
        } else {
            accommodationPending = [
                hotelQuote?.taxesIncluded == true ? nil : hotelQuote?.taxesIncluded == false ? "住宿税费（渠道标记未含）" : "住宿税费",
                hotelQuote?.mealPlan?.isEmpty == false ? nil : "早餐",
                "住宿押金"
            ].compactMap { $0 }
        }
        let accommodationDetail: String
        if nights == 0 {
            accommodationDetail = "已跳过或无需过夜"
        } else if hotelConfirmation?.actualAmountCNY != nil {
            accommodationDetail = "\(hotelConfirmation?.title ?? accommodation?.name ?? "住宿") · 用户记录的订单总额"
        } else if let quote = hotelQuote {
            let formula: String
            if quote.totalAmountCNY != nil || quote.unit == .total {
                formula = "渠道返回本次入住总价 · \(nights)晚 · \(rooms)间"
            } else if let amount = quote.amountCNY {
                formula = "¥\(amount)/晚 × \(nights)晚 × \(rooms)间"
            } else {
                formula = "\(nights)晚 × \(rooms)间"
            }
            accommodationDetail = "\(accommodation?.name ?? "住宿") · \(formula)\(hotelConfirmation == nil ? "" : " · 已确认预订，实付未记录")"
        } else {
            accommodationDetail = "\(nights)晚 × \(rooms)间 · 当前按每间2名成人估算"
        }

        return transportLines + transferLines + [
            ExpenseLine(
                id: "accommodation",
                title: "住宿",
                detail: accommodationDetail,
                amountCNY: accommodationAmount,
                source: nights == 0 ? .estimate : hotelConfirmation?.actualAmountCNY != nil ? .confirmed : expenseSource(for: hotelQuote),
                unpricedComponents: accommodationPending
            ),
            ticketLine,
            ExpenseLine(id: "meals", title: "餐饮", detail: "默认轻松节奏，预留正餐与休息", amountCNY: Int(Double(totalBudget) * 0.17), source: .budgetEnvelope),
            ExpenseLine(
                id: "local",
                title: "市内交通",
                detail: transferLines.isEmpty ? "地铁、公交与必要打车" : "扣除已选往返接驳后的市内交通额度",
                amountCNY: remainingLocalTransport,
                source: .budgetEnvelope
            ),
            ExpenseLine(id: "buffer", title: "机动金", detail: "价格波动与临时调整", amountCNY: Int(Double(totalBudget) * 0.05), source: .budgetEnvelope)
        ]
    }

    private func totalAmount(for quote: ProviderQuote?, travelers: Int) -> Int? {
        guard let quote else { return nil }
        if let totalAmountCNY = quote.totalAmountCNY { return totalAmountCNY }
        guard let amount = quote.amountCNY else { return nil }
        return quote.unit == .perPerson ? amount * max(travelers, 1) : amount
    }

    private func accommodationTotal(for quote: ProviderQuote, travelers: Int, nights: Int, rooms: Int) -> Int? {
        if let totalAmountCNY = quote.totalAmountCNY { return totalAmountCNY }
        guard let amount = quote.amountCNY else { return nil }
        switch quote.unit {
        case .total:
            return amount
        case .perPerson:
            return amount * max(travelers, 1)
        case .perNight:
            return amount * max(nights, 1) * max(rooms, 1)
        }
    }

    private func expenseSource(for quote: ProviderQuote?) -> ExpenseSource {
        guard let quote else { return .budgetEnvelope }
        if quote.isStale || quote.kind == .indicative { return .reference }
        if quote.kind == .live { return .live }
        if quote.kind == .budgetEstimate { return .estimate }
        return .budgetEnvelope
    }

    private func ticketExpenseLine(
        for days: [ItineraryDay],
        totalBudget: Int,
        travelers: Int
    ) -> ExpenseLine {
        let stops = days.flatMap(\.stops).filter { $0.interest != .food }
        let quoted = stops.compactMap(\.ticketQuote).filter { $0.amountCNY != nil }
        let quotedTotal = quoted.reduce(0) { partial, quote in
            partial + (totalAmount(for: quote, travelers: travelers) ?? 0)
        }
        let unknownCount = max(stops.count - quoted.count, 0)
        let envelope = Int(Double(totalBudget) * 0.13)

        if quoted.isEmpty {
            return ExpenseLine(
                id: "tickets",
                title: "景点与预约",
                detail: "按景点逐项核价前的额度",
                amountCNY: envelope,
                source: .budgetEnvelope,
                unpricedComponents: stops.isEmpty ? [] : ["\(stops.count)处景点票价"]
            )
        }

        let detail: String
        let amount: Int
        let source: ExpenseSource
        if unknownCount == 0 {
            detail = "\(quoted.count)处采用渠道当前展示价 · 日期、票种与优惠仍需复核"
            amount = quotedTotal
            source = quoted.allSatisfy { $0.kind == .live } ? .live : .estimate
        } else {
            detail = "\(quoted.count)处采用当前展示价，另\(unknownCount)处按预算预留"
            amount = quotedTotal + max(envelope - quotedTotal, 0)
            source = .estimate
        }
        return ExpenseLine(
            id: "tickets",
            title: "景点与预约",
            detail: detail,
            amountCNY: amount,
            source: source,
            unpricedComponents: unknownCount == 0 ? [] : ["\(unknownCount)处景点票价"]
        )
    }

    private func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "约\(minutes)分钟" }
        let remainder = minutes % 60
        return remainder == 0 ? "约\(minutes / 60)小时" : "约\(minutes / 60)小时\(remainder)分钟"
    }
}

struct ScheduleBuilder {
    private let policy = TourismPlanningPolicy()

    func build(
        for day: ItineraryDay,
        pace: TripPace,
        accommodation: AccommodationOption?,
        travelMode: TravelMode = .walking,
        constraints: TourismDayConstraints = .none,
        plannedDate: Date? = nil
    ) -> [ScheduleItem] {
        let rhythm = policy.rhythm(for: pace)
        var result: [ScheduleItem] = []
        var currentMinute = max(rhythm.startMinute, constraints.earliestStartMinute ?? rhythm.startMinute)
        var lunchIncluded = false

        if let earliestStartMinute = constraints.earliestStartMinute,
           earliestStartMinute > rhythm.startMinute {
            result.append(
                ScheduleItem(
                    id: "\(day.index)-arrival-boundary",
                    timeText: "\(policy.clock(earliestStartMinute))后",
                    title: "抵达、接驳与安顿",
                    detail: constraints.startNote ?? "从抵达枢纽、前往住处并安顿好之后，再开始当天游览",
                    placeID: nil
                )
            )
        }

        for (index, stop) in day.stops.enumerated() {
            if index > 0 {
                let previous = day.stops[index - 1]
                if !lunchIncluded,
                   stop.interest != .food,
                   currentMinute >= rhythm.lunchStartMinute - 10 {
                    appendLunch(
                        to: &result,
                        dayIndex: day.index,
                        currentMinute: &currentMinute,
                        rhythm: rhythm
                    )
                    lunchIncluded = true
                }

                let travelMinutes = policy.estimatedTravelMinutes(
                    from: previous.coordinate,
                    to: stop.coordinate,
                    mode: travelMode
                ) + rhythm.transferBufferMinutes
                let travelStart = currentMinute
                currentMinute += travelMinutes
                result.append(
                    ScheduleItem(
                        id: "\(day.index)-transfer-\(index)",
                        timeText: rangeText(from: travelStart, to: currentMinute),
                        title: "前往\(stop.name)",
                        detail: "\(travelMode.title) · 含换乘、找路与进场缓冲，实际以地图路线为准",
                        placeID: nil
                    )
                )
            }

            if stop.interest == .food, !lunchIncluded {
                // When a restaurant is one of the selected stops, let it carry
                // the meal instead of adding a second, generic lunch block.
                currentMinute = max(currentMinute, 11 * 60 + 30)
                lunchIncluded = currentMinute <= 14 * 60 + 30
            } else if !lunchIncluded,
                      stop.interest != .night,
                      currentMinute >= rhythm.lunchStartMinute - 10 {
                appendLunch(
                    to: &result,
                    dayIndex: day.index,
                    currentMinute: &currentMinute,
                    rhythm: rhythm
                )
                lunchIncluded = true
            }

            if stop.interest == .night, currentMinute < rhythm.nightStartMinute {
                if !lunchIncluded {
                    currentMinute = max(currentMinute, rhythm.lunchStartMinute)
                    appendLunch(
                        to: &result,
                        dayIndex: day.index,
                        currentMinute: &currentMinute,
                        rhythm: rhythm
                    )
                    lunchIncluded = true
                }
                if currentMinute < rhythm.nightStartMinute {
                    let pauseStart = currentMinute
                    currentMinute = rhythm.nightStartMinute
                    result.append(
                        ScheduleItem(
                            id: "\(day.index)-night-pause",
                            timeText: rangeText(from: pauseStart, to: currentMinute),
                            title: "午后留白与晚餐",
                            detail: "不把白天硬塞满；可回住处休息，也可随天气临时调整",
                            placeID: nil
                        )
                    )
                }
            }

            let visitMinutes = policy.visitMinutes(for: stop, pace: pace)
            let openingState = policy.openingState(for: stop, on: plannedDate)
            let openingWindow: TourismPlanningPolicy.OpeningWindow? = if case let .open(window) = openingState {
                window
            } else {
                nil
            }
            if let openingWindow, currentMinute < openingWindow.startMinute {
                let pauseStart = currentMinute
                currentMinute = openingWindow.startMinute
                result.append(
                    ScheduleItem(
                        id: "\(day.index)-opening-pause-\(stop.id)",
                        timeText: rangeText(from: pauseStart, to: currentMinute),
                        title: "等候开门与附近慢逛",
                        detail: "按当前可读取的营业时段留白；出发前仍需复核临时调整",
                        placeID: nil
                    )
                )
            }
            let start = currentMinute
            currentMinute += visitMinutes
            let mealNote = stop.interest == .food && lunchIncluded ? " · 这一站兼作正餐" : ""
            let ticketNote = stop.ticketQuote.map {
                " · \($0.provider.title)\($0.priceText)（\($0.kind.title)）"
            } ?? ""
            let openingNote: String
            if case let .normallyClosed(note) = openingState {
                openingNote = " · \(note)"
            } else if let openingWindow {
                let dayLabel = plannedDate == nil ? "今日" : "计划日"
                openingNote = currentMinute > openingWindow.endMinute
                    ? " · 预计可能越过\(dayLabel)营业时段，请调整或复核"
                    : " · \(dayLabel)营业\(policy.clock(openingWindow.startMinute))–\(policy.clock(openingWindow.endMinute))，仍需复核"
            } else {
                openingNote = " · 开放与预约请复核"
            }
            result.append(
                ScheduleItem(
                    id: "\(day.index)-\(stop.id)",
                    timeText: rangeText(from: start, to: currentMinute),
                    title: stop.name,
                    detail: "\(stop.interest.visitIntroduction) · 预计停留\(policy.durationText(visitMinutes))\(mealNote)\(openingNote)\(ticketNote)",
                    placeID: stop.id
                )
            )
        }

        if !lunchIncluded, currentMinute >= rhythm.lunchStartMinute {
            appendLunch(
                to: &result,
                dayIndex: day.index,
                currentMinute: &currentMinute,
                rhythm: rhythm
            )
        }

        if let latestEndMinute = constraints.latestEndMinute {
            let isConflicted = currentMinute > latestEndMinute
            result.append(
                ScheduleItem(
                    id: "\(day.index)-departure-boundary",
                    timeText: "需在\(policy.clock(latestEndMinute))前",
                    title: isConflicted ? "返程前需要调整" : "离开游览区，前往返程枢纽",
                    detail: isConflicted
                        ? "当前游览预计到\(policy.clock(currentMinute))；\(constraints.endNote ?? "需为接驳和提前进站留出时间")"
                        : (constraints.endNote ?? "已为接驳和提前进站留出时间"),
                    placeID: nil
                )
            )
        }

        if let accommodation, constraints.latestEndMinute == nil {
            result.append(
                ScheduleItem(
                    id: "\(day.index)-hotel",
                    timeText: "\(policy.clock(currentMinute))后",
                    title: day.index == 0 ? "办理入住并休息" : "返回住宿",
                    detail: "\(accommodation.name) · 回程时间需按当天实时路线复核",
                    placeID: nil
                )
            )
        }
        return result
    }

    private func appendLunch(
        to result: inout [ScheduleItem],
        dayIndex: Int,
        currentMinute: inout Int,
        rhythm: TourismPlanningPolicy.DayRhythm
    ) {
        currentMinute = max(currentMinute, rhythm.lunchStartMinute)
        let start = currentMinute
        currentMinute += rhythm.lunchDurationMinutes
        result.append(
            ScheduleItem(
                id: "\(dayIndex)-lunch",
                timeText: rangeText(from: start, to: currentMinute),
                title: "午餐与休息",
                detail: "在相邻景点之间用餐，给排队、步行和体力恢复留出余量",
                placeID: nil
            )
        )
    }

    private func rangeText(from start: Int, to end: Int) -> String {
        "\(policy.clock(start))–\(policy.clock(end))"
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

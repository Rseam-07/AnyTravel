import Foundation
import MapKit
import UIKit

enum PlanExportFormat: String, Sendable {
    case pdf
    case calendar
    case pdfAndCalendar
}

struct PlanSharePayload: Identifiable {
    let id = UUID()
    let title: String
    let urls: [URL]
}

struct PlanExportDay: Sendable {
    let itinerary: ItineraryDay
    let date: Date?
    let schedule: [ScheduleItem]
    let routeSegments: [[Coordinate]]
}

struct PlanExportPayload: Sendable {
    let title: String
    let draft: TripDraft
    let days: [PlanExportDay]
    let accommodation: AccommodationOption?
    let outboundTransport: TransportOption?
    let returnTransport: TransportOption?
    let outboundTransfer: LocalTransferOption?
    let returnTransfer: LocalTransferOption?
    let expenses: [ExpenseLine]
    let generatedAt: Date

    var totalExpenseCNY: Int { expenses.reduce(0) { $0 + $1.amountCNY } }
    var confirmedExpenseCNY: Int { expenses.filter { $0.source == .confirmed }.reduce(0) { $0 + $1.amountCNY } }
    var unpricedComponents: [String] { Array(Set(expenses.flatMap(\.unpricedComponents))).sorted() }
}

enum PlanExportError: LocalizedError, Equatable {
    case noItinerary
    case missingDates
    case cannotCreateFile

    var errorDescription: String? {
        switch self {
        case .noItinerary: "行程还没有展开，暂时没有内容可以导出。"
        case .missingDates: "先补充出发日期，才能把每天的安排写进日历。"
        case .cannotCreateFile: "导出文件没有写好，请稍后再试。"
        }
    }
}

@MainActor
struct PlanExportService {
    private let exportRoot: URL

    init(exportRoot: URL? = nil) {
        self.exportRoot = exportRoot
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("AnyTravel Exports", isDirectory: true)
    }

    func export(
        _ format: PlanExportFormat,
        payload: PlanExportPayload,
        includeMap: Bool = true
    ) async throws -> [URL] {
        guard !payload.days.isEmpty else { throw PlanExportError.noItinerary }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        switch format {
        case .pdf:
            return [try await makePDF(payload: payload, includeMap: includeMap)]
        case .calendar:
            return [try makeCalendar(payload: payload)]
        case .pdfAndCalendar:
            let pdf = try await makePDF(payload: payload, includeMap: includeMap)
            let calendar = try makeCalendar(payload: payload)
            return [pdf, calendar]
        }
    }

    func makePDF(payload: PlanExportPayload, includeMap: Bool = true) async throws -> URL {
        guard !payload.days.isEmpty else { throw PlanExportError.noItinerary }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let url = exportURL(for: payload, pathExtension: "pdf")
        try? FileManager.default.removeItem(at: url)

        let mapImage = includeMap ? await makeMapImage(for: payload) : nil
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: payload.title.exportSafeText,
            kCGPDFContextAuthor as String: "AnyTravel · 折叠远方",
            kCGPDFContextCreator as String: "AnyTravel iOS"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        do {
            try renderer.writePDF(to: url) { context in
                let document = PlanPDFDocument(context: context, pageRect: pageRect, payload: payload)
                document.render(mapImage: mapImage)
            }
        } catch {
            throw PlanExportError.cannotCreateFile
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PlanExportError.cannotCreateFile
        }
        return url
    }

    func makeCalendar(payload: PlanExportPayload) throws -> URL {
        guard !payload.days.isEmpty else { throw PlanExportError.noItinerary }
        guard payload.days.allSatisfy({ $0.date != nil }) else { throw PlanExportError.missingDates }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let url = exportURL(for: payload, pathExtension: "ics")
        try? FileManager.default.removeItem(at: url)

        let calendar = Calendar.current
        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.calendar = Calendar(identifier: .gregorian)
        localFormatter.timeZone = calendar.timeZone
        localFormatter.dateFormat = "yyyyMMdd'T'HHmmss"

        let utcFormatter = DateFormatter()
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcFormatter.calendar = Calendar(identifier: .gregorian)
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//AnyTravel//Folded Horizon//ZH",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escapeCalendarText(payload.title.exportSafeText))",
            "X-WR-TIMEZONE:\(escapeCalendarText(calendar.timeZone.identifier))"
        ]

        for day in payload.days {
            guard let date = day.date else { continue }
            for item in day.schedule {
                guard let range = scheduleRange(item.timeText, on: date, calendar: calendar) else { continue }
                let place = item.placeID.flatMap { id in day.itinerary.stops.first(where: { $0.id == id }) }
                let location = place?.address ?? (item.title.contains("住宿") ? payload.accommodation?.address : nil)
                let uidSource = "\(payload.title)-\(day.itinerary.index)-\(item.id)"
                let uid = Data(uidSource.utf8).base64EncodedString()
                lines.append(contentsOf: [
                    "BEGIN:VEVENT",
                    "UID:\(uid)@anytravel.local",
                    "DTSTAMP:\(utcFormatter.string(from: payload.generatedAt))",
                    "DTSTART:\(localFormatter.string(from: range.start))",
                    "DTEND:\(localFormatter.string(from: range.end))",
                    "SUMMARY:\(escapeCalendarText(item.title.exportSafeText))",
                    "DESCRIPTION:\(escapeCalendarText((item.detail + "\n来自 AnyTravel · " + payload.title).exportSafeText))"
                ])
                if let location, !location.isEmpty {
                    lines.append("LOCATION:\(escapeCalendarText(location.exportSafeText))")
                }
                lines.append("END:VEVENT")
            }
        }
        lines.append("END:VCALENDAR")

        let contents = lines.map(foldCalendarLine).joined(separator: "\r\n") + "\r\n"
        do {
            try Data(contents.utf8).write(to: url, options: .atomic)
        } catch {
            throw PlanExportError.cannotCreateFile
        }
        return url
    }

    private func exportURL(for payload: PlanExportPayload, pathExtension: String) -> URL {
        let safeName = payload.title
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return exportRoot
            .appendingPathComponent("AnyTravel-\(safeName.isEmpty ? "旅行方案" : safeName)")
            .appendingPathExtension(pathExtension)
    }

    private func makeMapImage(for payload: PlanExportPayload) async -> UIImage? {
        let stopCoordinates = payload.days.flatMap { $0.itinerary.stops.map(\.coordinate) }
        let coordinates = stopCoordinates + [payload.accommodation?.coordinate].compactMap { $0 }
        guard !coordinates.isEmpty else { return nil }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.45, 0.025),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.45, 0.025)
        )
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 510, height: 238)
        options.scale = 2
        options.mapType = .standard
        options.showsBuildings = true

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let imageFormat = UIGraphicsImageRendererFormat()
        imageFormat.scale = 2
        return UIGraphicsImageRenderer(size: options.size, format: imageFormat).image { rendererContext in
            snapshot.image.draw(at: .zero)
            let context = rendererContext.cgContext

            for day in payload.days {
                let color = PlanPDFPalette.dayColor(day.itinerary.index)
                for segment in day.routeSegments where segment.count > 1 {
                    let path = UIBezierPath()
                    for (index, coordinate) in segment.enumerated() {
                        let point = snapshot.point(for: coordinate.clLocationCoordinate)
                        index == 0 ? path.move(to: point) : path.addLine(to: point)
                    }
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    UIColor.white.withAlphaComponent(0.92).setStroke()
                    path.lineWidth = 8
                    path.stroke()
                    color.setStroke()
                    path.lineWidth = 4
                    path.stroke()
                }
            }

            for day in payload.days {
                for (index, stop) in day.itinerary.stops.enumerated() {
                    drawMapPin(
                        at: snapshot.point(for: stop.coordinate.clLocationCoordinate),
                        text: "\(day.itinerary.index + 1).\(index + 1)",
                        color: PlanPDFPalette.dayColor(day.itinerary.index),
                        context: context
                    )
                }
            }
            if let accommodation = payload.accommodation {
                drawMapPin(
                    at: snapshot.point(for: accommodation.coordinate.clLocationCoordinate),
                    text: "宿",
                    color: PlanPDFPalette.route,
                    context: context
                )
            }
        }
    }

    private func drawMapPin(at point: CGPoint, text: String, color: UIColor, context: CGContext) {
        let circle = CGRect(x: point.x - 13, y: point.y - 13, width: 26, height: 26)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.22).cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: circle.insetBy(dx: -2, dy: -2))
        context.restoreGState()
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: circle)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: text.count > 2 ? 7.5 : 10, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: centeredParagraphStyle()
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(in: CGRect(x: circle.minX, y: circle.midY - 6, width: circle.width, height: 14))
    }

    private func scheduleRange(
        _ text: String,
        on date: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let expression = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression?.matches(in: text, range: range) ?? []
        guard let first = matches.first,
              let hourRange = Range(first.range(at: 1), in: text),
              let minuteRange = Range(first.range(at: 2), in: text),
              let hour = Int(text[hourRange]),
              let minute = Int(text[minuteRange]),
              let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else { return nil }

        if matches.count > 1,
           let endHourRange = Range(matches[1].range(at: 1), in: text),
           let endMinuteRange = Range(matches[1].range(at: 2), in: text),
           let endHour = Int(text[endHourRange]),
           let endMinute = Int(text[endMinuteRange]),
           let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: date) {
            return (start, end > start ? end : calendar.date(byAdding: .day, value: 1, to: end) ?? end)
        }
        return (start, calendar.date(byAdding: .hour, value: 1, to: start) ?? start)
    }

    private func escapeCalendarText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func foldCalendarLine(_ line: String) -> String {
        var folded: [String] = []
        var current = ""
        for scalar in line.unicodeScalars {
            let part = String(scalar)
            if current.utf8.count + part.utf8.count > 74 {
                folded.append(current)
                current = " " + part
            } else {
                current += part
            }
        }
        if !current.isEmpty { folded.append(current) }
        return folded.joined(separator: "\r\n")
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }
}

@MainActor
private final class PlanPDFDocument {
    private let context: UIGraphicsPDFRendererContext
    private let pageRect: CGRect
    private let payload: PlanExportPayload
    private let margin: CGFloat = 42
    private var cursorY: CGFloat = 0
    private var pageNumber = 0

    private var contentWidth: CGFloat { pageRect.width - margin * 2 }
    private var contentBottom: CGFloat { pageRect.height - 48 }

    init(context: UIGraphicsPDFRendererContext, pageRect: CGRect, payload: PlanExportPayload) {
        self.context = context
        self.pageRect = pageRect
        self.payload = payload
    }

    func render(mapImage: UIImage?) {
        beginPage()
        drawHero()
        drawMap(mapImage)
        for day in payload.days { draw(day: day) }
        drawAccommodation()
        drawTransport()
        drawExpenses()
        drawFooter()
    }

    private func beginPage() {
        if pageNumber > 0 { drawFooter() }
        context.beginPage()
        pageNumber += 1
        context.cgContext.setFillColor(PlanPDFPalette.paper.cgColor)
        context.cgContext.fill(pageRect)
        if pageNumber == 1 {
            cursorY = 42
        } else {
            drawText(
                payload.title.exportSafeText,
                font: .systemFont(ofSize: 10, weight: .semibold),
                color: PlanPDFPalette.routeDark,
                maxWidth: contentWidth,
                at: CGPoint(x: margin, y: 28)
            )
            context.cgContext.setFillColor(PlanPDFPalette.route.withAlphaComponent(0.24).cgColor)
            context.cgContext.fill(CGRect(x: margin, y: 47, width: contentWidth, height: 1))
            cursorY = 64
        }
    }

    private func ensureSpace(_ height: CGFloat) {
        if cursorY + height > contentBottom { beginPage() }
    }

    private func drawHero() {
        drawText(
            "ANYTRAVEL / 折叠远方",
            font: .systemFont(ofSize: 10, weight: .bold),
            color: PlanPDFPalette.route,
            maxWidth: contentWidth,
            at: CGPoint(x: margin, y: cursorY),
            letterSpacing: 1.2
        )
        cursorY += 24
        cursorY += drawText(
            payload.title.exportSafeText,
            font: .systemFont(ofSize: 28, weight: .bold),
            color: PlanPDFPalette.ink,
            maxWidth: contentWidth,
            at: CGPoint(x: margin, y: cursorY),
            lineSpacing: 3
        )
        cursorY += 8
        cursorY += drawText(
            "把要去的地方，折成一页随身的远方。",
            font: .systemFont(ofSize: 12, weight: .medium),
            color: PlanPDFPalette.secondaryInk,
            maxWidth: contentWidth,
            at: CGPoint(x: margin, y: cursorY)
        )
        cursorY += 16

        let dateText: String
        if let start = payload.draft.logistics.startDate, let end = payload.draft.logistics.endDate {
            dateText = "\(formatDate(start)) - \(formatDate(end))"
        } else {
            dateText = "日期稍后决定"
        }
        let metadata = [
            dateText,
            "\(payload.draft.logistics.travelers) 人同行",
            "¥\(payload.draft.budgetPerPerson.formatted(.number.grouping(.automatic))) / 人",
            "\(payload.draft.pace.title)节奏"
        ].joined(separator: "   ·   ")
        let height = textHeight(metadata, font: .systemFont(ofSize: 10, weight: .semibold), width: contentWidth - 24)
        let card = CGRect(x: margin, y: cursorY, width: contentWidth, height: height + 20)
        drawRoundedRect(card, radius: 13, fill: PlanPDFPalette.mint)
        drawText(
            metadata,
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: PlanPDFPalette.routeDark,
            maxWidth: card.width - 24,
            at: CGPoint(x: card.minX + 12, y: card.minY + 10)
        )
        cursorY = card.maxY + 18
    }

    private func drawMap(_ image: UIImage?) {
        ensureSpace(260)
        drawSectionTitle("地图总览", subtitle: "路线只绘制 Apple Maps 已返回的路段")
        let mapRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: 220)
        context.cgContext.saveGState()
        UIBezierPath(roundedRect: mapRect, cornerRadius: 17).addClip()
        if let image {
            image.draw(in: mapRect)
        } else {
            context.cgContext.setFillColor(PlanPDFPalette.mint.cgColor)
            context.cgContext.fill(mapRect)
            drawText(
                "地图快照暂未取得，地点与地址仍完整列在下方。",
                font: .systemFont(ofSize: 11, weight: .medium),
                color: PlanPDFPalette.secondaryInk,
                maxWidth: mapRect.width - 40,
                at: CGPoint(x: mapRect.minX + 20, y: mapRect.midY - 8),
                alignment: .center
            )
        }
        context.cgContext.restoreGState()
        cursorY = mapRect.maxY + 20
    }

    private func draw(day: PlanExportDay) {
        let date = day.date.map { " · \(formatDateWithWeekday($0))" } ?? ""
        drawSectionTitle("\(day.itinerary.title)\(date)", subtitle: "默认给脚步留一点余地")
        for item in day.schedule {
            let place = item.placeID.flatMap { id in day.itinerary.stops.first(where: { $0.id == id }) }
            let detail = [item.detail.exportSafeText, place?.address.exportSafeText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            drawScheduleRow(
                time: item.timeText.exportSafeText,
                title: item.title.exportSafeText,
                detail: detail,
                continuationTitle: "\(day.itinerary.title) · 续"
            )
        }
        cursorY += 8
    }

    private func drawAccommodation() {
        drawSectionTitle("住在哪里", subtitle: "位置、价格与抵达的路放在一起看")
        guard let accommodation = payload.accommodation else {
            drawInfoCard(title: "住宿暂未选择", detail: "这部分可以继续留白，等路线更清楚时再决定。", accent: PlanPDFPalette.route)
            return
        }
        let quote = bestQuote(accommodation.quotes)
        let price = quote.map { "\($0.priceText) · \($0.provider.title) · \($0.kind.title)" } ?? "价格等待复核"
        drawInfoCard(
            title: accommodation.name.exportSafeText,
            detail: "\(accommodation.address.exportSafeText)\n到景点平均 \(accommodation.attractionDistanceMeters.anyTravelDistanceText) · \(price.exportSafeText)",
            accent: PlanPDFPalette.route
        )
    }

    private func drawTransport() {
        drawSectionTitle("怎样抵达，也怎样回来", subtitle: "班次与接驳分别保留自己的来源")
        drawTransportCard(payload.outboundTransport, label: "去程大交通")
        drawTransferCard(payload.outboundTransfer, label: "抵达接驳")
        drawTransportCard(payload.returnTransport, label: "返程大交通")
        drawTransferCard(payload.returnTransfer, label: "返程接驳")
    }

    private func drawExpenses() {
        drawSectionTitle("费用落款", subtitle: "每一笔都留下口径，最后仍以结算页为准")
        for line in payload.expenses {
            let price = "\(line.source == .confirmed ? "" : "约 ")¥\(line.amountCNY.formatted(.number.grouping(.automatic)))"
            let pending = line.unpricedComponents.isEmpty ? "" : " · 另待确认：\(line.unpricedComponents.joined(separator: "、"))"
            drawExpenseRow(
                title: line.title.exportSafeText,
                detail: "\(line.detail.exportSafeText) · \(line.source.title)\(pending)",
                price: price,
                continuationTitle: "费用落款 · 续"
            )
        }
        ensureSpace(62)
        let totalRect = CGRect(x: margin, y: cursorY + 4, width: contentWidth, height: 52)
        drawRoundedRect(totalRect, radius: 15, fill: PlanPDFPalette.route)
        drawText(
            "当前预算轮廓",
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: .white,
            maxWidth: 180,
            at: CGPoint(x: totalRect.minX + 16, y: totalRect.minY + 18)
        )
        drawText(
            "约 ¥\(payload.totalExpenseCNY.formatted(.number.grouping(.automatic)))",
            font: .monospacedDigitSystemFont(ofSize: 18, weight: .bold),
            color: .white,
            maxWidth: 220,
            at: CGPoint(x: totalRect.maxX - 236, y: totalRect.minY + 14),
            alignment: .right
        )
        cursorY = totalRect.maxY + 8
        if !payload.unpricedComponents.isEmpty {
            drawText(
                "已确认支出 ¥\(payload.confirmedExpenseCNY.formatted(.number.grouping(.automatic))) · 另待确认：\(payload.unpricedComponents.joined(separator: "、"))".exportSafeText,
                font: .systemFont(ofSize: 8.5, weight: .regular),
                color: PlanPDFPalette.secondaryInk,
                maxWidth: contentWidth,
                at: CGPoint(x: margin, y: cursorY)
            )
            cursorY += 18
        }
    }

    private func drawSectionTitle(_ title: String, subtitle: String) {
        ensureSpace(52)
        context.cgContext.setFillColor(PlanPDFPalette.route.cgColor)
        context.cgContext.fill(CGRect(x: margin, y: cursorY + 1, width: 4, height: 31))
        drawText(
            title.exportSafeText,
            font: .systemFont(ofSize: 15, weight: .bold),
            color: PlanPDFPalette.ink,
            maxWidth: contentWidth - 14,
            at: CGPoint(x: margin + 13, y: cursorY)
        )
        drawText(
            subtitle.exportSafeText,
            font: .systemFont(ofSize: 8.5, weight: .regular),
            color: PlanPDFPalette.secondaryInk,
            maxWidth: contentWidth - 14,
            at: CGPoint(x: margin + 13, y: cursorY + 20)
        )
        cursorY += 43
    }

    private func drawScheduleRow(
        time: String,
        title: String,
        detail: String,
        continuationTitle: String
    ) {
        let textWidth = contentWidth - 112
        let titleHeight = textHeight(title, font: .systemFont(ofSize: 11.5, weight: .bold), width: textWidth)
        let detailHeight = textHeight(detail, font: .systemFont(ofSize: 8.8), width: textWidth, lineSpacing: 1.5)
        let height = max(titleHeight + detailHeight + 24, 58)
        if cursorY + height + 7 > contentBottom {
            beginPage()
            drawSectionTitle(continuationTitle, subtitle: "上一页的脚步在这里继续")
        }
        let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: height)
        drawRoundedRect(rect, radius: 13, fill: PlanPDFPalette.card)
        drawText(
            time,
            font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            color: PlanPDFPalette.routeDark,
            maxWidth: 82,
            at: CGPoint(x: rect.minX + 13, y: rect.minY + 16)
        )
        drawText(
            title,
            font: .systemFont(ofSize: 11.5, weight: .bold),
            color: PlanPDFPalette.ink,
            maxWidth: textWidth,
            at: CGPoint(x: rect.minX + 102, y: rect.minY + 10)
        )
        drawText(
            detail,
            font: .systemFont(ofSize: 8.8),
            color: PlanPDFPalette.secondaryInk,
            maxWidth: textWidth,
            at: CGPoint(x: rect.minX + 102, y: rect.minY + 14 + titleHeight),
            lineSpacing: 1.5
        )
        cursorY = rect.maxY + 7
    }

    private func drawInfoCard(title: String, detail: String, accent: UIColor) {
        let titleHeight = textHeight(title, font: .systemFont(ofSize: 12, weight: .bold), width: contentWidth - 34)
        let detailHeight = textHeight(detail, font: .systemFont(ofSize: 9), width: contentWidth - 34, lineSpacing: 1.5)
        let height = titleHeight + detailHeight + 30
        ensureSpace(height + 8)
        let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: height)
        drawRoundedRect(rect, radius: 14, fill: PlanPDFPalette.card)
        context.cgContext.setFillColor(accent.cgColor)
        context.cgContext.fill(CGRect(x: rect.minX, y: rect.minY, width: 5, height: rect.height))
        drawText(title, font: .systemFont(ofSize: 12, weight: .bold), color: PlanPDFPalette.ink, maxWidth: rect.width - 34, at: CGPoint(x: rect.minX + 17, y: rect.minY + 10))
        drawText(detail, font: .systemFont(ofSize: 9), color: PlanPDFPalette.secondaryInk, maxWidth: rect.width - 34, at: CGPoint(x: rect.minX + 17, y: rect.minY + 14 + titleHeight), lineSpacing: 1.5)
        cursorY = rect.maxY + 8
    }

    private func drawTransportCard(_ option: TransportOption?, label: String) {
        guard let option else {
            drawInfoCard(title: label, detail: "暂未选择，可以稍后补上。", accent: PlanPDFPalette.warm)
            return
        }
        let time = transportTime(option)
        let quote = bestQuote(option.quotes)
        let price = quote.map { "\($0.priceText) · \($0.provider.title) · \($0.kind.title)" } ?? "班次或价格等待复核"
        drawInfoCard(
            title: "\(label) · \(option.title.exportSafeText)",
            detail: "\(option.originName.exportSafeText) → \(option.destinationName.exportSafeText)\(time)\n\(price.exportSafeText)",
            accent: PlanPDFPalette.warm
        )
    }

    private func drawTransferCard(_ option: LocalTransferOption?, label: String) {
        guard let option else { return }
        let cost = option.estimatedCostCNY == 0 ? "无需费用" : "约 ¥\(option.estimatedCostCNY)"
        drawInfoCard(
            title: "\(label) · \(option.mode.title)",
            detail: "\(option.originName.exportSafeText) → \(option.destinationName.exportSafeText)\n约 \(option.durationMinutes) 分钟 · \(option.distanceMeters.anyTravelDistanceText) · \(cost) · \(option.routeKind.title)",
            accent: PlanPDFPalette.route
        )
    }

    private func drawExpenseRow(
        title: String,
        detail: String,
        price: String,
        continuationTitle: String
    ) {
        let detailWidth = contentWidth - 155
        let detailHeight = textHeight(detail, font: .systemFont(ofSize: 8.3), width: detailWidth, lineSpacing: 1.2)
        let height = max(detailHeight + 30, 52)
        if cursorY + height + 6 > contentBottom {
            beginPage()
            drawSectionTitle(continuationTitle, subtitle: "金额口径与上一页保持一致")
        }
        let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: height)
        drawRoundedRect(rect, radius: 12, fill: PlanPDFPalette.card)
        drawText(title, font: .systemFont(ofSize: 10.5, weight: .semibold), color: PlanPDFPalette.ink, maxWidth: detailWidth, at: CGPoint(x: rect.minX + 13, y: rect.minY + 9))
        drawText(detail, font: .systemFont(ofSize: 8.3), color: PlanPDFPalette.secondaryInk, maxWidth: detailWidth, at: CGPoint(x: rect.minX + 13, y: rect.minY + 25), lineSpacing: 1.2)
        drawText(price, font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold), color: PlanPDFPalette.warm, maxWidth: 116, at: CGPoint(x: rect.maxX - 129, y: rect.midY - 7), alignment: .right)
        cursorY = rect.maxY + 6
    }

    private func drawFooter() {
        let footer = "AnyTravel · 折叠远方   |   价格、开放时间与路线请在出发前复核   |   \(pageNumber)"
        drawText(
            footer,
            font: .systemFont(ofSize: 7.5),
            color: PlanPDFPalette.secondaryInk.withAlphaComponent(0.78),
            maxWidth: contentWidth,
            at: CGPoint(x: margin, y: pageRect.height - 28),
            alignment: .center
        )
    }

    @discardableResult
    private func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        maxWidth: CGFloat,
        at point: CGPoint,
        lineSpacing: CGFloat = 0,
        alignment: NSTextAlignment = .left,
        letterSpacing: CGFloat = 0
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
            .kern: letterSpacing
        ]
        let attributed = NSAttributedString(string: text.exportSafeText, attributes: attributes)
        let height = ceil(attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
        attributed.draw(in: CGRect(x: point.x, y: point.y, width: maxWidth, height: height + 2))
        return height
    }

    private func textHeight(
        _ text: String,
        font: UIFont,
        width: CGFloat,
        lineSpacing: CGFloat = 0
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        return ceil(NSAttributedString(
            string: text.exportSafeText,
            attributes: [.font: font, .paragraphStyle: style]
        ).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
    }

    private func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: UIColor) {
        context.cgContext.setFillColor(fill.cgColor)
        context.cgContext.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        context.cgContext.fillPath()
    }

    private func bestQuote(_ quotes: [ProviderQuote]) -> ProviderQuote? {
        quotes
            .filter { $0.amountCNY != nil && $0.kind != .demo }
            .min { ($0.amountCNY ?? .max) < ($1.amountCNY ?? .max) }
            ?? quotes.first(where: { $0.amountCNY != nil })
    }

    private func transportTime(_ option: TransportOption) -> String {
        let departure = option.departureTime?.formatted(date: .omitted, time: .shortened)
        let arrival = option.arrivalTime?.formatted(date: .omitted, time: .shortened)
        let duration = option.durationMinutes.map { "约 \($0) 分钟" }
        let pieces = [departure.flatMap { value in arrival.map { " · \(value)-\($0)" } }, duration.map { " · \($0)" }]
            .compactMap { $0 }
        return pieces.joined()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private func formatDateWithWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}

private enum PlanPDFPalette {
    static let paper = UIColor(red: 0.985, green: 0.978, blue: 0.952, alpha: 1)
    static let card = UIColor(red: 0.965, green: 0.965, blue: 0.935, alpha: 1)
    static let mint = UIColor(red: 0.90, green: 0.955, blue: 0.925, alpha: 1)
    static let ink = UIColor(red: 0.075, green: 0.105, blue: 0.095, alpha: 1)
    static let secondaryInk = UIColor(red: 0.32, green: 0.37, blue: 0.35, alpha: 1)
    static let route = UIColor(red: 0.05, green: 0.47, blue: 0.42, alpha: 1)
    static let routeDark = UIColor(red: 0.02, green: 0.34, blue: 0.31, alpha: 1)
    static let warm = UIColor(red: 0.96, green: 0.31, blue: 0.16, alpha: 1)

    static func dayColor(_ index: Int) -> UIColor {
        [route, warm, UIColor.systemIndigo, UIColor.systemPink, UIColor.systemBlue][index % 5]
    }
}

private extension String {
    var exportSafeText: String {
        replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
    }
}

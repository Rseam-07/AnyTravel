import CoreGraphics
import XCTest
@testable import AnyTravel

final class PlanExportTests: XCTestCase {
    @MainActor
    func testCreatesReadableMultipagePDFAndImportableCalendar() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = makePayload(includeDates: true)
        let service = PlanExportService(exportRoot: directory)

        let urls = try await service.export(.pdfAndCalendar, payload: payload, includeMap: false)
        let pdfURL = try XCTUnwrap(urls.first(where: { $0.pathExtension == "pdf" }))
        let calendarURL = try XCTUnwrap(urls.first(where: { $0.pathExtension == "ics" }))
        let pdfData = try Data(contentsOf: pdfURL)
        let pdf = try XCTUnwrap(CGPDFDocument(pdfURL as CFURL))
        let calendarText = try String(contentsOf: calendarURL, encoding: .utf8)

        XCTAssertEqual(String(data: pdfData.prefix(4), encoding: .ascii), "%PDF")
        XCTAssertGreaterThanOrEqual(pdf.numberOfPages, 2)
        XCTAssertTrue(calendarText.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(calendarText.contains("SUMMARY:拙政园"))
        XCTAssertTrue(calendarText.contains("LOCATION:江苏省苏州市姑苏区东北街178号"))
        XCTAssertEqual(calendarText.components(separatedBy: "BEGIN:VEVENT").count - 1, 15)
        XCTAssertTrue(
            calendarText.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 },
            "iCalendar lines must be folded to 75 octets or fewer"
        )

        let pdfAttachment = XCTAttachment(contentsOfFile: pdfURL)
        pdfAttachment.name = "AnyTravel 完整旅行方案"
        pdfAttachment.lifetime = .keepAlways
        add(pdfAttachment)

        let calendarAttachment = XCTAttachment(contentsOfFile: calendarURL)
        calendarAttachment.name = "AnyTravel 行程日历"
        calendarAttachment.lifetime = .keepAlways
        add(calendarAttachment)
    }

    @MainActor
    func testCalendarExportRequiresAStartDateButPDFDoesNot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = makePayload(includeDates: false)
        let service = PlanExportService(exportRoot: directory)

        let pdf = try await service.export(.pdf, payload: payload, includeMap: false)
        XCTAssertEqual(pdf.first?.pathExtension, "pdf")
        XCTAssertThrowsError(try service.makeCalendar(payload: payload)) { error in
            XCTAssertEqual(error as? PlanExportError, .missingDates)
        }
    }

    @MainActor
    private func makePayload(includeDates: Bool) -> PlanExportPayload {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!
        var logistics = TripLogistics()
        logistics.origin = "上海"
        logistics.startDate = includeDates ? startDate : nil
        logistics.endDate = includeDates ? calendar.date(byAdding: .day, value: 2, to: startDate) : nil
        logistics.travelers = 2
        let draft = TripDraft(destination: "苏州", dayCount: 3, budgetPerPerson: 3_000, pace: .relaxed, logistics: logistics)

        let hotel = AccommodationOption(
            name: "苏州吴宫泛太平洋酒店",
            address: "江苏省苏州市姑苏区新市路388号",
            coordinate: Coordinate(latitude: 31.2860, longitude: 120.6220),
            attractionDistanceMeters: 3_200,
            quotes: [
                ProviderQuote(
                    provider: .rollingGo,
                    amountCNY: 468,
                    unit: .perNight,
                    kind: .live,
                    capturedAt: startDate,
                    note: "测试报价"
                )
            ]
        )
        let station = AccessPoint(
            name: "苏州站",
            coordinate: Coordinate(latitude: 31.3302, longitude: 120.6060),
            kind: .rail
        )
        let outbound = TransportOption(
            mode: .train,
            title: "G7008 · 上海→苏州",
            originName: "上海",
            destinationName: "苏州",
            durationMinutes: 32,
            departureTime: startDate,
            arrivalTime: startDate.addingTimeInterval(32 * 60),
            arrivalAccessPoint: station,
            quotes: [
                ProviderQuote(provider: .railway12306, amountCNY: 39, unit: .perPerson, kind: .live, capturedAt: startDate, note: "二等座")
            ]
        )
        let returnTrip = TransportOption(
            mode: .train,
            title: "G7028 · 苏州→上海",
            originName: "苏州",
            destinationName: "上海",
            direction: .returnTrip,
            durationMinutes: 32,
            departureTime: calendar.date(byAdding: .day, value: 2, to: startDate)?.addingTimeInterval(8 * 60 * 60),
            arrivalTime: calendar.date(byAdding: .day, value: 2, to: startDate)?.addingTimeInterval(8.5 * 60 * 60),
            arrivalAccessPoint: station,
            quotes: [
                ProviderQuote(provider: .railway12306, amountCNY: 40, unit: .perPerson, kind: .live, capturedAt: startDate, note: "二等座")
            ]
        )
        let outboundTransfer = LocalTransferOption(
            direction: .outbound,
            mode: .taxi,
            originName: "苏州站",
            destinationName: hotel.name,
            durationMinutes: 18,
            distanceMeters: 6_980,
            estimatedCostCNY: 32,
            routeKind: .appleMaps,
            costNote: "按里程估算"
        )
        let returnTransfer = LocalTransferOption(
            direction: .returnTrip,
            mode: .publicTransit,
            originName: hotel.name,
            destinationName: "苏州站",
            durationMinutes: 30,
            distanceMeters: 6_800,
            estimatedCostCNY: 4,
            routeKind: .distanceEstimate,
            costNote: "出发前复核"
        )

        let placeTemplates: [(String, String, Coordinate, TripInterest)] = [
            ("拙政园", "江苏省苏州市姑苏区东北街178号", Coordinate(latitude: 31.3265, longitude: 120.6251), .gardens),
            ("苏州博物馆", "江苏省苏州市姑苏区东北街204号", Coordinate(latitude: 31.3240, longitude: 120.6240), .culture),
            ("平江路", "江苏省苏州市姑苏区平江路", Coordinate(latitude: 31.3150, longitude: 120.6290), .food)
        ]
        let days = (0..<3).map { index -> PlanExportDay in
            let stops = placeTemplates.map { template in
                TravelPlace(name: template.0, address: template.1, coordinate: template.2, interest: template.3)
            }
            let itinerary = ItineraryDay(index: index, stops: stops)
            return PlanExportDay(
                itinerary: itinerary,
                date: includeDates ? calendar.date(byAdding: .day, value: index, to: startDate) : nil,
                schedule: ScheduleBuilder().build(for: itinerary, pace: .balanced, accommodation: hotel),
                routeSegments: []
            )
        }
        let expenses = ExpensePlanner().buildLines(
            draft: draft,
            accommodation: hotel,
            transport: outbound,
            returnTransport: returnTrip,
            outboundTransfer: outboundTransfer,
            returnTransfer: returnTransfer
        )
        return PlanExportPayload(
            title: "苏州 · 3天旅行方案",
            draft: draft,
            days: days,
            accommodation: hotel,
            outboundTransport: outbound,
            returnTransport: returnTrip,
            outboundTransfer: outboundTransfer,
            returnTransfer: returnTransfer,
            expenses: expenses,
            generatedAt: startDate
        )
    }
}

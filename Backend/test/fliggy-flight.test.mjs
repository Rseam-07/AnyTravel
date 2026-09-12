import test from "node:test";
import assert from "node:assert/strict";
import { FliggyFlightAdapter, flightCityCode, parseFlightPage, searchFlightPage } from "../src/adapters/fliggy-flight.mjs";

const fixture = { ret: ["SUCCESS::成功"], data: { success: true, items: [{ itemType: "DIRECT", itemDatas: [
  { bestPrice: "455", flightName: "3U3358", depTime: "23:00", arrTime: "01:30", duration: 150, depAirportName: "宁波栎社", arrAirportName: "天津滨海" },
  { bestPrice: "0", flightName: "invalid", depTime: "09:00", arrTime: "12:00" }
] }] } };

test("flight parser rejects zero, invalid clocks and unsuccessful envelopes", () => {
  assert.equal(parseFlightPage(fixture).offers.length, 1);
  assert.equal(parseFlightPage(fixture).lowestPrice, 455);
  assert.equal(parseFlightPage({ ...fixture, ret: ["FAIL_SYS_USER_VALIDATE"] }), null);
  const changed = structuredClone(fixture); changed.data.items[0].itemDatas[0].depTime = "29:00";
  assert.equal(parseFlightPage(changed).offers.length, 0);
});

test("current listing schema keeps cents, tax, terminals and overnight transfer legs correct", async () => {
  const listing = { ret: ["SUCCESS::调用成功"], data: { success: true, lowestPrice: 559, items: [{ itemType: "FLIGHT_TRANSFER", data: [{
    priceInfo: { adultPrice: 55900, adultTax: 21000, adultTotalPrice: 76900, childPrice: 10000 },
    flightInfos: [{ depTime: "2026-09-14 20:55:00", arrTime: "2026-09-15 09:10:00", duration: 735,
      depAirportName: "栎社", arrAirportName: "滨海", depTerm: "T2", arrTerm: "T2",
      transferTime: 535, transferCityNames: ["大连"],
      flightSegments: [{ marketingFlightNo: "9C7131" }, { marketingFlightNo: "HU7659" }]
    }]
  }] }] } };
  const parsed = parseFlightPage(listing);
  assert.equal(parsed.lowestPrice, 769);
  assert.equal(parsed.offers[0].price, 769);
  const adapter = new FliggyFlightAdapter({ search: async () => parsed });
  const { options } = await adapter.search({ origin: "宁波", destination: "天津", departureDate: "2026-09-14", modes: ["flight"] });
  assert.equal(options[0].amountCNY, 769);
  assert.equal(options[0].arrivalTime, "2026-09-15T09:10:00+08:00");
  assert.equal(options[0].serviceNumber, "9C7131 / HU7659");
  assert.equal(options[0].originName, "栎社 T2");
  assert.match(options[0].fareName, /大连中转.*含税/);
});

test("return failure preserves outbound price, true date, overnight arrival and booking URL", async () => {
  const adapter = new FliggyFlightAdapter({ search: async journey => {
    if (journey.direction === "return") throw new Error("upstream");
    return parseFlightPage(fixture);
  }, now: () => new Date("2026-09-05T00:00:00Z") });
  const result = await adapter.search({ origin: "宁波", destination: "天津", departureDate: "2026-09-08", returnDate: "2026-09-10", modes: ["flight"] });
  assert.equal(result.options.length, 1);
  assert.equal(result.options[0].amountCNY, 455);
  assert.equal(result.options[0].arrivalTime, "2026-09-08T17:30:00.000Z");
  assert.equal(new URL(result.options[0].bookingURL).searchParams.get("depDate"), "2026-09-08");
  assert.equal(result.diagnostics[1].status, "failed");
});

test("preserves provider dates and explains a transfer instead of presenting it as a direct flight", async () => {
  const liveLike = { ret: ["SUCCESS::成功"], data: { success: true, items: [{ itemType: "TRANSFER", itemDatas: [{
    bestPrice: "529",
    flightName: "AQ1038",
    depTime: "2026-09-12 22:50",
    arrTime: "2026-09-13 08:40",
    duration: 590,
    depAirportName: "栎社机场",
    arrAirportName: "苏南硕放机场",
    transferInfo: {
      transferCityName: "广州",
      transferFlightNo: "AQ1055",
      transferStopTime: "5小时15分"
    }
  }] }] } };
  const parsed = parseFlightPage(liveLike);
  assert.equal(parsed.offers[0].departureDateTime, "2026-09-12T22:50:00+08:00");
  assert.equal(parsed.offers[0].arrivalDateTime, "2026-09-13T08:40:00+08:00");

  const adapter = new FliggyFlightAdapter({
    search: async () => parsed,
    now: () => new Date("2026-09-06T00:00:00Z")
  });
  const result = await adapter.search({
    origin: "宁波",
    destination: "苏州",
    departureDate: "2026-09-12",
    modes: ["flight"]
  });
  const option = result.options[0];
  assert.equal(option.serviceNumber, "AQ1038 / AQ1055");
  assert.equal(option.departureTime, "2026-09-12T22:50:00+08:00");
  assert.equal(option.arrivalTime, "2026-09-13T08:40:00+08:00");
  assert.equal(option.durationMinutes, 590);
  assert.match(option.availability, /广州中转 · 停留5小时15分/);
});

test("public handshake only retries token bootstrap and stops at human verification", async () => {
  let attempts = 0;
  const result = await searchFlightPage({ from: "NGB", to: "TSN", date: "2026-09-08" }, { fetchImpl: async (_url, options) => {
    attempts++;
    if (attempts === 1) return new Response(JSON.stringify({ ret: ["FAIL_SYS_TOKEN_EXOIRED"] }), { headers: { "set-cookie": "_m_h5_tk=anonymous_123; Path=/; Secure" } });
    assert.match(options.headers.cookie, /_m_h5_tk=anonymous_123/);
    return Response.json(fixture);
  } });
  assert.equal(result.offers[0].price, 455);
  assert.equal(attempts, 2);
  attempts = 0;
  await assert.rejects(searchFlightPage({ from: "NGB", to: "TSN", date: "2026-09-08" }, { fetchImpl: async () => {
    attempts++; return Response.json({ ret: ["FAIL_SYS_USER_VALIDATE"] });
  } }));
  assert.equal(attempts, 1);
  assert.equal(flightCityCode("苏州市"), "WUX");
  assert.equal(flightCityCode("未知村落"), null);
});

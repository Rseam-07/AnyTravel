import test from "node:test";
import assert from "node:assert/strict";
import { AccorOfficialAdapter } from "../src/adapters/accor-official.mjs";
import { HiltonOfficialAdapter } from "../src/adapters/hilton-official.mjs";
import { normalizeChildrenAges } from "../src/quote-service.mjs";
import { officialTicketQuote } from "../src/official-ticket-policies.mjs";
import { searchQunarTicketQuotes } from "../src/qunar-ticket-service.mjs";
import { parseCtripPublicFlights, CtripPublicFlightAdapter } from "../src/adapters/ctrip-public-flight.mjs";

test("official hotel adapters retain the Worker global receiver", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async function () { assert.equal(this, globalThis); return Response.json({ hits: [], data: { hotels: [] } }); };
  try {
    const request = { destination: "北京", checkIn: "2026-10-06", checkOut: "2026-10-08", size: 2 };
    for (const Adapter of [AccorOfficialAdapter, HiltonOfficialAdapter]) {
      const result = await new Adapter().discover(request);
      assert.notEqual(result.diagnostics[0].status, "failed");
    }
  } finally { globalThis.fetch = original; }
});

test("same-age children remain separate travelers", () => {
  assert.deepEqual(normalizeChildrenAges([5, 5, 0, 18, -1, "9"]), [5, 5, 0, 9]);
});

test("Palace official admission replaces unrelated packages and expires for review", async () => {
  const attraction = { id: "palace", name: "故宫博物院" };
  const now = () => new Date("2026-09-28T08:00:00Z");
  const result = await searchQunarTicketQuotes({ destination: "北京", visitDate: "2026-10-06", attractions: [attraction] }, { now, fetchImpl: () => { throw new Error("Must not query packages for official-only admission"); } });
  assert.equal(result.quotes[0].amountCNY, 60);
  assert.equal(result.quotes[0].priceType, "admission");
  assert.match(result.quotes[0].bookingURL, /ticket.dpm.org.cn/);
  assert.equal(officialTicketQuote(attraction, "北京", "2026-11-06", now()).amountCNY, 40);
  assert.equal(officialTicketQuote(attraction, "台北", "2026-10-06", now()), null);
  assert.equal(officialTicketQuote(attraction, "北京", "2027-01-06", new Date("2027-01-01")), null);
});

const journey = { from: "WUH", to: "CKG", date: "2026-10-06", direction: "outbound" };
const row = { policy: { departDate: journey.date, currency: "CNY", price: 560, isContainsTax: false }, dport: "天河T3", aport: "江北T3", flightItem: { flights: [{ flightNo: "CZ6175", dtime: "2026-10-06 07:20:00", atime: "2026-10-06 08:55:00", dport: { cityName: "武汉" }, aport: { cityName: "重庆" }, stops: [] }] } };
const listing = { dcode: "WUH", acode: "CKG", ddate: journey.date, flights: [row] };
test("public flight results require exact route/date and preserve tax and overnight clocks", () => {
  const result = parseCtripPublicFlights(listing, journey, "2026-09-28T08:00:00Z");
  assert.equal(result[0].amountCNY, 560);
  assert.equal(result[0].durationMinutes, 95);
  assert.match(result[0].fareName, /未含税/);
  assert.throws(() => parseCtripPublicFlights({ ...listing, ddate: "2026-09-29" }, journey, ""), /date_mismatch/);
  assert.throws(() => parseCtripPublicFlights({ ...listing, acode: "SZX" }, journey, ""), /route_mismatch/);
  const overnight = structuredClone(row); overnight.flightItem.flights[0].dtime = "2026-10-06 23:20:00"; overnight.flightItem.flights[0].atime = "2026-10-07 00:55:00";
  assert.equal(parseCtripPublicFlights({ ...listing, flights: [overnight] }, journey, "")[0].durationMinutes, 95);
});
test("public source stops on a blocked response and never fabricates fallback prices", async () => {
  let calls = 0;
  const adapter = new CtripPublicFlightAdapter({ now: () => new Date("2026-09-28T08:00:00Z"), fetchImpl: async () => { calls++; return new Response("blocked", { status: 432 }); } });
  const result = await adapter.search({ origin: "武汉", destination: "重庆", departureDate: journey.date, modes: ["flight"] });
  assert.equal(calls, 1); assert.equal(result.options.length, 0); assert.equal(result.diagnostics[0].status, "failed");
});

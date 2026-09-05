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

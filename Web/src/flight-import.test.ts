import { it, expect } from "vitest";
import { importFlightResearch, researchFromRows, flightSearchURL } from "./flight-import";
const metadata = { origin: "武汉", destination: "重庆", date: "2026-10-06", sourceURL: "https://m.ctrip.com/html5/flight/taro/first?dcode=WUH&acode=CKG&ddate=2026-10-06", capturedAt: "2026-09-28T06:00:00Z" };
const expected = { ...metadata, direction: "outbound" as const };
it("imports reviewed visible prices as references and matches the whole journey", () => {
  const record = researchFromRows("CZ6175 | 07:20 | 08:55 | 560 | 天河T3 | 江北T3", metadata);
  const result = importFlightResearch(record, expected, new Date("2026-09-28T07:00:00Z"));
  expect(result[0].quotes[0]).toMatchObject({ kind: "indicative", amountCNY: 560, isStale: false });
  expect(result[0].durationMinutes).toBe(95);
  expect(() => importFlightResearch(record, { ...expected, date: "2026-10-07" })).toThrow(/日期/);
  expect(flightSearchURL("武汉", "重庆", metadata.date)).toContain("ddate=2026-10-06");
});
it("requires explicit overnight arrival, safe source and truthful capture time", () => {
  const record = researchFromRows("CZ6175 | 23:20 | 00:55 | 560 | 天河T3 | 江北T3", metadata);
  expect(() => importFlightResearch(record, expected)).toThrow(/跨日/);
  record.flights[0].nextDay = true;
  expect(importFlightResearch(record, expected, new Date("2026-09-29"))[0].quotes[0].isStale).toBe(true);
  expect(() => importFlightResearch({ ...record, sourceURL: "javascript:alert(1)" }, expected)).toThrow(/HTTPS/);
  expect(() => importFlightResearch({ ...record, capturedAt: "2999-01-01" }, expected)).toThrow(/查询时间/);
});

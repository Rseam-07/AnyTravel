import assert from "node:assert/strict";
import test from "node:test";
import { resolveCtripAirportCode } from "../src/adapters/ctrip-flight.mjs";
import { parseCtripFlightCards } from "../src/lib/flight-parser.mjs";
import { mergeTransportOptions } from "../src/lib/transport-merge.mjs";

const capturedAt = "2026-09-01T00:00:00.000Z";

test("resolves common Chinese cities and accepts explicit IATA codes", () => {
  assert.equal(resolveCtripAirportCode("宁波市"), "NGB");
  assert.equal(resolveCtripAirportCode("天津"), "TSN");
  assert.equal(resolveCtripAirportCode("pvg"), "PVG");
});

test("parses a rendered Ctrip flight card into a dated option", () => {
  const options = parseCtripFlightCards([{
    text: "中国东方航空\nMU5101 波音737\n08:10\n宁波栎社国际机场T2\n10:25\n天津滨海国际机场T2\n2小时15分\n经济舱 ¥680起"
  }], {
    direction: "outbound",
    date: "2026-09-10",
    originName: "宁波",
    destinationName: "天津",
    bookingURL: "https://flights.ctrip.com/online/list/oneway-ngb-tsn",
    capturedAt
  });

  assert.equal(options.length, 1);
  assert.equal(options[0].serviceNumber, "MU5101");
  assert.equal(options[0].originName, "宁波栎社国际机场T2");
  assert.equal(options[0].destinationName, "天津滨海国际机场T2");
  assert.equal(options[0].durationMinutes, 135);
  assert.equal(options[0].amountCNY, 680);
  assert.equal(options[0].fareName, "经济舱");
});

test("moves an overnight flight arrival to the next day", () => {
  const [option] = parseCtripFlightCards([
    "海南航空\nHU7001\n23:20\n海口美兰国际机场T1\n01:40 +1天\n北京首都国际机场T2\n2小时20分\n¥920 经济舱"
  ], {
    direction: "outbound",
    date: "2026-09-10",
    originName: "海口",
    destinationName: "北京",
    bookingURL: "https://flights.ctrip.com/",
    capturedAt
  });
  assert.equal(new Date(option.arrivalTime).getUTCDate(), 10);
  assert.equal((Date.parse(option.arrivalTime) - Date.parse(option.departureTime)) / 60_000, 140);
});

test("merges the same flight from multiple channels and keeps both fares", () => {
  const base = {
    mode: "flight",
    direction: "outbound",
    serviceNumber: "MU5101",
    originName: "宁波栎社国际机场T2",
    destinationName: "天津滨海国际机场T2",
    departureTime: "2026-09-10T00:10:00.000Z",
    arrivalTime: "2026-09-10T02:25:00.000Z",
    durationMinutes: 135,
    fareName: "经济舱",
    availability: "当前可选",
    capturedAt
  };
  const options = mergeTransportOptions([
    { ...base, provider: "ctrip", source: "ctrip-session", amountCNY: 680, bookingURL: "https://ctrip.example/" },
    { ...base, provider: "qunar", source: "qunar-session", amountCNY: 655, bookingURL: "https://qunar.example/" }
  ]);
  assert.equal(options.length, 1);
  assert.equal(options[0].offers.length, 2);
  assert.equal(options[0].amountCNY, 655);
  assert.deepEqual(options[0].offers.map((offer) => offer.provider), ["qunar", "ctrip"]);
});

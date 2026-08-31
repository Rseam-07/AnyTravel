import assert from "node:assert/strict";
import test from "node:test";
import {
  availabilitySummary,
  findStation,
  parseStationNames,
  parseTicketPrice,
  parseTrainRow
} from "../src/lib/railway-parser.mjs";
import { buildJourneyQueries } from "../src/adapters/railway12306.mjs";

test("parses station codes from the public station table", () => {
  const stations = parseStationNames("var station_names ='@sha|上海|SHH|shanghai|sh|20|0712|上海|||@szh|苏州|SZH|suzhou|sz|1215|0710|苏州|||';");

  assert.equal(findStation(stations, "上海市").code, "SHH");
  assert.equal(findStation(stations, "苏州站").code, "SZH");
});

test("parses a train row and prefers a usable second-class price", () => {
  const fields = Array(58).fill("");
  Object.assign(fields, {
    2: "55000G703280",
    3: "G7032",
    6: "SHH",
    7: "SZH",
    8: "05:45",
    9: "06:10",
    10: "00:25",
    11: "Y",
    16: "01",
    17: "02",
    30: "有",
    31: "有",
    35: "OMO"
  });
  const train = parseTrainRow(fields.join("|"), { SHH: "上海", SZH: "苏州" });
  const price = parseTicketPrice({ data: { WZ: "¥30.0", M: "¥48.0", O: "¥30.0", OT: [] } });

  assert.equal(train.serviceNumber, "G7032");
  assert.equal(train.durationMinutes, 25);
  assert.equal(price.amountCNY, 30);
  assert.equal(price.fareName, "二等座");
  assert.equal(availabilitySummary(train.availability), "二等座有票 · 一等座有票");
});

test("builds outbound and return railway queries with reversed stations", () => {
  const shanghai = { name: "上海", code: "SHH" };
  const suzhou = { name: "苏州", code: "SZH" };
  const journeys = buildJourneyQueries({
    departureDate: "2026-09-10",
    returnDate: "2026-09-12"
  }, shanghai, suzhou);

  assert.deepEqual(journeys, [
    { direction: "outbound", date: "2026-09-10", from: shanghai, to: suzhou },
    { direction: "return", date: "2026-09-12", from: suzhou, to: shanghai }
  ]);
});

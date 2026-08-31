import test from "node:test";
import assert from "node:assert/strict";
import { matchQunarSight, normalizeSightName, searchQunarTicketQuotes } from "../src/qunar-ticket-service.mjs";

test("normalizes common attraction suffixes without collapsing the real name", () => {
  assert.equal(normalizeSightName("虎丘山风景名胜区"), "虎丘山");
  assert.equal(normalizeSightName("拙政园（东门）"), "拙政园");
});

test("matches a Qunar sight to the selected attraction", () => {
  const sight = matchQunarSight(
    [
      { sightName: "虎丘山风景名胜区", address: "苏州市姑苏区虎丘山门内8号" },
      { sightName: "虎丘湿地公园", address: "苏州市相城区" }
    ],
    { name: "虎丘", address: "苏州市姑苏区虎丘山门内8号" }
  );
  assert.equal(sight.sightName, "虎丘山风景名胜区");
});

test("maps the public Qunar display price and booking URL", async () => {
  const payload = {
    data: {
      sightList: [{
        sightId: 641515105,
        sightName: "拙政园",
        address: "苏州市姑苏区东北街178号",
        free: false,
        qunarPrice: "38.2"
      }]
    }
  };
  const fetchImpl = async () => new Response(JSON.stringify(payload), {
    status: 200,
    headers: { "content-type": "application/json" }
  });

  const result = await searchQunarTicketQuotes({
    destination: "苏州",
    visitDate: "2026-09-15",
    attractions: [{ id: "garden", name: "拙政园", address: "苏州市姑苏区东北街178号" }]
  }, { fetchImpl, now: () => new Date("2026-09-01T00:00:00Z") });

  assert.equal(result.quotes.length, 1);
  assert.equal(result.quotes[0].amountCNY, 38);
  assert.equal(result.quotes[0].displayPriceText, "¥38.2/人起");
  assert.equal(result.quotes[0].provider, "qunar");
  assert.match(result.quotes[0].bookingURL, /detail_641515105/);
  assert.match(result.quotes[0].note, /计划日期2026-09-15/);
});

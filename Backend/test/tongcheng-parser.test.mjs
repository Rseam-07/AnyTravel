import test from "node:test";
import assert from "node:assert/strict";
import { cleanTongchengCity } from "../src/adapters/tongcheng.mjs";
import { parseTongchengCardTexts } from "../src/lib/tongcheng-parser.mjs";

test("normalizes a Tongcheng destination before city lookup", () => {
  assert.equal(cleanTongchengCity(" 苏州市 "), "苏州");
});

test("parses Tongcheng current price and visible room policies", () => {
  const hotels = [{ id: "hotel-1", name: "苏州吴宫泛太平洋酒店" }];
  const result = parseTongchengCardTexts(
    [{
      text: "苏州吴宫泛太平洋酒店\n4.8分 1,994条点评\n豪华大床房 含双早 免费取消\n￥688 ￥566起",
      href: "https://m.elong.com/hotel/detail?hotelid=1"
    }],
    hotels,
    "https://m.elong.com/hotel/hotellist",
    "2026-09-01T00:00:00.000Z"
  );

  assert.equal(result.length, 1);
  assert.equal(result[0].amountCNY, 566);
  assert.equal(result[0].provider, "tongcheng");
  assert.equal(result[0].bookingURL, "https://m.elong.com/hotel/detail?hotelid=1");
  assert.match(result[0].note, /免费取消/);
  assert.match(result[0].note, /含早/);
});

test("does not treat login-only copy as a live quote", () => {
  const result = parseTongchengCardTexts(
    ["苏州吴宫泛太平洋酒店\n4.8分\n登录查看低价"],
    [{ id: "hotel-1", name: "苏州吴宫泛太平洋酒店" }],
    "https://m.elong.com/hotel/hotellist",
    "2026-09-01T00:00:00.000Z"
  );
  assert.deepEqual(result, []);
});

test("requires a strong hotel-name match", () => {
  const result = parseTongchengCardTexts(
    ["苏州另一家精品酒店\n4.8分 888条点评\n￥399起"],
    [{ id: "hotel-1", name: "苏州柏悦酒店" }],
    "https://m.elong.com/hotel/hotellist",
    "2026-09-01T00:00:00.000Z"
  );
  assert.deepEqual(result, []);
});

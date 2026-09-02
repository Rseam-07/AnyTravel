import assert from "node:assert/strict";
import test from "node:test";
import {
  deduplicateAccommodationQuotes,
  mergeAccommodationCatalogResults
} from "../src/lib/accommodation-merge.mjs";
import { listingFromOneBoundRow } from "../src/adapters/onebound-ctrip.mjs";
import { parseCtripCatalogCards } from "../src/lib/ctrip-parser.mjs";
import { parseTongchengCatalogCards } from "../src/lib/tongcheng-parser.mjs";

const capturedAt = "2026-09-01T00:00:00.000Z";

test("merges one hotel across platforms while preserving both offers", () => {
  const hotels = mergeAccommodationCatalogResults([
    {
      providerHotelID: "ctrip-1",
      provider: "ctrip",
      source: "ctrip-session",
      name: "苏州吴宫泛太平洋酒店",
      address: "姑苏区新市路388号",
      latitude: 31.2861,
      longitude: 120.6221,
      amountCNY: 566,
      unit: "perNight",
      kind: "live",
      capturedAt,
      bookingURL: "https://hotels.ctrip.com/hotels/346290.html"
    },
    {
      providerHotelID: "tc-9",
      provider: "tongcheng",
      source: "tongcheng-session",
      name: "苏州吴宫泛太平洋酒店",
      address: "新市路388号",
      amountCNY: 542,
      unit: "perNight",
      kind: "live",
      capturedAt,
      bookingURL: "https://m.elong.com/hotel/detail?hotelid=9"
    }
  ]);

  assert.equal(hotels.length, 1);
  assert.equal(hotels[0].offers.length, 2);
  assert.deepEqual(hotels[0].offers.map((offer) => offer.provider).sort(), ["ctrip", "tongcheng"]);
  assert.deepEqual(hotels[0].sources, ["ctrip-session", "tongcheng-session"]);
  assert.equal(hotels[0].amountCNY, 542);
});

test("keeps differently named branches of the same chain separate", () => {
  const hotels = mergeAccommodationCatalogResults([
    { provider: "ctrip", name: "全季酒店(苏州观前街店)", address: "观前街1号" },
    { provider: "tongcheng", name: "全季酒店(苏州金鸡湖店)", address: "星湖街2号" }
  ]);
  assert.equal(hotels.length, 2);
});

test("nearby spelling variants merge when their coordinates agree", () => {
  const hotels = mergeAccommodationCatalogResults([
    {
      provider: "rollinggo",
      name: "苏州 W 酒店",
      address: "苏州工业园区星港街",
      latitude: 31.315,
      longitude: 120.68
    },
    {
      provider: "ctrip",
      name: "苏州W酒店",
      address: "星港街与苏惠路交叉口",
      latitude: 31.3155,
      longitude: 120.6803
    }
  ]);
  assert.equal(hotels.length, 1);
});

test("quote dedup keeps platforms and room variants but removes duplicate offers", () => {
  const quotes = deduplicateAccommodationQuotes([
    { hotelID: "hotel-1", hotelName: "测试酒店", provider: "ctrip", amountCNY: 620, unit: "perNight", roomName: "高级大床房", capturedAt },
    { hotelID: "hotel-1", hotelName: "测试酒店", provider: "ctrip", amountCNY: 588, unit: "perNight", roomName: "高级大床房", capturedAt },
    { hotelID: "hotel-1", hotelName: "测试酒店", provider: "ctrip", amountCNY: 680, unit: "perNight", roomName: "豪华双床房", capturedAt },
    { hotelID: "hotel-1", hotelName: "测试酒店", provider: "tongcheng", amountCNY: 570, unit: "perNight", roomName: "高级大床房", capturedAt }
  ]);
  assert.equal(quotes.length, 3);
  assert.deepEqual(quotes.map((quote) => quote.amountCNY), [570, 588, 680]);
});

test("OneBound catalog never presents its date-less list price as live", () => {
  const unpriced = listingFromOneBoundRow({
    title: "上海滴水湖斯南格尔精选酒店",
    num_iid: 112420466,
    address: "水芸路128号",
    price: "",
    detail_url: "https://hotels.ctrip.com/hotels/112420466.html"
  }, capturedAt);
  const priced = listingFromOneBoundRow({
    title: "上海东湖宾馆·悠选",
    num_iid: 445579,
    address: "东湖路7号",
    price: "688",
    detail_url: "https://hotels.ctrip.com/hotels/445579.html"
  }, capturedAt);

  assert.equal(unpriced.amountCNY, null);
  assert.equal(unpriced.kind, "checkOnProvider");
  assert.equal(priced.amountCNY, 688);
  assert.equal(priced.kind, "indicative");
});

test("session card parsers produce catalog listings even before a price appears", () => {
  const ctrip = parseCtripCatalogCards([{
    text: "苏州吴宫泛太平洋酒店 4.8 超棒 姑苏区新市路388号 登录查看低价",
    href: "https://hotels.ctrip.com/hotels/346290.html"
  }], "https://hotels.ctrip.com/", capturedAt);
  const tongcheng = parseTongchengCatalogCards([{
    text: "苏州吴宫泛太平洋酒店\n姑苏区新市路388号\n登录查看低价",
    href: "https://m.elong.com/hotel/detail?hotelid=9"
  }], "https://m.elong.com/hotel/", capturedAt);

  assert.equal(ctrip.length, 1);
  assert.equal(ctrip[0].amountCNY, null);
  assert.equal(tongcheng.length, 1);
  assert.equal(tongcheng[0].amountCNY, null);
});

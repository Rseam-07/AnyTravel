import assert from "node:assert/strict";
import test from "node:test";
import {
  catalogHotelFromObject,
  extractPrice,
  parseMCPPayload,
  quoteForRequestedHotel
} from "../src/lib/rollinggo-parser.mjs";

test("parses a streamable HTTP MCP response", () => {
  const payload = parseMCPPayload(`event: message\ndata: {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\\"hotelInformationList\\":[]}"}]},"id":1}\n\n`);
  assert.deepEqual(payload, [{ hotelInformationList: [] }]);
});

test("converts RollingGo stay total into a per-night amount", () => {
  const price = extractPrice({
    price: {
      message: "查价成功。2晚总价：826CNY（约413CNY/晚）",
      hasPrice: true,
      currency: "CNY",
      lowestPrice: 826
    }
  }, 2);
  assert.deepEqual(price, { amountCNY: 413, wasStayTotal: true });
});

test("keeps RollingGo search lowestPrice as a nightly amount", () => {
  const price = extractPrice({
    price: {
      message: "查价成功。最低价格：352，币种：CNY",
      hasPrice: true,
      currency: "CNY",
      lowestPrice: 352
    }
  }, 2);
  assert.deepEqual(price, { amountCNY: 352, wasStayTotal: false });
});

test("maps only the strongly matching requested hotel", () => {
  const requested = { id: "wu-gong", name: "苏州吴宫泛太平洋酒店" };
  const quote = quoteForRequestedHotel([
    { name: "酒店", price: { lowestPrice: 2905, message: "2晚总价" } },
    {
      name: "苏州吴宫泛太平洋酒店",
      price: { lowestPrice: 826, message: "2晚总价：826CNY" },
      bookingUrl: "https://example.com/book"
    }
  ], requested, 2, "2026-08-31T00:00:00.000Z");

  assert.equal(quote.hotelID, requested.id);
  assert.equal(quote.amountCNY, 413);
  assert.equal(quote.unit, "perNight");
  assert.equal(quote.bookingURL, "https://example.com/book");
});

test("does not attach a vaguely similar hotel", () => {
  const quote = quoteForRequestedHotel([
    { name: "苏州金鸡湖大酒店", price: { lowestPrice: 600, message: "2晚总价" } }
  ], { id: "other", name: "苏州吴宫泛太平洋酒店" }, 2, "2026-08-31T00:00:00.000Z");
  assert.equal(quote, null);
});

test("maps a RollingGo discovery result into a rich hotel card", () => {
  const hotel = catalogHotelFromObject({
    hotelId: "rg-1",
    name: "苏州松弛酒店",
    brand: "AnyTravel",
    address: "姑苏区示例路1号",
    latitude: 31.31,
    longitude: 120.62,
    starRating: 4,
    rating: 4.8,
    imageUrl: "https://example.com/hotel.jpg",
    bookingUrl: "https://example.com/book",
    amenities: ["早餐", { name: "停车场" }],
    price: { lowestPrice: 1_200, message: "2晚总价" }
  }, 2, "2026-09-01T00:00:00.000Z");

  assert.equal(hotel.name, "苏州松弛酒店");
  assert.equal(hotel.amountCNY, 600);
  assert.equal(hotel.starRating, 4);
  assert.deepEqual(hotel.amenities, ["早餐", "停车场"]);
  assert.equal(hotel.bookingURL, "https://example.com/book");
});

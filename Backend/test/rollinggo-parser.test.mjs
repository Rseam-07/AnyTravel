import assert from "node:assert/strict";
import test from "node:test";
import { extractPrice, parseMCPPayload, quoteForRequestedHotel } from "../src/lib/rollinggo-parser.mjs";

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

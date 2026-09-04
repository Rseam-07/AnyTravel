import assert from "node:assert/strict";
import test from "node:test";
import { HiltonOfficialAdapter, listingsFromHiltonPayload } from "../src/adapters/hilton-official.mjs";

const payload = {
  success: true,
  code: 200,
  data: {
    hotels: [{
      brandCode: "HI",
      hotelCode: "SZVTVHI",
      hotelName: "苏州希尔顿酒店",
      minPrice: 647.13,
      sellingPoints: ["紧邻地铁"],
      amenities: ["freeWifi"],
      masterCover: { url: "https://img.example/hilton.jpg" },
      location: {
        address: "苏州大道东275号",
        coordinate: { latitude: 31.324349, longitude: 120.735565 }
      }
    }]
  }
};

const request = {
  destination: "苏州",
  checkIn: "2026-09-09",
  checkOut: "2026-09-11",
  adults: 2,
  rooms: 1,
  size: 20
};

test("Hilton official payload keeps the displayed price indicative and dates the booking link", () => {
  const [hotel] = listingsFromHiltonPayload(payload, request, "2026-09-05T00:00:00.000Z");
  assert.equal(hotel.name, "苏州希尔顿酒店");
  assert.equal(hotel.amountCNY, 647);
  assert.equal(hotel.kind, "indicative");
  assert.equal(hotel.provider, "official");
  assert.equal(hotel.source, "hilton-official");
  assert.match(hotel.bookingURL, /arrivalDate=2026-09-09/);
  assert.match(hotel.bookingURL, /departureDate=2026-09-11/);
  assert.equal(hotel.latitude, 31.324349);
});

test("Hilton official adapter only attaches a quote to a strong hotel-name match", async () => {
  let requestedURL;
  const adapter = new HiltonOfficialAdapter({
    fetchImpl: async (url) => {
      requestedURL = url;
      return { ok: true, json: async () => payload };
    },
    now: () => new Date("2026-09-05T00:00:00.000Z")
  });
  const result = await adapter.search({
    ...request,
    hotels: [
      { id: "wanted", name: "苏州希尔顿酒店" },
      { id: "other", name: "苏州吴宫泛太平洋酒店" }
    ]
  });
  assert.equal(requestedURL.searchParams.get("keywords"), "苏州");
  assert.equal(result.quotes.length, 1);
  assert.equal(result.quotes[0].hotelID, "wanted");
  assert.equal(result.quotes[0].kind, "indicative");
  assert.equal(result.quotes[0].amountCNY, 647);
});

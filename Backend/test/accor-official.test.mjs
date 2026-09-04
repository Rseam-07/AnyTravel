import assert from "node:assert/strict";
import test from "node:test";
import { AccorOfficialAdapter, listingFromAccor } from "../src/adapters/accor-official.mjs";

const request = {
  destination: "苏州",
  checkIn: "2026-09-09",
  checkOut: "2026-09-11",
  adults: 2,
  rooms: 1,
  size: 5
};

const hotel = {
  objectID: "B1K2",
  name: "Pullman Suzhou Zhonghui",
  brandLabel: "Pullman",
  stars: 5,
  rating: { score: 4.7 },
  localization: {
    address: { street: "188 Jiayuan Road", city: "Suzhou" },
    gps: { lat: 31.371, lng: 120.615 }
  },
  freeAmenities: ["Wi-Fi", "Parking"],
  mediaCatalog: { "1024x768": "https://example.com/pullman.jpg" }
};

const availableRate = {
  available: true,
  availability: "AVAILABLE",
  offer: {
    accommodation: { code: "SUP" },
    mealPlan: { label: "Breakfast included" },
    pricing: {
      main: {
        amount: 974.4,
        simplifiedPolicies: { cancellation: { label: "Free cancellation before 18:00" } }
      }
    }
  }
};

test("Accor selected-date stay total is normalized to a nightly live price", () => {
  const listing = listingFromAccor(hotel, availableRate, request, 2, "2026-09-05T00:00:00.000Z");
  assert.equal(listing.name, "Pullman Suzhou Zhonghui");
  assert.equal(listing.amountCNY, 487);
  assert.equal(listing.totalAmountCNY, 974);
  assert.equal(listing.kind, "live");
  assert.equal(listing.source, "accor-official");
  assert.equal(listing.latitude, 31.371);
  assert.match(listing.bookingURL, /checkIn=2026-09-09/);
  assert.match(listing.bookingURL, /checkOut=2026-09-11/);
  assert.match(listing.note, /所选日期公开价/);
});

test("Accor unavailable dates keep a useful official-site catalog card", () => {
  const listing = listingFromAccor(
    hotel,
    { available: false, availability: "UNAVAILABLE", reason: "Sold out" },
    request,
    2
  );
  assert.equal(listing.amountCNY, null);
  assert.equal(listing.kind, "checkOnProvider");
  assert.equal(listing.availability, "Sold out");
});

test("Accor adapter attaches a live quote only to a strong name match", async () => {
  const calls = [];
  const adapter = new AccorOfficialAdapter({
    fetchImpl: async (url) => {
      calls.push(String(url));
      if (String(url).includes("algolia.net")) {
        return { ok: true, json: async () => ({ hits: [hotel] }) };
      }
      return {
        ok: true,
        json: async () => ({
          data: {
            hotelOffers: {
              availability: { status: "AVAILABLE", reasons: [] },
              offersSelection: { offers: [availableRate.offer] }
            }
          }
        })
      };
    },
    now: () => new Date("2026-09-05T00:00:00.000Z")
  });
  const result = await adapter.search({
    ...request,
    hotels: [
      { id: "wanted", name: "Pullman Suzhou Zhonghui" },
      { id: "other", name: "苏州希尔顿酒店" }
    ]
  });
  assert.equal(calls.length, 2);
  assert.match(calls[0], /prod_hotels_zh\/query/);
  assert.equal(result.quotes.length, 1);
  assert.equal(result.quotes[0].hotelID, "wanted");
  assert.equal(result.quotes[0].provider, "official");
  assert.equal(result.quotes[0].kind, "live");
  assert.equal(result.quotes[0].amountCNY, 487);
});

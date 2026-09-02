import test from "node:test";
import assert from "node:assert/strict";
import { normalizeElement } from "../src/overpass-service.mjs";

const capturedAt = "2026-09-02T12:00:00.000Z";

test("normalizes an OSM POI with zh name and opening hours", () => {
  const element = {
    type: "way",
    id: 123,
    center: { lat: 31.31, lon: 120.62 },
    tags: {
      tourism: "attraction",
      name: "The Humble Administrator's Garden",
      "name:zh": "拙政园",
      opening_hours: "Mo-Su 07:30-17:30",
      "addr:street": "东北街178号"
    }
  };
  const place = normalizeElement(element, capturedAt);
  assert.equal(place.name, "拙政园");
  assert.equal(place.interest, "gardens");
  assert.equal(place.opening, "Mo-Su 07:30-17:30");
  assert.equal(place.coordinate, undefined);
  assert.equal(place.latitude, 31.31);
  assert.equal(place.longitude, 120.62);
  assert.equal(place.address, "东北街178号");
});

test("classifies museums as culture and restaurants as food", () => {
  const museum = normalizeElement({ type: "node", id: 1, lat: 1, lon: 1, tags: { tourism: "museum", name: "苏州博物馆" } }, capturedAt);
  const restaurant = normalizeElement({ type: "node", id: 2, lat: 1, lon: 1, tags: { amenity: "restaurant", name: "松鹤楼" } }, capturedAt);
  assert.equal(museum.interest, "culture");
  assert.equal(restaurant.interest, "food");
});

test("drops elements without a usable name or coordinate", () => {
  assert.equal(normalizeElement({ type: "node", id: 1, lat: 1, lon: 1, tags: { tourism: "attraction" } }, capturedAt), null);
  assert.equal(normalizeElement({ type: "node", id: 2, tags: { name: "某处" } }, capturedAt), null);
});

test("keeps the radius query well-formed for the provider", async () => {
  const url = new URL("https://overpass-api.de/api/interpreter");
  url.searchParams.set("data", `[out:json][timeout:30];(nwr["tourism"](around:15000,31.30000,120.60000););out center 120;`);
  const encoded = url.searchParams.get("data");
  assert.ok(encoded.includes("around:15000,31.30000,120.60000"));
  assert.ok(encoded.includes("out center 120"));
});

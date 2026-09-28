import test from "node:test";
import assert from "node:assert/strict";
import { normalizeElement, searchPlacesAround } from "../src/overpass-service.mjs";

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

test("failed public POI sources degrade to nearby known places with truthful provenance", async () => {
  const original = globalThis.fetch;
  let attempts = 0;
  globalThis.fetch = async () => { attempts++; return new Response("unavailable", { status: 503 }); };
  try {
    const result = await searchPlacesAround({ latitude: 39.91631, longitude: 116.39721, radius: 5000, limit: 20 });
    assert.equal(result.source, "knowledge-fallback");
    assert.equal(result.degraded, true);
    assert.ok(result.places.length > 0);
    assert.ok(result.places.every(place => place.distance <= 5000 && place.rating === null && place.source.includes("内置")));
    assert.ok(attempts <= 2, "must not query the Europe-only mirror for China");
    await assert.rejects(searchPlacesAround({ latitude: -70, longitude: -120, radius: 1000 }), /暂时/);
    await assert.rejects(searchPlacesAround({ latitude: 91, longitude: 0 }), /latitude/);
  } finally { globalThis.fetch = original; }
});

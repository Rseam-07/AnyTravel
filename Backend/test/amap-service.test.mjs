import assert from "node:assert/strict";
import test from "node:test";
import { AMapError, gcj02ToWGS84, normalizePOI, searchAMapPlaces } from "../src/amap-service.mjs";

test("converts and labels an AMap GCJ-02 place", () => {
  const place = normalizePOI({
    id: "B0TEST",
    name: "拙政园",
    address: "东北街178号",
    type: "风景名胜",
    location: "120.625100,31.326500",
    business: {
      opentime_today: "09:00-17:00",
      opentime_week: "周一至周日 09:00-17:00",
      rating: "4.8",
      cost: "80"
    }
  });
  assert.equal(place.name, "拙政园");
  assert.equal(place.sourceCoordinateSystem, "GCJ-02");
  assert.ok(Math.abs(place.coordinate.longitude - place.sourceCoordinate.longitude) > 0.001);
  assert.ok(Math.abs(place.coordinate.latitude - place.sourceCoordinate.latitude) > 0.001);
  assert.equal(place.openingHoursToday, "09:00-17:00");
  assert.equal(place.openingHoursWeek, "周一至周日 09:00-17:00");
  assert.equal(place.rating, 4.8);
  assert.equal(place.averageCostCNY, 80);
});

test("keeps coordinates outside China unchanged", () => {
  assert.deepEqual(gcj02ToWGS84(2.3522, 48.8566), { longitude: 2.3522, latitude: 48.8566 });
});

test("reports an iOS-only key as a platform mismatch", async () => {
  const fetchImpl = async () => new Response(JSON.stringify({
    status: "0",
    info: "USERKEY_PLAT_NOMATCH",
    infocode: "10009"
  }), { status: 200, headers: { "content-type": "application/json" } });

  await assert.rejects(
    searchAMapPlaces(
      { keywords: "园林", city: "苏州" },
      { fetchImpl, env: { AMAP_API_KEY: "test", AMAP_BASE_URL: "https://restapi.amap.com" } }
    ),
    (error) => error instanceof AMapError && error.code === "amap_key_platform_mismatch" && error.status === 422
  );
});

test("returns provenance and converted places for a valid response", async () => {
  const fetchImpl = async (url) => {
    assert.equal(url.pathname, "/v5/place/text");
    assert.equal(url.searchParams.get("key"), "test");
    assert.equal(url.searchParams.get("region"), "苏州");
    assert.equal(url.searchParams.get("city_limit"), "true");
    assert.equal(url.searchParams.get("page_size"), "12");
    assert.equal(url.searchParams.get("page_num"), "1");
    assert.equal(url.searchParams.get("show_fields"), "business");
    return new Response(JSON.stringify({
      status: "1",
      pois: [{ id: "1", name: "苏州博物馆", address: "东北街204号", type: "科教文化服务", location: "120.6230,31.3247" }]
    }), { status: 200, headers: { "content-type": "application/json" } });
  };
  const result = await searchAMapPlaces(
    { keywords: "博物馆", city: "苏州" },
    {
      fetchImpl,
      env: { AMAP_API_KEY: "test", AMAP_BASE_URL: "https://restapi.amap.com" },
      now: () => new Date("2026-08-31T12:00:00Z")
    }
  );
  assert.equal(result.places.length, 1);
  assert.equal(result.sourceCRS, "GCJ-02");
  assert.equal(result.outputCRS, "WGS84 approximate inverse");
  assert.equal(result.capturedAt, "2026-08-31T12:00:00.000Z");
});

import { describe, expect, it } from "vitest";
import { parseRoadRoute, sketchLeg } from "./route-geometry";
import { handbookLegs } from "./handbook/routes";
import type { BookDay, BookPlace } from "./handbook/model";

describe("truthful map geometry", () => {
  const from = { lng: 120.6, lat: 31.3 }, to = { lng: 120.61, lat: 31.31 };
  const geometry = [[120.6, 31.3], [120.605, 31.31], [120.61, 31.31]];
  const payload = () => ({ code: "Ok", waypoints: [{ distance: 0 }, { distance: 10 }], routes: [{ distance: 1800, duration: 1200, geometry: { coordinates: geometry }, legs: [{ distance: 1800, duration: 1200, steps: [{ geometry: { coordinates: geometry } }] }] }] });
  it("retains actual leg shapes and route distances", () => {
    expect(parseRoadRoute(payload(), 2, "walking")).toMatchObject({ distanceMeters: 1800, durationMinutes: 20, legs: [{ geometry }] });
  });
  it("rejects distant snapped points and incomplete or non-finite geometry", () => {
    const p = payload(); p.waypoints[0].distance = 1000;
    expect(parseRoadRoute(p, 2, "walking")).toBeNull();
    const bad = payload(); bad.routes[0].geometry.coordinates = [[NaN, 31.3], [120, 31]];
    expect(parseRoadRoute(bad, 2, "walking")).toBeNull();
    expect(parseRoadRoute(payload(), 3, "walking")).toBeNull();
  });
  it("anchors an itinerary sketch exactly to its stops", () => {
    const line = sketchLeg(from, to);
    expect(line[0]).toEqual([from.lng, from.lat]);
    expect(line.at(-1)![0]).toBeCloseTo(to.lng); expect(line.at(-1)![1]).toBeCloseTo(to.lat);
    expect(line[12][0]).not.toBe((from.lng + to.lng) / 2);
  });
  const places = ["a", "b", "c"].map((id, i) => ({ id, name: id, region: "test", coordinate: { lng: 120 + i, lat: 31 } } as BookPlace));
  const day = (ids: string[]) => ({ items: ids.map(id => ({ placeIds: [id] })) } as BookDay);
  it("preserves a return visit instead of deduplicating the route", () => {
    expect(handbookLegs(day(["a", "b", "a"]), places).map(l => [l.from.id, l.to.id])).toEqual([["a", "b"], ["b", "a"]]);
  });
  it("never connects across a hidden or unlocated intermediate stop", () => {
    expect(handbookLegs(day(["a", "b", "c"]), [places[0], places[2]])).toEqual([]);
    expect(handbookLegs(day(["a", "b", "c"]), [places[0], { ...places[1], coordinate: undefined }, places[2]])).toEqual([]);
  });
});

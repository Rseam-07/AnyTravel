import type { Coord } from "./types";

export const DAY_COLORS = ["#126E66", "#C55A24", "#6157B8", "#B34B68", "#2777A8", "#7B6C35"];
export interface RoadLeg { geometry: [number, number][]; distanceMeters: number; durationMinutes: number }
export interface RoadRoute extends RoadLeg { legs: RoadLeg[] }

const cache = new Map<string, { value: RoadRoute | null; expires: number }>();
let queue: Promise<unknown> = Promise.resolve();
let lastRequest = 0;
export const routeKey = (points: Coord[], mode: string) => `${mode}:${points.map(p => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";")}`;
const valid = (p: unknown): p is [number, number] => Array.isArray(p) && p.length >= 2 && Number.isFinite(p[0]) && Number.isFinite(p[1]) && Math.abs(p[0]) <= 180 && Math.abs(p[1]) <= 90;

/** Both profiles are actual, separately built road graphs. The URL profile name alone cannot switch an OSRM graph. */
export async function roadRoute(points: Coord[], mode: "walking" | "driving", signal?: AbortSignal): Promise<RoadRoute | null> {
  if (points.length < 2 || points.some(p => !valid([p.lng, p.lat])) || signal?.aborted) return null;
  const key = routeKey(points, mode);
  const task = queue.then(async () => {
    if (signal?.aborted) return null;
    const saved = cache.get(key);
    if (saved && saved.expires > Date.now()) return saved.value;
    // FOSSGIS asks for at most one request per second. Request one day at a time,
    // including every stop, instead of firing parallel requests for each leg.
    await new Promise(resolve => setTimeout(resolve, Math.max(0, 1100 - (Date.now() - lastRequest))));
    if (signal?.aborted) return null;
    lastRequest = Date.now();
    let value: RoadRoute | null = null;
    try {
      const profile = mode === "walking" ? "foot" : "car";
      const path = points.map(p => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";");
      const response = await fetch(`https://routing.openstreetmap.de/routed-${profile}/route/v1/driving/${path}?overview=full&geometries=geojson&steps=true`, {
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(8000)]) : AbortSignal.timeout(8000)
      });
      if (response.ok) value = parseRoadRoute(await response.json(), points.length, mode);
    } catch { /* Keep the explicitly labelled itinerary sketch. */ }
    if (!signal?.aborted) {
      if (cache.size >= 100) cache.delete(cache.keys().next().value!);
      cache.set(key, { value, expires: Date.now() + (value ? 30 * 60_000 : 60_000) });
    }
    return value;
  });
  queue = task.catch(() => null);
  return task;
}

export function parseRoadRoute(payload: any, pointCount: number, mode: "walking" | "driving"): RoadRoute | null {
  const route = payload?.routes?.[0];
  if (payload?.code !== "Ok" || !route || !Array.isArray(payload.waypoints) || payload.waypoints.length !== pointCount ||
      payload.waypoints.some((p: any) => !Number.isFinite(p.distance) || p.distance > (mode === "walking" ? 200 : 400)) ||
      !Array.isArray(route.geometry?.coordinates) || route.geometry.coordinates.length < 2 || !route.geometry.coordinates.every(valid) ||
      !Number.isFinite(route.distance) || route.distance < 0 || !Number.isFinite(route.duration) || route.duration < 0 ||
      !Array.isArray(route.legs) || route.legs.length !== pointCount - 1) return null;
  const legs: RoadLeg[] = [];
  for (const leg of route.legs) {
    if (!Array.isArray(leg.steps) || !Number.isFinite(leg.distance) || leg.distance < 0 || !Number.isFinite(leg.duration) || leg.duration < 0) return null;
    const geometry = leg.steps.flatMap((s: any) => s.geometry?.coordinates ?? []);
    if (geometry.length < 2 || !geometry.every(valid)) return null;
    legs.push({ geometry, distanceMeters: leg.distance, durationMinutes: Math.max(1, Math.round(leg.duration / 60)) });
  }
  return { geometry: route.geometry.coordinates, distanceMeters: route.distance, durationMinutes: Math.max(1, Math.round(route.duration / 60)), legs };
}

/** A gentle curve conveys visiting order; it never claims to follow a road. */
export function sketchLeg(from: Coord, to: Coord): [number, number][] {
  const cos = Math.max(0.1, Math.cos((from.lat + to.lat) * Math.PI / 360));
  let dx = to.lng - from.lng;
  if (dx > 180) dx -= 360;
  if (dx < -180) dx += 360;
  const dy = (to.lat - from.lat) / cos;
  const bend = 0.1;
  return Array.from({ length: 25 }, (_, i) => {
    const t = i / 24, arc = 4 * t * (1 - t) * bend;
    return [from.lng + dx * t - dy * arc, from.lat + (dy * t + dx * arc) * cos];
  });
}

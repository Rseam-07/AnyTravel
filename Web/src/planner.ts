// AnyTravel Web heuristic itinerary builder.
// Mirrors TourismPlanningPolicy on iOS: seed assignment by day count, greedy
// nearest-neighbour ordering per day (limited opening-hour priority), typed
// visit durations, lunch/night slots, contingency and over-capacity flags.
// This is a planning estimate; real road segments come from OSRM when available.

import {
  DAY_BUDGETS,
  INTEREST_MINUTES,
  PACE_META,
  type Coord,
  type Pace,
  type ProviderQuote,
  type Plan,
  type PlanDay,
  type PlanStop,
  type TravelPlace,
  type TripDraft,
  clockText,
  durationText
} from "./types";

const EARTH_RADIUS_M = 6371000;

export function distanceMeters(from: Coord, to: Coord): number {
  const toRad = (v: number) => (v * Math.PI) / 180;
  const dLat = toRad(to.lat - from.lat);
  const dLng = toRad(to.lng - from.lng);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(from.lat)) * Math.cos(toRad(to.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a));
}

export function estimateTravelMinutes(from: Coord, to: Coord, mode: TripDraft["transportMode"]): number {
  const km = distanceMeters(from, to) / 1000;
  const spec: Record<string, [number, number]> = {
    walking: [4.5, 4],
    transit: [18, 12],
    driving: [27, 9]
  };
  const [speed, overhead] = spec[mode] ?? spec.transit;
  const raw = (km / speed) * 60 + overhead;
  return Math.min(Math.max(Math.round(raw / 5) * 5, 5), 120);
}

export function visitMinutes(place: TravelPlace, pace: Pace): number {
  const base = INTEREST_MINUTES[place.interest] ?? 105;
  const multiplier = pace === "relaxed" ? 1.12 : pace === "full" ? 0.86 : 1;
  const primary = place.planningPriority === "primary" ? 1.28 : 1;
  return Math.max(Math.round((base * multiplier * primary) / 5) * 5, 5);
}

function openingWindow(place: TravelPlace): { start: number; end: number } | null {
  if (!place.opening) return null;
  const match = place.opening.match(/(\d{1,2})[:：](\d{2})\s*[-–—至]\s*(\d{1,2})[:：](\d{2})/);
  if (!match) return null;
  const start = Number(match[1]) * 60 + Number(match[2]);
  const end = Number(match[3]) * 60 + Number(match[4]);
  if (start < end && end <= 24 * 60) return { start, end };
  return null;
}

function dateLabel(date: string): string {
  if (!date) return "";
  const d = new Date(`${date}T00:00:00`);
  if (Number.isNaN(d.getTime())) return date;
  const week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][d.getDay()];
  return `${date.slice(5).replace("-", "月")}日 ${week}`;
}

export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00`);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

export interface PlannedDay {
  dayStops: TravelPlace[];
  date: string;
}

export function dayBuckets(places: TravelPlace[], draft: TripDraft): PlannedDay[] {
  const dayCount = Math.max(draft.dayCount, 1);
  const center = draft.destinationCoord ?? places[0].coordinate;

  // Seeds: first near destination centre, remaining ones spread apart.
  const sorted = [...places].sort(
    (a, b) => distanceMeters(center, a.coordinate) - distanceMeters(center, b.coordinate)
  );
  const seeds: TravelPlace[] = [sorted[0]];
  for (let i = 1; i < dayCount && i < sorted.length; i++) {
    let best: TravelPlace | null = null;
    let bestDist = -1;
    for (const place of sorted) {
      if (seeds.includes(place)) continue;
      const minDist = Math.min(...seeds.map((s) => distanceMeters(s.coordinate, place.coordinate)));
      if (minDist > bestDist) {
        bestDist = minDist;
        best = place;
      }
    }
    if (best) seeds.push(best);
  }

  // Assign each non-seed place to the nearest seed with capacity headroom.
  const capacityPerDay = PACE_META[draft.pace].stopsPerDay + 2;
  const buckets: Record<number, TravelPlace[]> = {};
  const rest = places.filter((p) => !seeds.includes(p));
  const normalized = rest.map((p, i) => ({ place: p, order: i })).sort((a, b) => a.order - b.order);
  for (const { place } of normalized) {
    let bestDay = 0;
    let bestDist = Infinity;
    for (let d = 0; d < seeds.length; d++) {
      if ((buckets[d] ?? []).length >= capacityPerDay) continue;
      const dist = distanceMeters(seeds[d].coordinate, place.coordinate);
      if (dist < bestDist) {
        bestDist = dist;
        bestDay = d;
      }
    }
    (buckets[bestDay] = buckets[bestDay] ?? []).push(place);
  }

  const out: PlannedDay[] = [];
  for (let d = 0; d < dayCount; d++) {
    const stopList = [seeds[Math.min(d, seeds.length - 1)], ...(buckets[d] ?? [])];
    if (stopList.length === 0) continue;
    const unique: TravelPlace[] = [];
    for (const place of stopList) {
      const dup = unique.find(
        (u) =>
          (u.name === place.name || u.name.includes(place.name) || place.name.includes(u.name)) &&
          distanceMeters(u.coordinate, place.coordinate) < 400
      );
      if (!dup) unique.push(place);
    }
    if (unique.length > 0) {
      out.push({ dayStops: unique, date: draft.startDate ? addDays(draft.startDate, d) : "" });
    }
  }
  return out;
}

export function planItinerary(
  places: TravelPlace[],
  draft: TripDraft,
  actualRoutes?: { from: Coord; to: Coord; minutes: number }[]
): Plan {
  if (places.length < 2) {
    throw new Error("还没有足够能落在地图上的地点，请换个目的地或关键词再试。");
  }
  const center = draft.destinationCoord ?? places[0].coordinate;
  const rhythm = DAY_BUDGETS[draft.pace];
  const buckets = dayBuckets(places, draft);
  const built: PlanDay[] = [];

  for (const { dayStops, date } of buckets) {
    // Greedy nearest-neighbour ordering with limited opening-hour priority.
    const orderedStops: TravelPlace[] = [];
    let cursor: Coord = center;
    const remaining = [...dayStops];
    while (remaining.length > 0) {
      let pickIndex = 0;
      let bestScore = Infinity;
      for (let i = 0; i < remaining.length; i++) {
        const place = remaining[i];
        const dist = distanceMeters(cursor, place.coordinate);
        let score = dist;
        const win = openingWindow(place);
        if (win && win.start < 12 * 60) score = Math.min(score, dist * 0.7);
        if (place.interest === "night") score += 40000;
        if (place.interest === "food" && orderedStops.length === 0) score += 30000;
        if (score < bestScore) {
          bestScore = score;
          pickIndex = i;
        }
      }
      const picked = remaining.splice(pickIndex, 1)[0];
      orderedStops.push(picked);
      cursor = picked.coordinate;
    }

    // Timeline.
    const stops: PlanStop[] = [];
    let minutes = rhythm.start;
    let visitTotal = 0;
    let travelTotal = 0;
    let from: Coord = center;
    const route: { from: Coord; to: Coord }[] = [];
    const hasFood = orderedStops.some((p) => p.interest === "food");
    const hasNight = orderedStops.some((p) => p.interest === "night");

    for (const place of orderedStops) {
      const visit = visitMinutes(place, draft.pace);
      let move = estimateTravelMinutes(from, place.coordinate, draft.transportMode);
      const realRoute = actualRoutes?.find(
        (r) => distanceMeters(r.from, from) < 250 && distanceMeters(r.to, place.coordinate) < 250
      );
      if (realRoute) move = realRoute.minutes;
      travelTotal += move;
      minutes += move;
      route.push({ from, to: place.coordinate });

      if (!hasFood && stops.length > 0 && minutes < rhythm.lunch && minutes + visit > rhythm.lunch) {
        minutes += rhythm.lunchDuration;
      }
      if (place.interest === "food" && stops.length > 0 && minutes < rhythm.lunch) {
        minutes = rhythm.lunch;
      }

      const arrivalMinute = minutes;
      minutes += visit;
      const isFood = place.interest === "food";
      stops.push({
        place,
        arriveMinute: arrivalMinute,
        leaveMinute: minutes,
        arrivalText: clockText(arrivalMinute),
        departureText: clockText(minutes),
        visitMinutes: visit,
        moveMinutes: move,
        moveFrom: stops.length > 0 ? from : center,
        isPrimary: place.planningPriority === "primary",
        opening: place.opening,
        ticket: place.ticket,
        note: isFood && hasFood ? "这一天的正餐落在这里" : undefined
      });
      from = place.coordinate;
    }

    const end = minutes;
    const ordinaryEnd = hasNight ? rhythm.nightEnd : rhythm.daytimeEnd;
    const overCapacity = end > ordinaryEnd;
    const hasMealStop = dayStops.some((p) => p.interest === "food");
    const quoted = dayStops.filter((p) => p.ticket?.amountCNY != null).length;

    const badges = [
      `停留${durationText(visitTotal)}`,
      travelTotal > 0 ? `移动${durationText(travelTotal)}` : "少移动",
      hasMealStop ? "餐食已入线" : "午餐有留白"
    ];
    if (hasNight) badges.push("夜游置后");
    if (quoted > 0) badges.push(`${quoted} 处门票价`);
    const assessment = overCapacity
      ? "按当前节奏估算偏满，建议减一站或增加一天。"
      : "预计可在当天舒适时段内完成。";

    built.push({
      dateLabel: dateLabel(date),
      title: date ? `${dateLabel(date)} · 第${built.length + 1}天` : `第${built.length + 1}天`,
      stops,
      totalMinutes: end - rhythm.start,
      visitMinutes: visitTotal,
      travelMinutes: travelTotal,
      availableMinutes: Math.max(ordinaryEnd - rhythm.start, 0),
      overCapacity,
      assessment,
      badges,
      route
    });
  }

  const notes: string[] = [
    "规划为 Web 本地启发式：移动时间按直线速度估算，取得 OSRM 真实路线后会自动替换。"
  ];
  if (places.some((p) => p.opening)) {
    notes.push("已纳入可读取的营业时段，闭馆日与预约仍需在出发前复核。");
  }
  return {
    days: built,
    generatedAt: new Date().toISOString(),
    notes,
    engine: "web-heuristic"
  };
}

export function bestQuote(quotes: ProviderQuote[]): ProviderQuote | undefined {
  return (
    quotes
      .filter((q) => q.amountCNY != null && q.kind !== "demo")
      .sort((a, b) => (a.amountCNY ?? 0) - (b.amountCNY ?? 0))[0] ?? quotes[0]
  );
}

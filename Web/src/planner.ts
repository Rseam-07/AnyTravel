import { famousBestTime, famousStayMinutes, knowledgeHeat } from "./knowledge";
import {
  DAY_BUDGETS,
  INTEREST_MINUTES,
  type Coord,
  type Interest,
  type Pace,
  type Plan,
  type PlanDay,
  type PlanStop,
  type ProviderQuote,
  type TravelPlace,
  type TripDraft,
  clockText,
  durationText
} from "./types";

const EARTH_RADIUS_M = 6_371_000;
const DAILY_MAIN_LIMIT: Record<Pace, number> = { relaxed: 2, balanced: 3, full: 4 };
const DAILY_TOTAL_LIMIT: Record<Pace, number> = { relaxed: 4, balanced: 5, full: 6 };
const WHOLE_DAY_NAMES = /迪士尼|环球影城|主题乐园|欢乐谷|森林世界|海洋公园|冰雪大世界|黄山|九寨沟|张家界|米尔福德峡湾|霍比屯/;

export interface DayAssignment {
  stops: TravelPlace[];
  anchor: TravelPlace | null;
  date: string;
  theme: string;
  wholeDay: boolean;
}

export function distanceMeters(from: Coord, to: Coord): number {
  const toRad = (value: number) => (value * Math.PI) / 180;
  const dLat = toRad(to.lat - from.lat);
  const dLng = toRad(to.lng - from.lng);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(from.lat)) * Math.cos(toRad(to.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a));
}

export function estimateTravelMinutes(from: Coord, to: Coord, mode: TripDraft["transportMode"]): number {
  const km = distanceMeters(from, to) / 1000;
  const spec: Record<TripDraft["transportMode"], [number, number]> = {
    walking: [4.5, 4],
    transit: [18, 12],
    driving: [27, 9]
  };
  const [speed, overhead] = spec[mode];
  return Math.min(Math.max(Math.round((((km / speed) * 60) + overhead) / 5) * 5, 5), 120);
}

export function visitMinutes(place: TravelPlace, pace: Pace): number {
  const base = INTEREST_MINUTES[place.interest] ?? 105;
  const paceMultiplier = pace === "relaxed" ? 1.12 : pace === "full" ? 0.88 : 1;
  const priorityMultiplier = place.planningPriority === "primary" ? 1.18 : 1;
  const fallback = Math.round(base * paceMultiplier * priorityMultiplier);
  let suggested = famousStayMinutes(place, fallback);
  if (WHOLE_DAY_NAMES.test(place.name)) suggested = Math.max(suggested, 300);
  return Math.max(Math.round(suggested / 5) * 5, 30);
}

export function heatScore(place: TravelPlace, preferred: Interest[] = []): number {
  let score = place.planningPriority === "primary" ? 42 : 0;
  if (preferred.includes(place.interest)) score += 18;
  if (/博物馆|美术馆|纪念馆|故宫|古城|古镇|园|寺|塔|山|湖|海|乐园|步行街/.test(place.name)) score += 14;
  if (place.rating != null) score += place.rating * 3;
  if (/酒店|宾馆|停车场|游客中心|服务区/.test(place.name)) score -= 45;
  return knowledgeHeat(place, score);
}

export function addDays(date: string, days: number): string {
  const match = date.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return date;
  const parsed = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]) + days));
  return parsed.toISOString().slice(0, 10);
}

export function assignDays(input: TravelPlace[], draft: TripDraft): { days: DayAssignment[]; overflow: number } {
  const places = deduplicatePlaces(input);
  const dayCount = Math.max(draft.dayCount, 1);
  const center = draft.destinationCoord ?? places[0]?.coordinate;
  if (!center || places.length === 0) return { days: [], overflow: 0 };

  const ranked = [...places].sort(
    (a, b) => heatScore(b, draft.interests) - heatScore(a, draft.interests)
  );
  const anchorCandidates = ranked.filter((place) => place.interest !== "food" && place.interest !== "night");
  const anchors: TravelPlace[] = [];

  while (anchors.length < dayCount && anchors.length < anchorCandidates.length) {
    const remaining = anchorCandidates.filter((place) => !anchors.includes(place));
    const picked = [...remaining].sort((a, b) => {
      const spreadA = anchors.length === 0
        ? 0
        : Math.min(...anchors.map((anchor) => distanceMeters(anchor.coordinate, a.coordinate)));
      const spreadB = anchors.length === 0
        ? 0
        : Math.min(...anchors.map((anchor) => distanceMeters(anchor.coordinate, b.coordinate)));
      const scoreA = heatScore(a, draft.interests) + Math.min(spreadA / 2500, 36);
      const scoreB = heatScore(b, draft.interests) + Math.min(spreadB / 2500, 36);
      return scoreB - scoreA;
    })[0];
    if (!picked) break;
    anchors.push(picked);
  }

  const days: DayAssignment[] = Array.from({ length: Math.min(dayCount, Math.max(anchors.length, 1)) }, (_, index) => {
    const anchor = anchors[index] ?? null;
    const wholeDay = anchor ? isWholeDay(anchor, draft.pace) : false;
    return {
      stops: anchor ? [anchor] : [],
      anchor,
      date: draft.startDate ? addDays(draft.startDate, index) : "",
      theme: anchor ? `${shortName(anchor.name)}一带` : `第${index + 1}天`,
      wholeDay
    };
  });

  const used = new Set(anchors.map((place) => place.id));
  const daytime = ranked.filter((place) => !used.has(place.id) && place.interest !== "food" && place.interest !== "night");
  const food = ranked.filter((place) => !used.has(place.id) && place.interest === "food");
  const night = ranked.filter((place) => !used.has(place.id) && place.interest === "night");

  for (const pool of [daytime, food, night]) {
    for (const place of pool) {
      const available = days
        .filter((day) => canAccept(day, place, draft.pace))
        .map((day) => ({ day, score: placementScore(day, place, draft.interests) }))
        .sort((a, b) => a.score - b.score)[0]?.day;
      if (!available) continue;
      available.stops.push(place);
      used.add(place.id);
    }
  }

  const nonEmpty = days.filter((day) => day.stops.length > 0);
  return { days: nonEmpty, overflow: Math.max(places.length - used.size, 0) };
}

function canAccept(day: DayAssignment, place: TravelPlace, pace: Pace): boolean {
  if (day.wholeDay) return false;
  if (day.stops.length >= DAILY_TOTAL_LIMIT[pace]) return false;
  if (place.interest === "food" && day.stops.some((item) => item.interest === "food")) return false;
  if (place.interest === "night" && day.stops.some((item) => item.interest === "night")) return false;
  if (place.interest !== "food" && place.interest !== "night") {
    const mainStops = day.stops.filter((item) => item.interest !== "food" && item.interest !== "night").length;
    if (mainStops >= DAILY_MAIN_LIMIT[pace]) return false;
  }
  const sameType = day.stops.filter((item) => item.interest === place.interest).length;
  const typeLimit = pace === "full" ? 2 : 1;
  return sameType < typeLimit;
}

function placementScore(day: DayAssignment, place: TravelPlace, preferred: Interest[]): number {
  const anchor = day.anchor?.coordinate ?? place.coordinate;
  const nearest = Math.min(
    ...day.stops.map((item) => distanceMeters(item.coordinate, place.coordinate)),
    distanceMeters(anchor, place.coordinate)
  );
  const loadPenalty = day.stops.length * 6000;
  const priorityCredit = heatScore(place, preferred) * 35;
  return nearest + loadPenalty - priorityCredit;
}

function isWholeDay(place: TravelPlace, pace: Pace): boolean {
  return visitMinutes(place, pace) >= 300;
}

function deduplicatePlaces(places: TravelPlace[]): TravelPlace[] {
  const unique: TravelPlace[] = [];
  for (const place of places) {
    if (!Number.isFinite(place.coordinate.lat) || !Number.isFinite(place.coordinate.lng)) continue;
    const normalized = place.name.replace(/[\s·•（）()\-—]/g, "").toLowerCase();
    const duplicate = unique.some((candidate) => {
      const other = candidate.name.replace(/[\s·•（）()\-—]/g, "").toLowerCase();
      const similarName = normalized === other || (normalized.length >= 4 && (normalized.includes(other) || other.includes(normalized)));
      return similarName && distanceMeters(candidate.coordinate, place.coordinate) < 500;
    });
    if (!duplicate) unique.push(place);
  }
  return unique;
}

function orderedStops(day: DayAssignment, center: Coord, preferred: Interest[]): TravelPlace[] {
  if (day.wholeDay) return day.stops.slice(0, 1);

  const daytime = day.stops.filter((place) => place.interest !== "food" && place.interest !== "night");
  const foods = day.stops.filter((place) => place.interest === "food");
  const nights = day.stops.filter((place) => place.interest === "night");
  const ordered: TravelPlace[] = [];
  let cursor = center;

  while (daytime.length > 0) {
    const index = daytime
      .map((place, itemIndex) => {
        const best = famousBestTime(place);
        const timeBonus = ordered.length === 0 && (best === "清晨" || best === "上午") ? -30_000 : 0;
        const latePenalty = ordered.length === 0 && (best === "傍晚" || best === "晚上") ? 40_000 : 0;
        return {
          itemIndex,
          score: distanceMeters(cursor, place.coordinate) + timeBonus + latePenalty - heatScore(place, preferred) * 25
        };
      })
      .sort((a, b) => a.score - b.score)[0].itemIndex;
    const picked = daytime.splice(index, 1)[0];
    ordered.push(picked);
    cursor = picked.coordinate;
  }

  if (foods[0]) ordered.splice(Math.min(1, ordered.length), 0, foods[0]);
  ordered.push(...nights);
  return ordered;
}

function openingWindow(place: TravelPlace): { start: number; end: number } | null {
  if (!place.opening) return null;
  const match = place.opening.match(/(\d{1,2})[:：](\d{2})\s*[-–—至]\s*(\d{1,2})[:：](\d{2})/);
  if (!match) return null;
  const start = Number(match[1]) * 60 + Number(match[2]);
  const end = Number(match[3]) * 60 + Number(match[4]);
  return start < end && end <= 1440 ? { start, end } : null;
}

function dateLabel(date: string): string {
  if (!date) return "";
  const parsed = new Date(`${date}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return date;
  const weekday = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][parsed.getDay()];
  return `${date.slice(5).replace("-", "月")}日 ${weekday}`;
}

function shortName(name: string): string {
  return name.replace(/风景名胜区|国家旅游度假区|历史文化街区/g, "").slice(0, 12);
}

export function planItinerary(
  input: TravelPlace[],
  draft: TripDraft,
  actualRoutes?: { from: Coord; to: Coord; minutes: number }[]
): Plan {
  const places = deduplicatePlaces(input);
  if (places.length < 2) throw new Error("还没有足够能落在地图上的地点，请换个目的地或关键词再试。");

  const center = draft.destinationCoord ?? places[0].coordinate;
  const rhythm = DAY_BUDGETS[draft.pace];
  const { days: assignments, overflow } = assignDays(places, draft);
  const days: PlanDay[] = assignments.map((assignment, dayIndex) => {
    const ordered = orderedStops(assignment, center, draft.interests);
    const stops: PlanStop[] = [];
    const route: { from: Coord; to: Coord }[] = [];
    let minutes = rhythm.start;
    let visitTotal = 0;
    let travelTotal = 0;
    let from = center;
    let lunchAdded = false;

    for (const place of ordered) {
      const visit = visitMinutes(place, draft.pace);
      let move = estimateTravelMinutes(from, place.coordinate, draft.transportMode);
      const actual = actualRoutes?.find(
        (item) => distanceMeters(item.from, from) < 300 && distanceMeters(item.to, place.coordinate) < 300
      );
      if (actual) move = actual.minutes;

      minutes += move;
      travelTotal += move;
      route.push({ from, to: place.coordinate });

      if (place.interest === "food") {
        minutes = Math.max(minutes, rhythm.lunch);
        lunchAdded = true;
      } else if (!lunchAdded && stops.length > 0 && minutes < rhythm.lunch && minutes + visit > rhythm.lunch) {
        minutes = rhythm.lunch + rhythm.lunchDuration;
        lunchAdded = true;
      }
      const best = famousBestTime(place);
      if (best === "傍晚") minutes = Math.max(minutes, 17 * 60);
      if (best === "晚上" || place.interest === "night") minutes = Math.max(minutes, 18 * 60 + 30);

      const window = openingWindow(place);
      if (window && minutes < window.start) minutes = window.start;
      const arrivalMinute = minutes;
      minutes += visit;
      visitTotal += visit;

      stops.push({
        place,
        arriveMinute: arrivalMinute,
        leaveMinute: minutes,
        arrivalText: clockText(arrivalMinute),
        departureText: clockText(minutes),
        visitMinutes: visit,
        moveMinutes: move,
        moveFrom: from,
        isPrimary: place === assignment.anchor || heatScore(place, draft.interests) >= 70,
        opening: place.opening,
        ticket: place.ticket,
        note: place === assignment.anchor
          ? assignment.wholeDay
            ? "这处目的地需要大半天到一天，今天不再叠加其他景点。"
            : "今天围绕这里展开，其他停留尽量控制在同一片区。"
          : place.interest === "food"
            ? "正餐和休息留在这段时间。"
            : undefined
      });
      from = place.coordinate;
    }

    const hasNight = ordered.some((place) => place.interest === "night" || famousBestTime(place) === "晚上");
    const ordinaryEnd = hasNight ? rhythm.nightEnd : rhythm.daytimeEnd;
    const overCapacity = minutes > ordinaryEnd;
    const label = dateLabel(assignment.date);
    const title = `${label ? `${label} · ` : ""}${assignment.theme}`;
    const badges = [
      `${stops.length} 处停留`,
      `游览${durationText(visitTotal)}`,
      `移动约${durationText(travelTotal)}`,
      assignment.wholeDay ? "整日主线" : lunchAdded || ordered.some((place) => place.interest === "food") ? "午间有休息" : "午餐留白"
    ];

    return {
      dateLabel: label,
      title,
      stops,
      totalMinutes: Math.max(minutes - rhythm.start, 0),
      visitMinutes: visitTotal,
      travelMinutes: travelTotal,
      availableMinutes: Math.max(ordinaryEnd - rhythm.start, 0),
      overCapacity,
      assessment: overCapacity
        ? "这天仍偏满，建议删掉一个次要停留或调整交通方式。"
        : assignment.wholeDay
          ? "全天只保留一条主线，避免把远郊或大型景区切碎。"
          : `第 ${dayIndex + 1} 天集中在 ${assignment.theme}，包含交通、用餐与缓冲时间。`,
      badges,
      route
    };
  });

  const notes = [
    "每天围绕一个相邻区域展开；核心景点、用餐、短停留与夜间活动按真实可用时段排序。"
  ];
  if (overflow > 0) notes.unshift(`另有 ${overflow} 个候选点没有硬塞进日程，可增加天数或在地图上替换。`);
  if (places.some((place) => place.source.includes("知识库"))) {
    notes.push("部分候选来自离线目的地资料快照；门票、预约与开放信息必须在出发前复核。");
  }

  return { days, generatedAt: new Date().toISOString(), notes, engine: "web-heuristic" };
}

export function bestQuote(quotes: ProviderQuote[]): ProviderQuote | undefined {
  return (
    quotes
      .filter((quote) => quote.amountCNY != null && quote.kind !== "demo")
      .sort((a, b) => Number(Boolean(a.isStale)) - Number(Boolean(b.isStale)) || (a.amountCNY ?? 0) - (b.amountCNY ?? 0))[0] ?? quotes[0]
  );
}

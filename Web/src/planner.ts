import { enrichPlace, famousBestTime, famousStayMinutes, knowledgeHeat } from "./knowledge";
import {
  DAY_BUDGETS, INTEREST_MINUTES, clockText, durationText, effectiveParty,
  type Coord, type Interest, type Pace, type Plan, type PlanDay, type PlanStop,
  type ProviderQuote, type TravelPlace, type TripDraft, type PlanLockState, type PlanBreak
} from "./types";

const MAIN_LIMIT: Record<Pace, number> = { relaxed: 2, balanced: 3, full: 4 };
const isMain = (p: TravelPlace) => p.interest !== "food" && p.interest !== "night";
const shortName = (name: string) => name.replace(/风景名胜区|国家旅游度假区|历史文化街区/g, "").slice(0, 12);
const rounded = (n: number) => Math.ceil(n / 5) * 5;
type RoadTime = { from: Coord; to: Coord; minutes: number };
export interface DayAssignment { stops: TravelPlace[]; anchor: TravelPlace | null; date: string; theme: string; wholeDay: boolean }

export function distanceMeters(from: Coord, to: Coord): number {
  const rad = (v: number) => v * Math.PI / 180;
  const a = Math.sin(rad(to.lat - from.lat) / 2) ** 2 + Math.cos(rad(from.lat)) * Math.cos(rad(to.lat)) * Math.sin(rad(to.lng - from.lng) / 2) ** 2;
  return 12_742_000 * Math.asin(Math.sqrt(Math.min(1, a)));
}

export function estimateTravelMinutes(from: Coord, to: Coord, mode: TripDraft["transportMode"]): number {
  const km = distanceMeters(from, to) / 1000;
  if (km < 0.08) return 0;
  // Straight-line distances need a detour allowance. Never cap a long transfer at 120 min.
  const [speed, overhead, detour] = { walking: [4.2, 3, 1.25], transit: [18, 12, 1.35], driving: [27, 9, 1.3] }[mode];
  return rounded(km * detour / speed * 60 + overhead);
}

export function visitMinutes(place: TravelPlace, pace: Pace): number {
  const base = famousStayMinutes(place, INTEREST_MINUTES[place.interest] ?? 105);
  const longVisit = base >= 300 || /主题乐园|迪士尼|环球影城|森林世界/.test(place.name);
  return rounded(Math.max(longVisit ? Math.max(base, 360) : base * (pace === "relaxed" ? 1.1 : pace === "full" ? 0.95 : 1), 30));
}

export function heatScore(place: TravelPlace, preferred: Interest[] = []): number {
  // A guide's “must see” is a weak recommendation, never the user's hard constraint.
  let score = 25 + (preferred.includes(place.interest) ? 55 : 0);
  if (place.planningPriority === "primary") score += 5;
  if (place.rating != null) score += Math.max(0, Math.min(place.rating, 5) - 3) * 3;
  if (/酒店|宾馆|停车场|游客中心|服务区/.test(place.name)) score -= 100;
  return knowledgeHeat(place, score);
}

export function addDays(date: string, days: number): string {
  const m = date.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return m ? new Date(Date.UTC(+m[1], +m[2] - 1, +m[3] + days)).toISOString().slice(0, 10) : date;
}

export function timeMinute(value?: string): number | undefined {
  const m = value?.match(/^(\d{1,2}):(\d{2})$/);
  return m && +m[1] < 24 && +m[2] < 60 ? +m[1] * 60 + +m[2] : undefined;
}

export function planningWindow(draft: TripDraft, index: number, hasNight = false) {
  const rhythm = DAY_BUDGETS[draft.pace];
  const start = index === 0 ? Math.max(rhythm.start, timeMinute(draft.firstDayStart) ?? rhythm.start) : rhythm.start;
  const end = index === draft.dayCount - 1
    ? Math.min(hasNight ? rhythm.nightEnd : rhythm.daytimeEnd, timeMinute(draft.lastDayEnd) ?? 1440)
    : hasNight ? rhythm.nightEnd : rhythm.daytimeEnd;
  return { start, end };
}

function dateLabel(date: string) {
  if (!date) return "";
  const d = new Date(`${date}T12:00:00`);
  return Number.isNaN(d.getTime()) ? date : `${date.slice(5).replace("-", "月")}日 周${"日一二三四五六"[d.getDay()]}`;
}

/** Deliberately bounded parser. Unknown rules remain visible as unverified data. */
export function openingWindows(text: string | undefined, date: string): { windows: [number, number][]; known: boolean } {
  if (!text) return { windows: [[0, 1440]], known: false };
  if (/24\s*\/\s*7|全天开放|24小时/.test(text)) return { windows: [[0, 1440]], known: true };
  const weekday = date ? new Date(`${date}T12:00:00`).getDay() : -1;
  const zhDay = "日一二三四五六"[weekday];
  if (weekday >= 0 && new RegExp(`(?:周|星期)${zhDay}[^;；。\\d]{0,5}(?:闭馆|休馆|关闭|不开放)`).test(text)) return { windows: [], known: true };
  if (weekday >= 0 && /(?:周|星期)一闭馆/.test(text) && weekday === 1) return { windows: [], known: true };
  const names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];
  const clauses = text.split(/[;；]/);
  const ranges: [number, number][] = [];
  let matchedDay = false;
  let hasWeeklyRule = false;
  let explicitOff = false;
  for (const clause of clauses) {
    const rule = clause.match(/\b((?:Mo|Tu|We|Th|Fr|Sa|Su)(?:\s*[-,]\s*(?:Mo|Tu|We|Th|Fr|Sa|Su))*)\b/);
    if (rule) {
      // A closure-only note does not establish opening rules for the other six days.
      hasWeeklyRule ||= /\d{1,2}[:：]\d{2}\s*[-–—至]\s*\d{1,2}[:：]\d{2}/.test(clause);
      if (weekday < 0) continue;
      const active = new Set<number>();
      for (const part of rule[1].split(",")) {
        const [a, b] = part.trim().split(/\s*-\s*/).map(n => names.indexOf(n));
        if (b === undefined) active.add(a);
        else for (let k = a, count = 0; count < 7; k = (k + 1) % 7, count++) { active.add(k); if (k === b) break; }
      }
      if (!active.has(weekday)) continue;
      matchedDay = true;
      if (/off|closed/.test(clause)) { explicitOff = true; continue; }
    }
    for (const m of clause.matchAll(/(\d{1,2})[:：](\d{2})\s*[-–—至]\s*(\d{1,2})[:：](\d{2})/g)) {
      const start = +m[1] * 60 + +m[2], end = +m[3] * 60 + +m[4];
      if (start < end && end <= 1440 && +m[2] < 60 && +m[4] < 60) ranges.push([start, end]);
    }
  }
  if (explicitOff || (hasWeeklyRule && weekday >= 0 && !matchedDay && ranges.length === 0)) return { windows: [], known: true };
  return ranges.length ? { windows: ranges.sort((a, b) => a[0] - b[0]), known: true } : { windows: [[0, 1440]], known: false };
}

function samePlace(a: TravelPlace, b: TravelPlace, destination: string): boolean {
  if (a.id === b.id) return true;
  const clean = (name: string) => name.replace(/[\s·•（）()\-—]/g, "").toLowerCase();
  const city = clean(destination).replace(/市$/, "");
  const canonical = (name: string) => {
    let value = clean(name);
    if (city && value.startsWith(city)) value = value.slice(city.length).replace(/^市/, "");
    // A city or national prefix is an alias only when the actual venue name
    // and location agree. Never collapse a museum's separately named galleries.
    return value.replace(/^中国/, "");
  };
  const name = canonical(a.name);
  return name.length >= 3 && name === canonical(b.name) && distanceMeters(a.coordinate, b.coordinate) < 500;
}

function deduplicatePlaces(input: TravelPlace[], draft: TripDraft, lockedIDs: string[] = []) {
  const result: TravelPlace[] = [];
  const priority = (p: TravelPlace) => lockedIDs.includes(p.id) ? 2 : draft.mustVisitIDs?.includes(p.id) ? 1 : 0;
  for (const place of [...input].sort((a, b) => priority(b) - priority(a))) {
    const { lat, lng } = place.coordinate;
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 85 || Math.abs(lng) > 180) continue;
    if (result.some(p => samePlace(p, place, draft.destination))) continue;
    result.push(enrichPlace(place));
  }
  return result;
}

/** One scheduler powers generation, edits, locks and date changes. No second clock. */
export function scheduleDay(
  places: TravelPlace[], draft: TripDraft, dayIndex: number,
  actualRoutes: RoadTime[] = [], locks: PlanLockState = { visits: [] }
): PlanDay {
  const rhythm = DAY_BUDGETS[draft.pace];
  const hasNight = places.some(p => p.interest === "night" || (p.interest === "food" && famousBestTime(p) === "晚上"));
  const { start, end } = planningWindow(draft, dayIndex, hasNight);
  const date = draft.startDate ? addDays(draft.startDate, dayIndex) : "";
  const label = dateLabel(date);
  const party = effectiveParty(draft);
  const needsRest = party.seniorTravelers > 0 || party.childrenAges.some(age => age <= 8) || party.mobilityNeed !== "none";
  const breaks: PlanBreak[] = [], warnings: string[] = [], stops: PlanStop[] = [], route: PlanDay["route"] = [];
  if (!acceptableShape(places, draft)) warnings.push("当天游览量超过所选节奏，或整日景区与其他地点重叠");
  let cursor = start, from = draft.destinationCoord ?? places[0]?.coordinate;
  let travelTotal = 0, visitTotal = 0;
  let lunch = start >= 14 * 60, dinner = start >= 20 * 60;
  const pause = (minutes: number, kind: PlanBreak["kind"], title: string, beforeStopID?: string) => {
    if (minutes <= 0) return;
    breaks.push({ kind, startMinute: cursor, endMinute: cursor + minutes, label: title, beforeStopID });
    cursor += minutes;
  };
  const waitUntil = (target: number, title: string, beforeStopID: string) => {
    // An opening/booking wait may already contain lunchtime; do not defer lunch to late afternoon.
    const lunchStart = Math.max(cursor, rhythm.lunch);
    if (!lunch && cursor < 14 * 60 && lunchStart + rhythm.lunchDuration <= target) {
      pause(lunchStart - cursor, "wait", title, beforeStopID);
      pause(rhythm.lunchDuration, "meal", "午餐与休息 · 等待时就近安排", beforeStopID);
      lunch = true;
    }
    pause(target - cursor, "wait", title, beforeStopID);
  };
  for (const place of places) {
    const duration = visitMinutes(place, draft.pace);
    const lock = locks.visits.find(v => v.placeID === place.id && v.dayIndex === dayIndex);
    let visit = lock?.arriveMinute != null && lock.leaveMinute != null ? Math.max(30, lock.leaveMinute - lock.arriveMinute) : duration;
    const actual = actualRoutes.find(r => from && distanceMeters(r.from, from) < 80 && distanceMeters(r.to, place.coordinate) < 80);
    let move = from ? actual?.minutes ?? estimateTravelMinutes(from, place.coordinate, draft.transportMode) : 0;
    if (!Number.isFinite(move) || move < 0) move = from ? estimateTravelMinutes(from, place.coordinate, draft.transportMode) : 0;
    if (needsRest && draft.transportMode === "walking") move = rounded(move * 1.2);
    if (from) route.push({ from, to: place.coordinate });
    travelTotal += move;
    cursor += move;
    const opening = openingWindows(place.opening, date);
    const firstWindow = opening.windows.find(([a, b]) => {
      const arrival = Math.max(cursor, a);
      const meal = !lunch && visit >= 240 && arrival < 13 * 60 && arrival + visit > 13 * 60 ? rhythm.lunchDuration : 0;
      return arrival + visit + meal <= b;
    });
    if (firstWindow && cursor < firstWindow[0]) waitUntil(firstWindow[0], "等待开放", place.id);
    const ownLunch = place.interest === "food" && famousBestTime(place) !== "晚上" && cursor < 15 * 60;
    const onSiteLunch = !lunch && visit >= 240 && cursor < 13 * 60 && cursor + visit > 13 * 60;
    if (!lunch && !ownLunch && !onSiteLunch && cursor + visit > 14 * 60 && cursor < 15 * 60 && end >= 13 * 60) {
      if (cursor < rhythm.lunch) pause(rhythm.lunch - cursor, "wait", "附近自由活动", place.id);
      pause(rhythm.lunchDuration, "meal", "午餐与休息 · 就近安排", place.id);
      lunch = true;
    }
    if (ownLunch) {
      if (cursor < rhythm.lunch) pause(rhythm.lunch - cursor, "wait", "附近自由活动", place.id);
      lunch = true;
    }
    const best = famousBestTime(place);
    // "Best at sunset" is a preference, not a closure. Only night activities / dinner own a time window.
    const preferredStart = place.interest === "night" ? 18 * 60 + 30 : place.interest === "food" && best === "晚上" ? 17 * 60 + 30 : 0;
    if (preferredStart && !dinner && end > 19 * 60) {
      if (cursor < 17 * 60 + 30) pause(17 * 60 + 30 - cursor, "wait", "自由活动 · 可回住处休息", place.id);
      if (place.interest !== "food") pause(60, "meal", "晚餐 · 就近安排", place.id);
      dinner = true;
    }
    if (cursor < preferredStart) pause(preferredStart - cursor, "wait", "等待适合的游览时段", place.id);
    const mealInside = onSiteLunch ? rhythm.lunchDuration : 0;
    const lockedSpan = lock?.arriveMinute != null && lock.leaveMinute != null ? lock.leaveMinute - lock.arriveMinute : undefined;
    const span = lockedSpan ?? visit + mealInside;
    if (lockedSpan != null && mealInside) visit = Math.max(30, lockedSpan - mealInside);
    const fitting = opening.windows.find(([a, b]) => Math.max(cursor, a) + span <= b);
    if (!fitting) warnings.push(`${place.name}：${opening.windows.length ? "可用时间不足以在开放时段内游览完" : "资料标注当天不开放"}`);
    else if (cursor < fitting[0]) waitUntil(fitting[0], "等待开放", place.id);
    if (lock?.arriveMinute != null) {
      if (cursor > lock.arriveMinute) warnings.push(`${place.name}：锁定时段与前序移动冲突，请调整前一站或解锁`);
      else waitUntil(lock.arriveMinute, "锁定时段前的自由时间", place.id);
    }
    const arrive = cursor;
    cursor += span;
    if (opening.known && opening.windows.length && !opening.windows.some(([a, b]) => arrive >= a && cursor <= b) && !warnings.some(w => w.startsWith(`${place.name}：`))) {
      warnings.push(`${place.name}：锁定或移动后的时段超出开放时间`);
    }
    if (onSiteLunch) {
      const lunchStart = Math.max(arrive, rhythm.lunch);
      breaks.push({ kind: "meal", startMinute: lunchStart, endMinute: lunchStart + mealInside, label: "景区内午餐与休息", beforeStopID: place.id });
      lunch = true;
    }
    const issues = warnings.filter(w => w.startsWith(`${place.name}：`));
    const explanation = [
      draft.mustVisitIDs?.includes(place.id) ? "你指定的必去地点" : stops.filter(s => isMain(s.place)).length === 0 && isMain(place) ? "今天的主要游览" : "与当天路线衔接",
      onSiteLunch ? "已在停留中留出午餐时间" : null,
      !opening.known ? "开放时间待核实" : "开放资料为快照，预约与临时调整需核实",
      ...issues
    ].filter(Boolean).join("；");
    stops.push({ place, arriveMinute: arrive, leaveMinute: cursor, arrivalText: clockText(arrive), departureText: clockText(cursor), visitMinutes: visit, moveMinutes: move, moveSource: actual ? "routed" : "estimate", moveFrom: from, isPrimary: isMain(place) && (stops.filter(s => isMain(s.place)).length === 0 || Boolean(draft.mustVisitIDs?.includes(place.id))), opening: place.opening, ticket: place.ticket, note: explanation });
    visitTotal += visit;
    from = place.coordinate;
    pause(rounded((visit + move) * rhythm.buffer) + (needsRest ? 10 : 0), "buffer", needsRest ? "休息与机动 · 照顾同行节奏" : "机动时间 · 排队、找路与休息");
  }
  if (!lunch && places.length && cursor >= 12 * 60 + 30 && end >= 14 * 60) {
    pause(rhythm.lunchDuration, "meal", "午餐与休息 · 游览后就近安排");
  }
  if (cursor > end && places.length) warnings.push(`预计 ${clockText(cursor)} 结束，超过当天 ${clockText(end)} 的可用时间`);
  if (end <= start) warnings.push("抵达与离开时间之间没有可用游览时段");
  const anchor = places.find(isMain) ?? places[0];
  const wholeDay = places.some(p => visitMinutes(p, draft.pace) >= 300);
  const mealMinutes = breaks.filter(b => b.kind === "meal").reduce((sum, b) => sum + b.endMinute - b.startMinute, 0);
  const bufferMinutes = breaks.filter(b => b.kind === "buffer").reduce((sum, b) => sum + b.endMinute - b.startMinute, 0);
  const overCapacity = warnings.length > 0;
  return {
    dateLabel: label, title: `${label ? `${label} · ` : ""}${anchor ? `${shortName(anchor.name)}一带` : "留给自由安排"}`,
    stops, route, totalMinutes: Math.max(0, cursor - start), visitMinutes: visitTotal, travelMinutes: travelTotal,
    availableMinutes: Math.max(0, end - start), overCapacity, startMinute: start, endMinute: end, mealMinutes, bufferMinutes,
    freeMinutes: Math.max(0, end - cursor), breaks, warnings,
    assessment: overCapacity ? warnings[0] : !places.length ? "没有适合当前时间和移动条件的候选，可调整时段或交通方式。" : wholeDay ? "这处游览占据大半天，今天只保留这一条主线。" : `游览、移动、用餐与机动都已计入，${clockText(cursor)} 后可自由安排。`,
    badges: [`${stops.length} 处停留`, `移动约${durationText(travelTotal)}`, wholeDay ? "整日主线" : `${bufferMinutes} 分钟机动`]
  };
}

function acceptableShape(places: TravelPlace[], draft: TripDraft) {
  const main = places.filter(isMain);
  if (main.length > MAIN_LIMIT[draft.pace]) return false;
  if (main.some(p => visitMinutes(p, draft.pace) >= 300) && places.length > 1) return false;
  return places.filter(p => p.interest === "food").length <= 1 && places.filter(p => p.interest === "night").length <= 1;
}

function insertion(
  existing: TravelPlace[], place: TravelPlace, draft: TripDraft, dayIndex: number,
  actual: RoadTime[], locks: PlanLockState
): { places: TravelPlace[]; day: PlanDay; cost: number } | null {
  if (!acceptableShape([...existing, place], draft)) return null;
  let best: { places: TravelPlace[]; day: PlanDay; cost: number } | null = null;
  for (let index = 0; index <= existing.length; index++) {
    const next = [...existing.slice(0, index), place, ...existing.slice(index)];
    // Eating and night activities are time windows, not an arbitrary alternating template.
    if (next.some((p, i) => p.interest === "night" && next.slice(i + 1).some(isMain))) continue;
    const day = scheduleDay(next, draft, dayIndex, actual, locks);
    if (day.overCapacity) continue;
    const maxLeg = draft.transportMode === "walking" ? 55 : draft.pace === "relaxed" ? 65 : 90;
    if (day.stops.some((s, i) => (s.moveMinutes ?? 0) > (i === 0 ? maxLeg * 1.5 : maxLeg))) continue;
    // Interest drives selection. Distance and elapsed time drive placement.
    const timingPenalty = day.stops.reduce((sum, stop) => {
      const bestTime = famousBestTime(stop.place);
      return sum + (bestTime === "上午" && (stop.arriveMinute ?? 0) > 780 ? 12 : bestTime === "傍晚" && (stop.arriveMinute ?? 0) < 960 ? 8 : 0);
    }, 0);
    const waiting = day.breaks?.filter(b => b.kind === "wait").reduce((sum, b) => sum + b.endMinute - b.startMinute, 0) ?? 0;
    const cost = day.travelMinutes * 2.5 + waiting * 0.8 + day.totalMinutes * 0.07 + existing.filter(p => p.interest === place.interest).length * 30 + timingPenalty;
    if (!best || cost < best.cost) best = { places: next, day, cost };
  }
  return best;
}

export function planItinerary(
  input: TravelPlace[], draft: TripDraft, actualRoutes: RoadTime[] = [],
  fixed: { previous?: Plan | null; locks?: PlanLockState } = {}
): Plan {
  const locks = fixed.locks ?? { visits: [] };
  const lockedPlaces = fixed.previous?.days.flatMap(d => d.stops).filter(s => locks.visits.some(lock => lock.placeID === s.place.id)).map(s => s.place) ?? [];
  const places = deduplicatePlaces([...lockedPlaces, ...input], draft, locks.visits.map(lock => lock.placeID));
  if (!places.length) throw new Error("还没有可用的地点，请换个目的地或添加一个地点。");
  const dayCount = Math.max(1, Math.min(14, Math.floor(draft.dayCount || 1)));
  draft = { ...draft, dayCount };
  const assigned: TravelPlace[][] = Array.from({ length: dayCount }, () => []);
  const used = new Set<string>();
  for (const lock of [...locks.visits].sort((a, b) => a.orderIndex - b.orderIndex)) {
    const place = fixed.previous?.days.flatMap(d => d.stops).find(s => s.place.id === lock.placeID)?.place ?? places.find(p => p.id === lock.placeID);
    if (place && !used.has(place.id)) { assigned[Math.min(lock.dayIndex, dayCount - 1)].push(enrichPlace(place)); used.add(place.id); }
  }
  const required = new Set(draft.mustVisitIDs ?? []);
  const excluded = new Set(draft.excludedPlaceIDs ?? []);
  const excludedPlaces = input.filter(p => excluded.has(p.id));
  const availableDays = (place: TravelPlace) => assigned.reduce((sum, _, i) => sum + Number(openingWindows(place.opening, draft.startDate ? addDays(draft.startDate, i) : "").windows.length > 0), 0);
  const ranked = places.filter(p => !excludedPlaces.some(excludedPlace => samePlace(p, excludedPlace, draft.destination))).sort((a, b) =>
    Number(required.has(b.id)) - Number(required.has(a.id)) ||
    heatScore(b, draft.interests) - heatScore(a, draft.interests) ||
    availableDays(a) - availableDays(b) || a.id.localeCompare(b.id));
  // Choose the next *feasible insertion*, not the next entry in a popularity list.
  // Diminishing returns reward different experiences; a nearby place can beat a remote famous one.
  for (let pass = 0; pass < ranked.length; pass++) {
    let choice: { index: number; place: TravelPlace; candidate: NonNullable<ReturnType<typeof insertion>>; score: number } | null = null;
    const baselines = assigned.map((day, i) => scheduleDay(day, draft, i, actualRoutes, locks));
    for (const place of ranked) {
      if (used.has(place.id)) continue;
      if (!required.has(place.id) && (place.interest === "night" || place.interest === "family") && !draft.interests.includes(place.interest)) continue;
      for (let d = 0; d < dayCount; d++) {
        const candidate = insertion(assigned[d], place, draft, d, actualRoutes, locks);
        if (!candidate) continue;
        const extraTravel = candidate.day.travelMinutes - baselines[d].travelMinutes;
        const repeats = assigned[d].filter(p => p.interest === place.interest).length;
        const value = heatScore(place, draft.interests) + (isMain(place) ? 10 : 0);
        const score = (required.has(place.id) ? 10000 : 0) + value - extraTravel * 0.8 - repeats * 22
          - assigned[d].length * 7 - Math.max(0, candidate.day.totalMinutes - baselines[d].totalMinutes) * 0.025;
        if (score > 0 && (!choice || score > choice.score)) choice = { index: d, place, candidate, score };
      }
    }
    if (!choice) break;
    assigned[choice.index] = choice.candidate.places;
    used.add(choice.place.id);
  }
  const days = assigned.map((p, i) => scheduleDay(p, draft, i, actualRoutes, locks));
  const alternatives = ranked.filter(p => !used.has(p.id)).map(place => {
    let reason = "当前天数内会挤占游览、吃饭或机动时间，留作备选";
    if (availableDays(place) === 0) reason = "开放资料与所选日期不符，需先核实开放或换日期";
    else if ((place.interest === "night" || place.interest === "family") && !draft.interests.includes(place.interest) && !required.has(place.id)) reason = "与你这次的兴趣选择不符，按需加入";
    else if (visitMinutes(place, draft.pace) >= 300) reason = "需要单独留出大半天，现有日程放不下";
    else if (draft.destinationCoord && estimateTravelMinutes(draft.destinationCoord, place.coordinate, draft.transportMode) > 80) reason = "当前移动方式下接驳偏长，建议换交通方式或单独安排";
    return { place, reason, required: required.has(place.id) };
  });
  const notes = ["攻略提供停留、时段与地点信息；具体顺序按你的日期、偏好、交通和可用时间重新计算。", "移动为直线距离加绕行与换乘的估算，起点暂用目的地中心；不代表实时路况。"];
  if (alternatives.length) notes.unshift(`另有 ${alternatives.length} 个候选点没有硬塞进日程，已保留在备选中。`);
  if (alternatives.some(p => p.required)) notes.unshift("有必去地点无法满足当前约束，请在备选中查看原因，调整时间或替换其他地点。");
  if (locks.visits.some(l => l.dayIndex >= dayCount)) notes.unshift("缩短天数后，原锁定日期已不存在；请核对移至最后一天的锁定地点。");
  return { days, alternatives, notes, generatedAt: new Date().toISOString(), engine: "web-heuristic" };
}

export function assignDays(input: TravelPlace[], draft: TripDraft): { days: DayAssignment[]; overflow: number } {
  const plan = planItinerary(input, draft);
  return { days: plan.days.map((day, i) => ({ stops: day.stops.map(s => s.place), anchor: day.stops[0]?.place ?? null, date: draft.startDate ? addDays(draft.startDate, i) : "", theme: day.title, wholeDay: day.badges.includes("整日主线") })), overflow: plan.alternatives?.length ?? 0 };
}

export function bestQuote(quotes: ProviderQuote[]): ProviderQuote | undefined {
  return quotes.filter(q => q.amountCNY != null && q.kind !== "demo").sort((a, b) => Number(Boolean(a.isStale)) - Number(Boolean(b.isStale)) || (a.amountCNY ?? 0) - (b.amountCNY ?? 0))[0] ?? quotes[0];
}

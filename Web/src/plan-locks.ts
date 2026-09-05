import {
  DAY_BUDGETS,
  clockText,
  durationText,
  type LockedVisit,
  type Plan,
  type PlanDay,
  type PlanLockState,
  type PlanStop,
  type TripDraft
} from "./types";
import { addDays, distanceMeters, estimateTravelMinutes, visitMinutes } from "./planner";

export const EMPTY_PLAN_LOCKS: PlanLockState = { visits: [] };

const normalized = (value: string) => value.replace(/[\s·・()（）\-—_]/g, "").toLowerCase();

export function visitIsLocked(locks: PlanLockState, placeID: string): boolean {
  return locks.visits.some((lock) => lock.placeID === placeID);
}

export function toggleVisitLock(locks: PlanLockState, plan: Plan, dayIndex: number, stopIndex: number): PlanLockState {
  const stop = plan.days[dayIndex]?.stops[stopIndex];
  if (!stop) return locks;
  if (visitIsLocked(locks, stop.place.id)) {
    return { ...locks, visits: locks.visits.filter((lock) => lock.placeID !== stop.place.id) };
  }
  return {
    ...locks,
    visits: [
      ...locks.visits,
      {
        placeID: stop.place.id,
        placeName: stop.place.name,
        dayIndex,
        orderIndex: stopIndex,
        arriveMinute: stop.arriveMinute,
        leaveMinute: stop.leaveMinute
      }
    ]
  };
}

function sameStop(stop: PlanStop, lock: LockedVisit): boolean {
  return stop.place.id === lock.placeID || normalized(stop.place.name) === normalized(lock.placeName);
}

function dateLabel(date: string): string {
  const parsed = new Date(`${date}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return date;
  const weekday = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][parsed.getDay()];
  return `${date.slice(5).replace("-", "月")}日 ${weekday}`;
}

function themeFromTitle(title: string): string {
  return title.replace(/^\d{1,2}月\d{1,2}日\s+周[一二三四五六日]\s*·\s*/, "");
}

function rebuildDay(template: PlanDay, stops: PlanStop[], draft: TripDraft, dayIndex: number, locks: PlanLockState): PlanDay {
  const rhythm = DAY_BUDGETS[draft.pace];
  const lockByID = new Map(locks.visits.map((lock) => [lock.placeID, lock]));
  let minute = rhythm.start;
  let from = draft.destinationCoord ?? stops[0]?.place.coordinate;
  let travelMinutes = 0;
  let visitTotal = 0;
  const route: PlanDay["route"] = [];
  const rebuilt = stops.map((old): PlanStop => {
    const move = from ? estimateTravelMinutes(from, old.place.coordinate, draft.transportMode) : 0;
    if (from) route.push({ from, to: old.place.coordinate });
    minute += move;
    travelMinutes += move;
    const lock = lockByID.get(old.place.id) ?? locks.visits.find((item) => normalized(item.placeName) === normalized(old.place.name));
    const requestedArrival = lock?.dayIndex === dayIndex ? lock.arriveMinute : undefined;
    const arrival = requestedArrival != null && requestedArrival >= minute ? requestedArrival : minute;
    const duration = lock?.leaveMinute != null && lock.arriveMinute != null
      ? Math.max(lock.leaveMinute - lock.arriveMinute, 30)
      : visitMinutes(old.place, draft.pace);
    const departure = arrival + duration;
    minute = departure;
    visitTotal += duration;
    const result: PlanStop = {
      ...old,
      arriveMinute: arrival,
      leaveMinute: departure,
      arrivalText: clockText(arrival),
      departureText: clockText(departure),
      visitMinutes: duration,
      moveMinutes: move,
      moveFrom: from,
      note: requestedArrival != null && requestedArrival < arrival
        ? `${old.note ? `${old.note} ` : ""}锁定时段与前序移动冲突，已顺延至最早可达时间。`
        : old.note
    };
    from = old.place.coordinate;
    return result;
  });
  const hasNight = rebuilt.some((stop) => stop.place.interest === "night");
  const end = hasNight ? rhythm.nightEnd : rhythm.daytimeEnd;
  const overCapacity = minute > end;
  const date = draft.startDate ? dateLabel(addDays(draft.startDate, dayIndex)) : template.dateLabel;
  const theme = themeFromTitle(template.title) || `第${dayIndex + 1}天`;
  return {
    ...template,
    dateLabel: date,
    title: date ? `${date} · ${theme}` : theme,
    stops: rebuilt,
    route,
    totalMinutes: Math.max(minute - rhythm.start, 0),
    visitMinutes: visitTotal,
    travelMinutes,
    availableMinutes: Math.max(end - rhythm.start, 0),
    overCapacity,
    assessment: overCapacity
      ? "这天在保留锁定内容后偏满；可以解锁一个时段，或把次要停留移到别天。"
      : `第 ${dayIndex + 1} 天保留了你的确定项，其余时间按新的条件重新衔接。`,
    badges: [
      `${rebuilt.length} 处停留`,
      `游览${durationText(visitTotal)}`,
      `移动约${durationText(travelMinutes)}`,
      locks.visits.some((lock) => lock.dayIndex === dayIndex) ? "含锁定时段" : "时间已重算"
    ]
  };
}

/** Reinsert fixed visits into a newly generated plan, preserving day, order and feasible time. */
export function applyLockedVisits(generated: Plan, previous: Plan | null, locks: PlanLockState, draft: TripDraft): Plan {
  if (!previous || locks.visits.length === 0 || generated.days.length === 0) return generated;
  const previousStops = previous.days.flatMap((day) => day.stops);
  const dayStops = generated.days.map((day) => [...day.stops]);
  for (const lock of [...locks.visits].sort((a, b) => a.dayIndex - b.dayIndex || a.orderIndex - b.orderIndex)) {
    const preserved = previousStops.find((stop) => sameStop(stop, lock));
    if (!preserved) continue;
    for (const stops of dayStops) {
      const index = stops.findIndex((stop) => sameStop(stop, lock));
      if (index >= 0) stops.splice(index, 1);
    }
    const dayIndex = Math.min(Math.max(lock.dayIndex, 0), dayStops.length - 1);
    dayStops[dayIndex].splice(Math.min(Math.max(lock.orderIndex, 0), dayStops[dayIndex].length), 0, preserved);
  }
  return {
    ...generated,
    days: generated.days.map((day, index) => rebuildDay(day, dayStops[index], draft, index, locks)),
    notes: [...generated.notes, "带锁标记的景点保留在原来的日期、顺序与可行时段；其余内容围绕它们重新铺开。"]
  };
}

/** Keep the current itinerary exactly in place while recalculating dates and travel time. */
export function rebaseExistingPlan(previous: Plan, draft: TripDraft, locks: PlanLockState): Plan {
  return {
    ...previous,
    generatedAt: new Date().toISOString(),
    days: previous.days.map((day, index) => rebuildDay(day, day.stops, draft, index, locks)),
    notes: [...previous.notes.filter((note) => !note.startsWith("本次只调整")), "本次只调整日期、人数、预算或移动条件；景点与日序没有重排。"]
  };
}

export interface DraftChangeImpact {
  key: keyof TripDraft;
  title: string;
  detail: string;
  scope: "quotes" | "schedule" | "itinerary";
}

export function draftChangeImpacts(before: TripDraft, after: TripDraft): DraftChangeImpact[] {
  const impacts: DraftChangeImpact[] = [];
  const add = (key: keyof TripDraft, title: string, detail: string, scope: DraftChangeImpact["scope"]) => {
    if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) impacts.push({ key, title, detail, scope });
  };
  add("startDate", "日期", "住宿、去返程、门票价格会重新查询；每天地点顺序保留。", "quotes");
  add("travelers", "同行人数", "价格与房间数量重新计算；路线不变。", "quotes");
  add("budgetPerPerson", "人均预算", "费用判断与推荐排序更新；已锁定选择不变。", "quotes");
  add("origin", "出发地", "去返程班次重新查询；市内行程不变。", "quotes");
  add("longDistanceMode", "抵达偏好", "交通推荐更新；锁定班次不变。", "quotes");
  add("skipAccommodation", "住宿", "住宿模块与相关费用更新。", "quotes");
  add("skipTransport", "大交通", "去返程模块与相关费用更新。", "quotes");
  add("transportMode", "市内移动", "地点顺序保留，移动耗时与当天结束时间重算。", "schedule");
  add("pace", "游览节奏", "地点顺序保留，停留时长重算；锁定时段优先。", "schedule");
  add("dayCount", "旅行天数", "未锁定地点会重新分配；锁定地点保留在可用日期内。", "itinerary");
  add("interests", "兴趣偏好", "未锁定候选会重新筛选与分组。", "itinerary");
  add("destination", "目的地", "将开始一段新的旅行，当前锁定只属于原目的地。", "itinerary");
  return impacts;
}

export function routeDistance(day: PlanDay): number {
  return day.route.reduce((sum, segment) => sum + distanceMeters(segment.from, segment.to), 0);
}

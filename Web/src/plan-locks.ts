import {
  type LockedVisit,
  type Plan,
  type PlanDay,
  type PlanLockState,
  type PlanStop,
  type TripDraft
} from "./types";
import { scheduleDay, distanceMeters } from "./planner";

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

function rebuildDay(template: PlanDay, stops: PlanStop[], draft: TripDraft, dayIndex: number, locks: PlanLockState): PlanDay {
  return scheduleDay(stops.map(stop => stop.place), draft, dayIndex, [], locks);
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
  add("pace", "游览节奏", "在原天数内重新分配游览与休息；锁定内容保留。", "itinerary");
  add("dayCount", "旅行天数", "未锁定地点会重新分配；锁定地点保留在可用日期内。", "itinerary");
  add("interests", "兴趣偏好", "未锁定候选会重新筛选与分组。", "itinerary");
  add("destination", "目的地", "将开始一段新的旅行，当前锁定只属于原目的地。", "itinerary");
  add("firstDayStart", "首日开始时间", "从抵达安顿后开始安排，放不下的地点保留为备选。", "itinerary");
  add("lastDayEnd", "末日结束时间", "在离开前结束游览，放不下的地点保留为备选。", "itinerary");
  add("party", "同行需要", "儿童、长辈和行动需要会增加休息与步行时间。", "itinerary");
  add("mustVisitIDs", "必去地点", "优先安排你的必去地点；无法满足时明确提示。", "itinerary");
  add("excludedPlaceIDs", "不想去的地点", "移出当前方案，保留其他地点与锁定内容。", "itinerary");
  return impacts;
}

export function routeDistance(day: PlanDay): number {
  return day.route.reduce((sum, segment) => sum + distanceMeters(segment.from, segment.to), 0);
}

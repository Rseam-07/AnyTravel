import { useApp } from "../store";
import { formatCNY } from "../types";

export default function TrackRail() {
  const { state, setFocus, relaxPlan } = useApp();
  const plan = state.plan;
  if (!plan) return null;
  const totalCost = plan.days.reduce((sum, day) => sum + day.stops.length, 0);
  const estimated = buildRoughTotal(state);
  return (
    <div className="track-rail">
      {plan.days.map((day, index) => (
        <button
          key={index}
          className={`rail-day${state.selectedDay === index ? " selected" : ""}`}
          onClick={() => setFocus({ kind: "day", id: String(index), coordinate: day.route[0]?.from })}
        >
          <div className="r-date">{day.dateLabel}</div>
          <div className="r-title">
            {day.stops.map((s) => s.place.name).slice(0, 3).join(" · ")}
            {day.stops.length > 3 ? " …" : ""}
          </div>
          <div className="r-stops">
            {day.stops.length} 处 · {day.overCapacity ? "偏满" : "舒适"}
          </div>
        </button>
      ))}
      <div className="rail-actions">
        <button className="chip-btn route-flavored" onClick={() => void relaxPlan()}>
          🌿 铺松
        </button>
      </div>
      <div className="rail-total">
        <span className="t-price">{estimated != null ? formatCNY(estimated) : "费用待选"}</span>
        <span>{totalCost} 处停留 · 估算/实时混合</span>
      </div>
    </div>
  );
}

import type { AppState } from "../store";

function buildRoughTotal(state: AppState): number | null {
  let total = 0;
  let any = false;
  for (const option of state.transports) {
    if (option.id !== state.selectedOutboundID && option.id !== state.selectedReturnID) continue;
    const quote = option.quotes.find((q) => q.amountCNY != null);
    if (quote?.amountCNY != null) {
      total += quote.amountCNY * state.draft.travelers;
      any = true;
    }
  }
  const stay = state.accommodations.find((a) => a.id === state.selectedAccommodationID);
  const quote = stay && stay.quotes.find((q) => q.amountCNY != null);
  if (quote?.amountCNY != null) {
    total += quote.amountCNY * Math.max(state.draft.dayCount - 1, 1) * Math.ceil(state.draft.travelers / 2);
    any = true;
  }
  for (const ticket of Object.values(state.tickets)) {
    if (ticket.amountCNY != null) {
      total += ticket.amountCNY * state.draft.travelers;
      any = true;
    }
  }
  total += state.draft.dayCount * state.draft.travelers * 12; // city transit estimate
  total += state.draft.dayCount * state.draft.travelers * 130; // meals estimate
  return any ? total : null;
}

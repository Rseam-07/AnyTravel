import { useApp } from "../store";
import { formatCNY } from "../types";
import { buildExpenseSummary } from "../expense-planner";

export default function TrackRail() {
  const { state, setFocus, relaxPlan } = useApp();
  const plan = state.plan;
  if (!plan) return null;
  const totalCost = plan.days.reduce((sum, day) => sum + day.stops.length, 0);
  const expense = buildExpenseSummary(state);
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
        <span className="t-price">约 {formatCNY(expense.plannedTotalCNY)}</span>
        <span>{totalCost} 处停留 · 含查询价与预算预留</span>
      </div>
    </div>
  );
}

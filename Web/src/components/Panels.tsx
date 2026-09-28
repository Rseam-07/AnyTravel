import { useEffect, useMemo, useState, type CSSProperties } from "react";
import {
  BookOpen,
  Clock3,
  Cloud,
  CloudFog,
  CloudLightning,
  CloudRain,
  CloudSun,
  Hotel,
  Leaf,
  Lock,
  LockOpen,
  MapPin,
  Printer,
  Save,
  Send,
  Share2,
  Sparkles,
  SunMedium,
  Ticket,
  Trash2,
  ArrowLeftRight,
  Plus,
  Coffee,
  TrainFront,
  UtensilsCrossed
} from "lucide-react";
import { preferredQuote, quoteContext, quoteTotal, quoteUnitLabel } from "../quotes";
import { transportTimingConflict } from "../quote-refresh";
import MotionTabs from "./MotionTabs";
import FlightResearchImport from "./FlightResearchImport";
import { useApp } from "../store";
import { clockText, formatCNY, meterText } from "../types";
import { addDays, distanceMeters, scheduleDay } from "../planner";
import type { AccommodationOption, BookingConfirmation, BookingKind } from "../types";
import { KNOWLEDGE_STATS, lookupCity } from "../knowledge";
import { buildExpenseSummary, expenseSourceTitle } from "../expense-planner";

export function WeatherStrip() {
  const { state } = useApp();
  if (!state.weather?.length) return null;
  const start = state.draft.startDate;
  const end = start ? addDays(start, state.draft.dayCount - 1) : undefined;
  const relevant = state.weather.filter(day => (!start || day.date >= start) && (!end || day.date <= end));
  if (!relevant.length) return <p className="weather-note">出行日期尚未进入当前预报范围，临近出发再查看天气。</p>;
  return (
    <div className="weather-strip" aria-label="行程天气">
      {relevant.slice(0, 8).map((day) => {
        const code = day.code;
        const WeatherIcon = code === 0
          ? SunMedium
          : code <= 2
            ? CloudSun
            : code === 3
              ? Cloud
              : code <= 48
                ? CloudFog
                : code <= 82
                  ? CloudRain
                  : CloudLightning;
        const rain = day.precipitationProbability >= 50;
        return (
          <div key={day.date} className={`weather-card${rain ? " rain" : ""}`}>
            <div className="w-date">{day.date.slice(5).replace("-", "/")}</div>
            <div className="w-symbol"><WeatherIcon size={18} strokeWidth={1.8} aria-hidden="true" /></div>
            <div>
              {Math.round(day.maxTemp)}° / {Math.round(day.minTemp)}°
            </div>
            {rain && <div style={{ fontSize: 10, color: "var(--warm)", fontWeight: 700 }}>雨 {day.precipitationProbability}%</div>}
          </div>
        );
      })}
    </div>
  );
}

export function PlanPanel({ compact = false }: { compact?: boolean }) {
  const { state, setFocus, removeStop, replaceStop, applyDraftChanges, relaxPlan, shareURL, saveTrip, sendChat, toggleVisitLock } = useApp();
  const plan = state.plan;
  useEffect(() => setReplacing(null), [state.selectedDay, plan?.generatedAt]);
  const [replacing, setReplacing] = useState<number | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [adjustment, setAdjustment] = useState("");
  const [assistantReply, setAssistantReply] = useState<string | null>(null);
  const [assistantBusy, setAssistantBusy] = useState(false);

  useEffect(() => {
    if (!notice) return undefined;
    const timer = window.setTimeout(() => setNotice(null), 3200);
    return () => window.clearTimeout(timer);
  }, [notice]);

  if (!plan) {
    return (
      <div style={{ paddingTop: 6 }}>
        <div className="empty-note">
          先输入目的地和条件，再点“生成我的路线”。
          <br />
          路线会按可用时间、移动和偏好安排，并留出用餐与休息。
        </div>
        {state.failureDetail && <div className="issue-note">{state.failureDetail}</div>}
      </div>
    );
  }

  const dayIndex = Math.min(state.selectedDay, Math.max(plan.days.length - 1, 0));
  const day = plan.days[dayIndex];
  if (!day) return <div className="empty-note">这份行程还没有可显示的天数。</div>;

  const guide = lookupCity(state.draft.destination);
  const routeMeters = day.route.reduce((sum, segment) => sum + distanceMeters(segment.from, segment.to), 0);
  const dayColor = ["#126E66", "#E87424", "#6157B8", "#B34B68", "#2777A8", "#7B6C35"][dayIndex % 6];
  const foodMinutes = day.stops.filter(s => s.place.interest === "food").reduce((sum, s) => sum + s.visitMinutes, 0);
  const sightseeingMinutes = day.visitMinutes - foodMinutes;
  const mealMinutes = (day.mealMinutes ?? 0) + foodMinutes;
  const replacementOptions = replacing == null ? [] : (plan.alternatives ?? []).map(item => {
    const replacement = scheduleDay(day.stops.map((stop, index) => index === replacing ? item.place : stop.place), state.draft, dayIndex, [], state.planLocks);
    return { ...item, conflict: replacement.overCapacity ? replacement.assessment : null };
  });
  const fittingReplacements = replacementOptions.filter(item => !item.conflict);
  const conflictingReplacements = replacementOptions.filter(item => item.conflict);
  const dayStyle = { "--day-color": dayColor } as CSSProperties;

  const submitAdjustment = async () => {
    const text = adjustment.trim();
    if (!text || assistantBusy) return;
    setAssistantBusy(true);
    setAssistantReply(null);
    try {
      const reply = await sendChat(text);
      setAssistantReply(reply);
      setAdjustment("");
    } catch (error) {
      setAssistantReply(error instanceof Error ? error.message : "暂时没能理解这次调整。");
    } finally {
      setAssistantBusy(false);
    }
  };

  return (
    <div className="plan-panel" style={dayStyle}>
      <div className="plan-overview">
        <div>
          <span className="plan-kicker">{state.draft.destination} · 第 {dayIndex + 1} 天</span>
          <h1>{day.title.replace(/^.* · /, "")}</h1>
          <p>{day.stops.length} 处停留 · 连线 {meterText(routeMeters)} · 移动约 {Math.round(day.travelMinutes)} 分钟</p>
        </div>
        <div className="plan-icon-actions" aria-label="行程操作">
          <button
            className="icon-action"
            title="存进旅册"
            aria-label="存进旅册"
            onClick={() => {
              if (saveTrip()) setNotice("完整方案已收进旅册。");
            }}
          >
            <Save size={17} aria-hidden="true" />
          </button>
          <button
            className="icon-action"
            title="复制分享链接"
            aria-label="复制分享链接"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(shareURL());
                setNotice("分享链接已复制，对方打开后会还原这次条件。");
              } catch {
                setNotice("浏览器未允许复制链接，请允许剪贴板访问后重试。行程已保留。");
              }
            }}
          >
            <Share2 size={17} aria-hidden="true" />
          </button>
          <button className="icon-action" title="打印或存成 PDF" aria-label="打印或存成 PDF" onClick={() => window.print()}>
            <Printer size={17} aria-hidden="true" />
          </button>
        </div>
      </div>

      <MotionTabs className="day-switcher" label="选择行程日期" value={String(dayIndex)} onChange={id => { const index = Number(id); const item = plan.days[index]; setFocus({ kind: "day", id, coordinate: item.route[0]?.from ?? item.stops[0]?.place.coordinate }); }} items={plan.days.map((item, index) => ({ id: String(index), content: <><b>第 {index + 1} 天</b><small>{item.dateLabel || "日期待定"}</small></> }))} />
      <div className="day-capacity" key={`budget-${dayIndex}`}>
        <div className="capacity-heading"><span>{day.overCapacity ? "需要调整时间" : "今天的时间安排"}</span><strong>{clockText(day.startMinute)}—{clockText(day.endMinute)}</strong></div>
        <div className="capacity-track" aria-hidden="true">{[
          { key: "visit", value: sightseeingMinutes }, { key: "travel", value: day.travelMinutes },
          { key: "meal", value: mealMinutes }, { key: "buffer", value: day.bufferMinutes ?? 0 },
          { key: "free", value: Math.max(0, day.availableMinutes - day.visitMinutes - day.travelMinutes - (day.mealMinutes ?? 0) - (day.bufferMinutes ?? 0)) }
        ].map(part => <i key={part.key} className={`capacity-${part.key}`} style={{ flexGrow: part.value }} />)}</div>
        <div className="capacity-legend"><span><i className="capacity-visit" />游览 {sightseeingMinutes}分</span><span><i className="capacity-travel" />路程 {day.travelMinutes}分</span><span><i className="capacity-meal" />餐休 {mealMinutes}分</span><span><i className="capacity-buffer" />机动 {day.bufferMinutes ?? 0}分</span></div>
        {day.warnings?.map(warning => <p className="capacity-warning" key={warning}>{warning}</p>)}
      </div>

      {state.notice && (
        <div className="issue-note success-note">
          {state.notice}
        </div>
      )}
      {notice && <div className="issue-note success-note">{notice}</div>}
      <WeatherStrip />

      <div className="itinerary-list" key={`day-${dayIndex}`}>
        {day.stops.map((stop, stopIndex) => {
          const ticket = state.tickets[stop.place.id] ?? stop.ticket;
          const locked = state.planLocks.visits.some((lock) => lock.placeID === stop.place.id);
          return (
            <div key={`${stop.place.id}-${stopIndex}`} className="itinerary-item" style={{ "--stop-index": stopIndex } as CSSProperties}>

              {(stop.moveMinutes ?? 0) > 0 && (
                <div className="travel-leg">
                  <span>{stopIndex === 0 ? "从市中心出发 · " : ""}{stop.moveSource === "routed" ? "路段预计" : "移动估算"} {stop.moveMinutes ?? "—"} 分钟</span>
                  {stop.moveFrom && <span>{meterText(distanceMeters(stop.moveFrom, stop.place.coordinate))}</span>}
                </div>
              )}
              {day.breaks?.filter(b => b.beforeStopID === stop.place.id && b.endMinute <= (stop.arriveMinute ?? 0)).map((pause, index) => <div className={`schedule-pause ${pause.kind}`} key={index}><Coffee size={14} aria-hidden="true" /><span><b>{clockText(pause.startMinute)}–{clockText(pause.endMinute)}</b>{pause.label}</span></div>)}
              <article
                className={`itinerary-stop${state.focus?.kind === "place" && state.focus.id === stop.place.id ? " selected" : ""}`}
                role="button"
                tabIndex={0}
                onClick={() => setFocus({ kind: "place", id: stop.place.id, coordinate: stop.place.coordinate })}
                onKeyDown={(event) => {
                  if (event.target === event.currentTarget && (event.key === "Enter" || event.key === " ")) {
                    event.preventDefault();
                    setFocus({ kind: "place", id: stop.place.id, coordinate: stop.place.coordinate });
                  }
                }}
              >
                <span className="stop-index">{stopIndex + 1}</span>
                <div className="stop-time">
                  <strong>{stop.arrivalText}</strong>
                  <span>{stop.departureText}</span>
                </div>
                <div className="stop-body">
                  <div className="stop-name">
                    {stop.place.source === "user" && <MapPin size={14} aria-label="手动添加" />}
                    <strong>{stop.place.name}</strong>
                    {stop.isPrimary && <span className="prio">主游览</span>}
                    {locked && <span className="booking-state locked"><Lock size={10} aria-hidden="true" />日期与时段已锁</span>}
                  </div>
                  <div className="stop-meta">
                    <span><Clock3 size={13} aria-hidden="true" />停留约 {stop.visitMinutes} 分钟</span>
                    {stop.opening && <span>{stop.opening}</span>}
                    {ticket?.amountCNY != null && (
                      <span>
                        <Ticket size={13} aria-hidden="true" />{ticket.priceType === "relatedProduct" ? "相关产品起价 " : "门票参考 "}<b>{formatCNY(ticket.amountCNY)}</b>
                        {ticket.isStale && <span className="stale-tag">历史记录，待刷新</span>}
                        {ticket.bookingURL && (
                          <a className="link-btn" href={ticket.bookingURL} target="_blank" rel="noreferrer" onClick={(event) => event.stopPropagation()}>
                            查看来源
                          </a>
                        )}
                      </span>
                    )}
                    {ticket?.note && <span className="stop-reason">{ticket.note}</span>}
                    {stop.note && <span className="stop-reason">{stop.note}</span>}
                  </div>
                </div>
                <span className="stop-actions">
                  <button className="replace-stop" aria-label={`替换${stop.place.name}`} title="从备选里换一处" disabled={locked || !plan.alternatives?.length} onClick={event => { event.stopPropagation(); setReplacing(replacing === stopIndex ? null : stopIndex); }}><ArrowLeftRight size={14} aria-hidden="true" /></button>
                  <button
                    className={`lock-control${locked ? " active" : ""}`}
                    aria-label={locked ? `解锁${stop.place.name}` : `锁定${stop.place.name}的日期与时段`}
                    title={locked ? "解锁日期与时段" : "锁定日期与时段"}
                    onClick={(event) => {
                      event.stopPropagation();
                      toggleVisitLock(dayIndex, stopIndex);
                    }}
                  >
                    {locked ? <Lock size={14} aria-hidden="true" /> : <LockOpen size={14} aria-hidden="true" />}
                  </button>
                  <button
                    className="remove-stop"
                    aria-label={`移除${stop.place.name}`}
                    title={locked ? "先解锁，才能移除" : "从当天移除"}
                    disabled={locked}
                    onClick={(event) => {
                      event.stopPropagation();
                      void removeStop(dayIndex, stopIndex);
                    }}
                  >
                    <Trash2 size={15} aria-hidden="true" />
                  </button>
                </span>
              </article>
              {day.breaks?.filter(b => b.kind === "buffer" && b.startMinute === stop.leaveMinute).map((pause, index) => <div className="buffer-note" key={index}>{pause.endMinute - pause.startMinute} 分钟机动{stopIndex === day.stops.length - 1 ? " · 今天不用赶" : ""}</div>)}
              {replacing === stopIndex && <div className="replacement-picker">
                <strong>替换 {stop.place.name}</strong><p>只重算当天，其他日期保持原安排。</p>
                {fittingReplacements.map(item => <button key={item.place.id} onClick={() => void replaceStop(dayIndex, stopIndex, item.place.id)}><span>{item.place.name}</span><ArrowLeftRight size={14} aria-hidden="true" /></button>)}
                {!fittingReplacements.length && <p role="status">现有备选都无法完整放入这一天。可以换当天另一站，或先移除一站留出时间。</p>}
                {conflictingReplacements.length > 0 && <details className="replacement-conflicts"><summary>{conflictingReplacements.length} 处暂时放不下 · 查看原因</summary>{conflictingReplacements.map(item => <p key={item.place.id}><strong>{item.place.name}</strong><br />{item.conflict}</p>)}</details>}
                <button className="chip-btn" onClick={() => setReplacing(null)}>取消替换</button>
              </div>}
            </div>
          );
        })}
      </div>
      {day.breaks?.filter(pause => pause.kind === "meal" && !pause.beforeStopID).map((pause, index) => <div className="schedule-pause meal" key={`last-meal-${index}`}><Coffee size={14} aria-hidden="true" /><span><b>{clockText(pause.startMinute)}–{clockText(pause.endMinute)}</b>{pause.label}</span></div>)}
      <div className="day-summary">
        <div>
          <strong>{day.assessment}</strong>
          <span>停留 {Math.round(day.visitMinutes)} 分钟 · 移动 {Math.round(day.travelMinutes)} 分钟</span>
        </div>
        <button className="chip-btn" title="在原有天数内减少游览负担" onClick={() => void relaxPlan()}>
          <Leaf size={15} aria-hidden="true" /> 铺松一点
        </button>
      </div>

      {Boolean(plan.alternatives?.length) && <details className="alternatives-panel" open={plan.alternatives?.some(item => item.required) || undefined}>
        <summary><span>留在备选里的地方</span><b>{plan.alternatives?.length} 处</b></summary>
        <p>每个地方都值得留足时间。可以优先安排，也可以点行程中的换位按钮替换。</p>
        {plan.alternatives?.map(item => <div className={`alternative-item${item.required ? " required" : ""}`} key={item.place.id}><div><strong>{item.place.name}{item.required && <small>必去，尚未排入</small>}</strong><p>{item.reason}</p></div><div className="alternative-actions"><button className="chip-btn" onClick={() => setFocus({ kind: "place", id: item.place.id, coordinate: item.place.coordinate })}><MapPin size={13} aria-hidden="true" />定位</button><button className="chip-btn" onClick={() => void applyDraftChanges({ ...state.draft, mustVisitIDs: item.required ? state.draft.mustVisitIDs?.filter(id => id !== item.place.id) : [...new Set([...(state.draft.mustVisitIDs ?? []), item.place.id])] })}><Plus size={13} aria-hidden="true" />{item.required ? "取消必去" : "优先安排"}</button></div></div>)}
      </details>}
      <div className="inline-assistant">
        <div className="assistant-label"><Sparkles size={15} aria-hidden="true" />一句话调整整段行程</div>
        <div className="assistant-input-row">
          <input
            value={adjustment}
            aria-label="一句话调整行程"
            placeholder="比如：轻松一点，多安排美食"
            onChange={(event) => setAdjustment(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") void submitAdjustment();
            }}
          />
          <button disabled={!adjustment.trim() || assistantBusy} onClick={() => void submitAdjustment()} aria-label="发送调整">
            <Send size={17} aria-hidden="true" />
          </button>
        </div>
        {assistantBusy && <p>正在把调整落回地图…</p>}
        {assistantReply && <p>{assistantReply}</p>}
      </div>

      {guide && (
        <>
          <details className="plan-context">
            <summary><BookOpen size={15} aria-hidden="true" />为什么这样排</summary>
            <p>
              本次按你选择的日期、兴趣与可用时间安排；同城攻略只提供地点和游览时长的参考。
            </p>
            {plan.notes.map((note, index) => <p key={index}>{note}</p>)}
            <p>路线会优先请求道路几何，无法连接时才用直连估算。营业时间与闭馆日请在出发前复核。</p>
          </details>
          <p className="data-attribution">
            地点资料：<a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a>
            · <a href="https://www.wikidata.org/" target="_blank" rel="noreferrer">Wikidata</a>
            · <a href="https://audiala.com/" target="_blank" rel="noreferrer">Data by Audiala</a>
          </p>
        </>
      )}
      {!compact && <div style={{ height: 8 }} />}
    </div>
  );
}

export function AccommodationPanel() {
  const { state, setFocus, selectAccommodation, confirmBooking, removeBookingConfirmation, toggleAccommodationLock } = useApp();
  const [filter, setFilter] = useState<"all" | "cheap" | "live" | "near">("all");
  const items = state.accommodations;
  const stayContext = quoteContext(state.draft, "accommodation");

  const sorted = useMemo(() => {
    let list = [...items];
    const draftCenter = state.draft.destinationCoord;
    if (filter === "cheap") {
      list.sort((a, b) => (quoteTotal(preferredQuote(a.quotes, stayContext), stayContext) ?? Infinity) - (quoteTotal(preferredQuote(b.quotes, stayContext), stayContext) ?? Infinity));
    } else if (filter === "live") {
      list = list.filter((a) => a.quotes.some((q) => q.amountCNY != null && q.kind === "live" && !q.isStale));
    } else if (filter === "near") {
      list.sort((a, b) => {
        const da = a.coordinate && draftCenter ? distanceMeters(draftCenter, a.coordinate) : 1e9;
        const db = b.coordinate && draftCenter ? distanceMeters(draftCenter, b.coordinate) : 1e9;
        return da - db;
      });
    }
    return list;
  }, [items, filter, state.draft]);

  const liveProviders = useMemo(
    () => new Set(items.flatMap((a) => a.quotes.filter((q) => q.amountCNY != null).map((q) => q.providerTitle))),
    [items]
  );
  const areaSuggestions = useMemo(() => {
    const seen = new Set<string>();
    return (state.plan?.days ?? []).flatMap((day, index) => {
      const anchor = day.stops[0]?.place;
      if (!anchor || seen.has(anchor.id)) return [];
      seen.add(anchor.id);
      return [{ anchor, day: index + 1 }];
    });
  }, [state.plan]);

  return (
    <div>
      <div className="section-title">
        住哪里 <span className="sub-text" style={{ fontWeight: 500 }}>匹配行程锚点与起点距离</span>
      </div>
      <div style={{ display: "flex", gap: 6, marginBottom: 10, flexWrap: "wrap" }}>
        {(
          [
            ["all", "综合"],
            ["near", "近市中心"],
            ["cheap", "低价优先"],
            ["live", "只看查询价"]
          ] as const
        ).map(([id, title]) => (
          <button key={id} className={`chip-btn ${filter === id ? "active" : ""}`} onClick={() => setFilter(id)}>
            {title}
          </button>
        ))}
      </div>
      {liveProviders.size > 0 && (
        <div className="sub-text" style={{ marginBottom: 8 }}>
          价格来源：{[...liveProviders].join("、")}
          {state.accommodationIssues.length > 0 && "（其他渠道见设置）"}
        </div>
      )}
      {state.accommodationIssues.length > 0 && (
        <details style={{ marginBottom: 10 }} open={false}>
          <summary className="chip-btn" style={{ cursor: "pointer" }}>
            价格渠道：{liveProviders.size > 0 ? `${liveProviders.size} 个可用` : "尚未接通"}
            <span style={{ marginLeft: 6, opacity: 0.7 }}>（展开查看详情）</span>
          </summary>
          <div style={{ marginTop: 8, display: "flex", flexDirection: "column", gap: 6 }}>
            {state.accommodationIssues.map((issue, i) => (
              <div key={i} className="issue-note" style={{ marginBottom: 0 }}>
                {issue.providerTitle}：{issue.detail ?? issue.status}
              </div>
            ))}
            <div className="sub-text">已有路线和保存内容不受影响；稍后刷新会继续尝试可用渠道。</div>
          </div>
        </details>
      )}
      {items.length === 0 && areaSuggestions.length > 0 && (
        <div className="area-suggestions">
          <div className="area-suggestion-head">
            <strong>先定落脚片区</strong>
            <span>按每天主线就近推荐，不冒充具体酒店</span>
          </div>
          {areaSuggestions.map(({ anchor, day }) => {
            const id = `area-${anchor.id}`;
            const selected = state.focus?.kind === "accommodation" && state.focus.id === id;
            return (
              <button
                key={id}
                className={`area-card${selected ? " selected" : ""}`}
                onClick={() => setFocus({ kind: "accommodation", id, coordinate: anchor.coordinate })}
              >
                <span className="area-icon"><MapPin size={17} aria-hidden="true" /></span>
                <span>
                  <strong>{anchor.name}一带</strong>
                  <small>靠近第 {day} 天主线，减少早晚折返</small>
                </span>
              </button>
            );
          })}
        </div>
      )}
      {items.length === 0 && state.accommodationIssues.length === 0 && (
        <div className="empty-note">正在等待住宿信息…如果暂时没有结果，可以稍后重试或调整日期。</div>
      )}
      {sorted.map((item) => (
        <StayCard
          key={item.id}
          item={item}
          selected={state.selectedAccommodationID === item.id}
          confirmation={state.bookingConfirmations.find(record => record.kind === "accommodation" && record.itemID === item.id)}
          locked={state.planLocks.accommodationID === item.id || state.bookingConfirmations.some(record => record.kind === "accommodation" && record.itemID === item.id)}
          onSelect={() => selectAccommodation(item.id)}
          onToggleLock={() => toggleAccommodationLock(item.id)}
          onConfirm={(note, amount) => confirmBooking("accommodation", item.id, note, amount)}
          onRemoveConfirmation={() => removeBookingConfirmation("accommodation", item.id)}
          onFocus={() => item.coordinate && setFocus({ kind: "accommodation", id: item.id, coordinate: item.coordinate })}
        />
      ))}
    </div>
  );
}

function StayCard({
  item,
  selected,
  confirmation,
  locked,
  onSelect,
  onToggleLock,
  onConfirm,
  onRemoveConfirmation,
  onFocus
}: {
  item: AccommodationOption;
  selected: boolean;
  confirmation?: BookingConfirmation;
  locked: boolean;
  onSelect: () => void;
  onToggleLock: () => void;
  onConfirm: (note?: string, actualAmountCNY?: number) => void;
  onRemoveConfirmation: () => void;
  onFocus: () => void;
}) {
  const { state } = useApp();
  const [failedImage, setFailedImage] = useState<string>();
  const context = quoteContext(state.draft, "accommodation");
  const quote = preferredQuote(item.quotes, context);
  const total = quoteTotal(quote, context);
  const channelCount = new Set(item.quotes.filter((q) => q.amountCNY != null).map((q) => q.provider)).size;
  return (
    <div className={`stay-card${selected ? " selected" : ""}${confirmation ? " booked" : ""}`} onClick={onSelect}>
      <div className="stay-thumb">
        {item.imageURL && failedImage !== item.imageURL ? <img src={item.imageURL} alt="" loading="lazy" onError={() => setFailedImage(item.imageURL)} /> : <Hotel size={24} aria-label="住宿" />}
      </div>
      <div className="stay-main">
        <div className="stay-name">
          {item.name}
          {channelCount > 1 && <span className="provider-tag" style={{ marginLeft: 6 }}>{channelCount} 家比价</span>}
          <span className={`booking-state ${confirmation ? "confirmed" : selected ? "selected" : "suggestion"}`}>
            {confirmation ? "已确认预订" : selected ? "已选择 · 未预订" : "备选"}
          </span>
          {locked && <span className="booking-state locked"><Lock size={10} aria-hidden="true" />已锁定</span>}
        </div>
        <div className="stay-meta">
          {[item.brand, item.starRating ? `${item.starRating} 星` : null]
            .filter(Boolean)
            .join(" · ")}
          {item.attractionDistanceMeters != null && ` · 距景点约 ${meterText(item.attractionDistanceMeters)}`}
        </div>
        <div className="stay-quote">
          {quote ? (
            <>
              <span className={`price ${quote.amountCNY == null ? "muted" : ""}`}>{formatCNY(quote.amountCNY)}</span>
              <span className="price-unit">{quoteUnitLabel(quote.unit)}</span>
              {quote.providerTitle && <span className="provider-tag">{quote.providerTitle}</span>}
              {quote.isStale && <span className="stale-tag">历史价格</span>}
              {quote.kind === "indicative" && <span className="stale-tag">参考起价</span>}
              {quote.roomName && (
                <span className="provider-tag" style={{ maxWidth: 140, overflow: "hidden", textOverflow: "ellipsis" }}>
                  {quote.roomName}
                </span>
              )}
              {quote.mealPlan && <span className="provider-tag">{quote.mealPlan}</span>}
            </>
          ) : (
            <span className="sub-text">价格待查</span>
          )}
        </div>
        {quote && <p className="sub-text quote-provenance">{context.nights}晚 · {context.rooms}间合计 {formatCNY(total)}{quote.capturedAt ? ` · 查询于 ${new Date(quote.capturedAt).toLocaleString("zh-CN")}` : ""}<br />{quote.note}</p>}
        <div className="stay-links">
          {quote?.bookingURL && (
            <a className="link-btn" href={quote.bookingURL} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>
              到渠道购买
            </a>
          )}
          {item.officialWebsiteURL && (
            <a className="link-btn" href={item.officialWebsiteURL} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>
              酒店官网
            </a>
          )}
          <button className="link-btn" style={{ textDecoration: "none" }} onClick={(e) => { e.stopPropagation(); onFocus(); }}>
            在地图上看
          </button>
          <button
            className={`link-btn lock-link${locked ? " active" : ""}`}
            style={{ textDecoration: "none" }}
            disabled={Boolean(confirmation)}
            title={confirmation ? "已预订内容会自动锁定；撤销预订确认后可解锁" : undefined}
            onClick={(e) => { e.stopPropagation(); onToggleLock(); }}
          >
            {locked ? <Lock size={12} aria-hidden="true" /> : <LockOpen size={12} aria-hidden="true" />}
            {confirmation ? "预订已锁定" : locked ? "解锁住处" : "锁定住处"}
          </button>
        </div>
        {(selected || confirmation) && (
          <BookingControl
            kind="accommodation"
            confirmation={confirmation}
            onConfirm={onConfirm}
            onRemove={onRemoveConfirmation}
          />
        )}
      </div>
    </div>
  );
}

export function TransportPanel({ onGoConditions }: { onGoConditions?: () => void }) {
  const { state, selectTransport, importResearchedFlights, confirmBooking, removeBookingConfirmation, toggleTransportLock } = useApp();
  const [direction, setDirection] = useState<"outbound" | "return">("outbound");
  const outbound = state.transports.filter((t) => t.direction === "outbound");
  const retur = state.transports.filter((t) => t.direction === "return");
  const list = direction === "outbound" ? outbound : retur;
  const actualIssues = state.transportIssues.filter((issue) => !["ok", "configured", "disabled"].includes(issue.status));

  return (
    <div>
      <div className="section-title">怎么去，怎么回</div>
      {!state.draft.origin && (
        <div className="issue-note">
          补充出发地后，去程与返程班次、余票和席别价格会立刻出现。
          {onGoConditions && (
            <button
              className="chip-btn route-flavored"
              style={{ marginLeft: 8 }}
              onClick={onGoConditions}
            >
              去填出发地 →
            </button>
          )}
        </div>
      )}
      {state.transports.length > 0 && (
        <div className="transport-source-note">
          <TrainFront size={15} aria-hidden="true" />
          交通查询 · 去程 {outbound.length} 班 · 返程 {retur.length} 班 · 来源见各班次
        </div>
      )}
      {actualIssues.map((issue, i) => (
        <div key={i} className="issue-note">
          {issue.providerTitle}：{issue.detail ?? issue.status}
          {issue.provider === "fliggy" && <a className="link-btn" href="https://h5.m.taobao.com/trip/traffic-search/search/index.html?defaultBiz=flight" target="_blank" rel="noreferrer">到飞猪查询</a>}
        </div>
      ))}
      {state.draft.origin && state.draft.startDate && (
        <div className="mode-tabs">
          <button className={`chip-btn ${direction === "outbound" ? "active" : ""}`} onClick={() => setDirection("outbound")}>
            去程 {outbound.length ? `(${outbound.length})` : ""}
          </button>
          <button className={`chip-btn ${direction === "return" ? "active" : ""}`} onClick={() => setDirection("return")}>
            返程 {retur.length ? `(${retur.length})` : ""}
          </button>
        </div>
      )}
      <FlightResearchImport key={`${direction}-${state.draft.origin}-${state.draft.destination}-${state.draft.startDate}-${state.draft.dayCount}`} draft={state.draft} direction={direction} onImport={importResearchedFlights}/>
      {list.length > 0 && <p className="sub-text">预选会核对首末日时间，并按火车 1 小时、飞机抵达后 2 小时或出发前 3 小时留出接驳。实际接驳请结合机场、车站位置确认。</p>}
      {list.map((option) => {
        const quote = preferredQuote(option.quotes, quoteContext(state.draft, "transport"));
        const timingConflict = transportTimingConflict(option, state.draft, state.plan);
        const selected = direction === "outbound" ? state.selectedOutboundID === option.id : state.selectedReturnID === option.id;
        const confirmation = state.bookingConfirmations.find(record => record.kind === "transport" && record.itemID === option.id);
        const locked = confirmation != null || (direction === "outbound"
          ? state.planLocks.outboundTransportID === option.id
          : state.planLocks.returnTransportID === option.id);
        return (
          <div
            key={option.id}
            className={`train-card${selected ? " selected" : ""}${confirmation ? " booked" : ""}`}
            onClick={() => selectTransport(option.id)}
          >
            <div className="train-title">
              {option.title}
              <span className={`booking-state ${confirmation ? "confirmed" : selected ? "selected" : "suggestion"}`}>
                {confirmation ? "已确认预订" : selected ? "已选择 · 未购票" : option.isRecommended ? "推荐" : "备选"}
              </span>
              {locked && <span className="booking-state locked"><Lock size={10} aria-hidden="true" />已锁定</span>}
            </div>
            <div className="train-meta">
              {option.departureTime ? `${option.departureTime.toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Shanghai" })} 出发` : ""}
              {option.arrivalTime ? ` → ${option.arrivalTime.toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Shanghai" })} 到达（北京时间）` : ""}
              {option.durationMinutes ? ` · 约 ${Math.round(option.durationMinutes)} 分钟` : ""}
              {option.availability ? ` · ${option.availability}` : ""}
            </div>
            <div className="train-price">
              <span className={`price ${quote?.amountCNY == null ? "muted" : ""}`}>{quote ? `${formatCNY(quote.amountCNY)}${quoteUnitLabel(quote.unit)}` : "等待报价"}</span>
              <span style={{ display: "flex", gap: 6, alignItems: "center" }}>
                {quote && <span className="provider-tag">{quote.providerTitle}</span>}
                {quote?.kind === "indicative" && <span className="stale-tag">参考价格</span>}
                {quote?.isStale && <span className="stale-tag">历史价格</span>}
                {quote?.bookingURL && (
                  <a className="link-btn" href={quote.bookingURL} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>
                    购买页
                  </a>
                )}
              </span>
            </div>
            {quote && <p className="sub-text quote-provenance">{quote.capturedAt ? `查询于 ${new Date(quote.capturedAt).toLocaleString("zh-CN")} · ` : ""}{quote.note}</p>}
            {timingConflict && <p className="issue-note">{timingConflict}</p>}
            <button
              className={`lock-row-action${locked ? " active" : ""}`}
              disabled={Boolean(confirmation)}
              title={confirmation ? "已购票内容会自动锁定；撤销确认后可解锁" : undefined}
              onClick={(event) => { event.stopPropagation(); toggleTransportLock(option.id); }}
            >
              {locked ? <Lock size={13} aria-hidden="true" /> : <LockOpen size={13} aria-hidden="true" />}
              {confirmation ? "购票后已锁定" : locked ? "解锁这个班次" : "锁定这个班次"}
            </button>
            {(selected || confirmation) && (
              <BookingControl
                kind="transport"
                confirmation={confirmation}
                onConfirm={(note, amount) => confirmBooking("transport", option.id, note, amount)}
                onRemove={() => removeBookingConfirmation("transport", option.id)}
              />
            )}
          </div>
        );
      })}
      {list.length === 0 && state.draft.origin && (
        <div className="empty-note">
          {state.transportIssues.length === 0
            ? "正在获取往返班次…"
            : "当前没有返回可购买班次；可以调整日期后再试，或到设置查看渠道状态。"}
        </div>
      )}
    </div>
  );
}

function BookingControl({
  kind,
  confirmation,
  onConfirm,
  onRemove
}: {
  kind: BookingKind;
  confirmation?: BookingConfirmation;
  onConfirm: (note?: string, actualAmountCNY?: number) => void;
  onRemove: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [note, setNote] = useState(confirmation?.note ?? "");
  const [actualAmount, setActualAmount] = useState(confirmation?.actualAmountCNY?.toString() ?? "");
  const noun = kind === "accommodation" ? "住宿" : "车票/机票";
  if (confirmation) {
    const confirmedAt = new Date(confirmation.confirmedAt);
    const dateText = Number.isFinite(confirmedAt.getTime())
      ? confirmedAt.toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })
      : "已记录";
    const tripDates = confirmation.startDate
      ? confirmation.endDate && confirmation.endDate !== confirmation.startDate
        ? `${confirmation.startDate} 至 ${confirmation.endDate}`
        : confirmation.startDate
      : null;
    return (
      <div className="booking-confirmation" onClick={(event) => event.stopPropagation()}>
        <div>
          <strong>你已确认在外部平台订好</strong>
          <small>{[tripDates, confirmation.actualAmountCNY ? `实际支出 ${formatCNY(confirmation.actualAmountCNY)}` : "实际支出未记录", dateText, confirmation.note].filter(Boolean).join(" · ")}</small>
        </div>
        <button className="link-btn" onClick={onRemove}>撤销确认</button>
      </div>
    );
  }
  if (!editing) {
    return (
      <div className="booking-pending" onClick={(event) => event.stopPropagation()}>
        <span>目前只是已选择，AnyTravel 尚未替你下单。</span>
        <button className="link-btn booking-confirm-btn" onClick={() => setEditing(true)}>我已订好</button>
      </div>
    );
  }
  return (
    <form
      className="booking-editor"
      onClick={(event) => event.stopPropagation()}
      onSubmit={(event) => {
        event.preventDefault();
        const parsed = actualAmount.trim() ? Number(actualAmount) : undefined;
        onConfirm(note, parsed != null && Number.isFinite(parsed) && parsed > 0 ? parsed : undefined);
        setEditing(false);
      }}
    >
      <label>
        实际支付总额（可留空）
        <input type="number" min="0.01" max="10000000" step="0.01" inputMode="decimal" value={actualAmount} onChange={(event) => setActualAmount(event.target.value)} placeholder="例如：1288.50" autoFocus />
      </label>
      <label>
        {noun}订单备注（可留空）
        <input value={note} onChange={(event) => setNote(event.target.value)} maxLength={80} placeholder="例如：订单尾号、可取消至何时" />
      </label>
      <small>请勿填写身份证号、银行卡或完整支付信息。</small>
      <div>
        <button type="button" className="link-btn" onClick={() => setEditing(false)}>取消</button>
        <button type="submit" className="link-btn booking-confirm-btn">确认已预订</button>
      </div>
    </form>
  );
}

export function BudgetPanel({ onNavigate }: { onNavigate?: (target: "stay" | "transport") => void }) {
  const { state } = useApp();
  const summary = useMemo(() => buildExpenseSummary(state), [state]);
  const budget = state.draft.budgetPerPerson ? state.draft.budgetPerPerson * state.draft.travelers : null;
  const over = budget != null && summary.plannedTotalCNY > budget;
  const biggest = [...summary.rows].filter((row) => row.amountCNY > 0).sort((a, b) => b.amountCNY - a.amountCNY).slice(0, 2);
  return (
    <div>
      <div className="section-title">一路要花多少钱</div>
      <div className="cost-summary" aria-label="费用口径摘要">
        <div><small>当前预算轮廓</small><strong>约 {formatCNY(summary.plannedTotalCNY)}</strong></div>
        <div><small>已确认支出</small><strong>{formatCNY(summary.confirmedTotalCNY)}</strong></div>
        <div><small>渠道查询/参考</small><strong>{formatCNY(summary.quotedTotalCNY)}</strong></div>
      </div>
      {summary.rows.map((row) => (
        <div key={row.id} className="cost-row">
          <span className="cost-label">
            {row.label}
            <span className="cost-kind">
              {expenseSourceTitle(row.source)} · {row.note}
              {row.pendingItems.length > 0 ? ` · 另待确认：${row.pendingItems.join("、")}` : ""}
            </span>
          </span>
          <span className="cost-amount">{formatCNY(row.amountCNY)}</span>
        </div>
      ))}
      <div className="cost-total">
        <span>计划总额（{state.draft.travelers} 人，含预留）</span>
        <span style={{ color: over ? "var(--danger)" : "var(--warm)" }}>约 {formatCNY(summary.plannedTotalCNY)}</span>
      </div>
      {summary.pendingItems.length > 0 && (
        <div className="cost-boundary" role="status">
          仍有 {summary.pendingItems.length} 类金额可能另计：{summary.pendingItems.join("、")}。它们没有被当作 0，机动金只用于预算缓冲。
        </div>
      )}
      {budget != null && (
        <div className="sub-text" style={{ marginTop: 8 }}>
          {over ? (
            <div className="cost-overage">
              <strong>比总预算高约 {formatCNY(summary.plannedTotalCNY - budget)}</strong>
              <span>占用最多的是 {biggest.map((row) => `${row.label} ${formatCNY(row.amountCNY)}`).join("、")}。</span>
              <div>
                <button className="mini-btn" onClick={() => onNavigate?.("stay")}>调整住宿</button>
                <button className="mini-btn" onClick={() => onNavigate?.("transport")}>调整交通</button>
              </div>
            </div>
          ) : (
            <>在预算 {formatCNY(budget)} 内，当前还留有约 {formatCNY(budget - summary.plannedTotalCNY)} 余量。</>
          )}
        </div>
      )}
      <div className="cost-boundary">住宿按旅行条件中的房间数与晚数计算；儿童、单人入住、加床、税费、早餐、押金和取消条件以最终订单页为准。</div>
    </div>
  );
}

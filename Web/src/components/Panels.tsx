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
  MapPin,
  Printer,
  Save,
  Send,
  Share2,
  Sparkles,
  SunMedium,
  Ticket,
  Trash2,
  TrainFront,
  UtensilsCrossed
} from "lucide-react";
import { useApp } from "../store";
import { formatCNY, meterText } from "../types";
import { bestQuote, distanceMeters } from "../planner";
import type { AccommodationOption, BookingConfirmation, BookingKind } from "../types";
import { KNOWLEDGE_STATS, lookupCity } from "../knowledge";
import { buildExpenseSummary, expenseSourceTitle } from "../expense-planner";

export function WeatherStrip() {
  const { state } = useApp();
  if (!state.weather?.length) return null;
  return (
    <div className="weather-strip" aria-label="行程天气">
      {state.weather.slice(0, 8).map((day) => {
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
  const { state, setFocus, removeStop, relaxPlan, shareURL, saveTrip, sendChat } = useApp();
  const plan = state.plan;
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
          先输入目的地和条件，再点“让旅程展开”。
          <br />
          方案会按空间聚类铺开每天：真实的地点、移动、用餐与夜间时段都会写进时间表。
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
          <h2>{day.title}</h2>
          <p>{day.stops.length} 处停留 · {meterText(routeMeters)} · 移动约 {Math.round(day.travelMinutes)} 分钟</p>
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
            onClick={() => {
              navigator.clipboard.writeText(shareURL()).catch(() => undefined);
              setNotice("分享链接已复制，对方打开后会还原这次条件。");
            }}
          >
            <Share2 size={17} aria-hidden="true" />
          </button>
          <button className="icon-action" title="打印或存成 PDF" aria-label="打印或存成 PDF" onClick={() => window.print()}>
            <Printer size={17} aria-hidden="true" />
          </button>
        </div>
      </div>

      <div className="day-switcher" role="tablist" aria-label="选择行程日期">
        {plan.days.map((item, index) => (
          <button
            key={`${item.dateLabel}-${index}`}
            role="tab"
            aria-selected={index === dayIndex}
            className={index === dayIndex ? "active" : ""}
            style={{ "--tab-color": ["#126E66", "#E87424", "#6157B8", "#B34B68", "#2777A8", "#7B6C35"][index % 6] } as CSSProperties}
            onClick={() => setFocus({ kind: "day", id: String(index), coordinate: item.route[0]?.from ?? item.stops[0]?.place.coordinate })}
          >
            <span>第 {index + 1} 天</span>
            <small>{item.dateLabel}</small>
          </button>
        ))}
      </div>

      {state.notice && (
        <div className="issue-note success-note">
          {state.notice}
        </div>
      )}
      {notice && <div className="issue-note success-note">{notice}</div>}
      <WeatherStrip />

      <div className="itinerary-list">
        {day.stops.map((stop, stopIndex) => {
          const ticket = state.tickets[stop.place.id] ?? stop.ticket;
          return (
            <div key={`${stop.place.id}-${stopIndex}`}>
              {stopIndex > 0 && (
                <div className="travel-leg">
                  <span>移动约 {stop.moveMinutes ?? "—"} 分钟</span>
                  {stop.moveFrom && <span>{meterText(distanceMeters(stop.moveFrom, stop.place.coordinate))}</span>}
                </div>
              )}
              <article
                className={`itinerary-stop${state.focus?.kind === "place" && state.focus.id === stop.place.id ? " selected" : ""}`}
                role="button"
                tabIndex={0}
                onClick={() => setFocus({ kind: "place", id: stop.place.id, coordinate: stop.place.coordinate })}
                onKeyDown={(event) => {
                  if (event.key === "Enter" || event.key === " ") {
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
                  </div>
                  <div className="stop-meta">
                    <span><Clock3 size={13} aria-hidden="true" />停留约 {stop.visitMinutes} 分钟</span>
                    {stop.opening && <span>{stop.opening}</span>}
                    {ticket?.amountCNY != null && (
                      <span>
                        <Ticket size={13} aria-hidden="true" />门票起价 <b>{formatCNY(ticket.amountCNY)}</b>
                        {ticket.isStale && <span className="stale-tag">历史记录，待刷新</span>}
                        {ticket.bookingURL && (
                          <a className="link-btn" href={ticket.bookingURL} target="_blank" rel="noreferrer" onClick={(event) => event.stopPropagation()}>
                            查看来源
                          </a>
                        )}
                      </span>
                    )}
                    {stop.note && <span><UtensilsCrossed size={13} aria-hidden="true" />{stop.note}</span>}
                  </div>
                </div>
                <button
                  className="remove-stop"
                  aria-label={`移除${stop.place.name}`}
                  title="从当天移除"
                  onClick={(event) => {
                    event.stopPropagation();
                    void removeStop(dayIndex, stopIndex);
                  }}
                >
                  <Trash2 size={15} aria-hidden="true" />
                </button>
              </article>
            </div>
          );
        })}
      </div>

      <div className="day-summary">
        <div>
          <strong>{day.assessment}</strong>
          <span>游览 {Math.round(day.visitMinutes)} 分钟 · 移动 {Math.round(day.travelMinutes)} 分钟</span>
        </div>
        <button className="chip-btn" title="保留地点并把节奏重新铺松" onClick={() => void relaxPlan()}>
          <Leaf size={15} aria-hidden="true" /> 铺松一点
        </button>
      </div>

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
              {guide.sense || `${guide.city}目的地资料`}。本次从 {guide.places.length} 个本地候选点中筛选；离线资料共覆盖 {KNOWLEDGE_STATS.cities} 个目的地、{KNOWLEDGE_STATS.sources} 个去重来源。
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
  const { state, setFocus, selectAccommodation, confirmBooking, removeBookingConfirmation } = useApp();
  const [filter, setFilter] = useState<"all" | "cheap" | "live" | "near">("all");
  const items = state.accommodations;

  const sorted = useMemo(() => {
    let list = [...items];
    const draftCenter = state.draft.destinationCoord;
    if (filter === "cheap") {
      list.sort((a, b) => (bestQuote(a.quotes)?.amountCNY ?? Number.MAX_SAFE_INTEGER) - (bestQuote(b.quotes)?.amountCNY ?? Number.MAX_SAFE_INTEGER));
    } else if (filter === "live") {
      list = list.filter((a) => a.quotes.some((q) => q.amountCNY != null));
    } else if (filter === "near") {
      list.sort((a, b) => {
        const da = a.coordinate && draftCenter ? distanceMeters(draftCenter, a.coordinate) : 1e9;
        const db = b.coordinate && draftCenter ? distanceMeters(draftCenter, b.coordinate) : 1e9;
        return da - db;
      });
    }
    return list;
  }, [items, filter, state.draft.destinationCoord]);

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
            ["live", "只看实时价"]
          ] as const
        ).map(([id, title]) => (
          <button key={id} className={`chip-btn ${filter === id ? "active" : ""}`} onClick={() => setFilter(id)}>
            {title}
          </button>
        ))}
      </div>
      {liveProviders.size > 0 && (
        <div className="sub-text" style={{ marginBottom: 8 }}>
          实时价渠道：{[...liveProviders].join("、")}
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
          onSelect={() => selectAccommodation(item.id)}
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
  onSelect,
  onConfirm,
  onRemoveConfirmation,
  onFocus
}: {
  item: AccommodationOption;
  selected: boolean;
  confirmation?: BookingConfirmation;
  onSelect: () => void;
  onConfirm: (note?: string, actualAmountCNY?: number) => void;
  onRemoveConfirmation: () => void;
  onFocus: () => void;
}) {
  const quote = bestQuote(item.quotes);
  const channelCount = new Set(item.quotes.filter((q) => q.amountCNY != null).map((q) => q.provider)).size;
  return (
    <div className={`stay-card${selected ? " selected" : ""}${confirmation ? " booked" : ""}`} onClick={onSelect}>
      <div className="stay-thumb" style={item.imageURL ? { backgroundImage: `url(${item.imageURL})` } : undefined}>
        {item.imageURL ? "" : <Hotel size={24} aria-label="住宿" />}
      </div>
      <div className="stay-main">
        <div className="stay-name">
          {item.name}
          {channelCount > 1 && <span className="provider-tag" style={{ marginLeft: 6 }}>{channelCount} 家比价</span>}
          <span className={`booking-state ${confirmation ? "confirmed" : selected ? "selected" : "suggestion"}`}>
            {confirmation ? "已确认预订" : selected ? "已选择 · 未预订" : "备选"}
          </span>
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
              <span className="price-unit">{quote.unit === "total" ? "/总价" : "/晚"}</span>
              {quote.providerTitle && <span className="provider-tag">{quote.providerTitle}</span>}
              {quote.isStale && <span className="stale-tag">历史价格</span>}
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
  const { state, selectTransport, confirmBooking, removeBookingConfirmation } = useApp();
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
          铁路 12306 公开查询 · 去程 {outbound.length} 列 · 返程 {retur.length} 列
        </div>
      )}
      {actualIssues.map((issue, i) => (
        <div key={i} className="issue-note">
          {issue.providerTitle}：{issue.detail ?? issue.status}
        </div>
      ))}
      {(outbound.length > 0 || retur.length > 0) && (
        <div className="mode-tabs">
          <button className={`chip-btn ${direction === "outbound" ? "active" : ""}`} onClick={() => setDirection("outbound")}>
            去程 {outbound.length ? `(${outbound.length})` : ""}
          </button>
          <button className={`chip-btn ${direction === "return" ? "active" : ""}`} onClick={() => setDirection("return")}>
            返程 {retur.length ? `(${retur.length})` : ""}
          </button>
        </div>
      )}
      {list.map((option) => {
        const quote = bestQuote(option.quotes);
        const selected = direction === "outbound" ? state.selectedOutboundID === option.id : state.selectedReturnID === option.id;
        const confirmation = state.bookingConfirmations.find(record => record.kind === "transport" && record.itemID === option.id);
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
            </div>
            <div className="train-meta">
              {option.departureTime ? `${option.departureTime.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })} 始发` : ""}
              {option.durationMinutes ? ` · 约 ${Math.round(option.durationMinutes)} 分钟` : ""}
              {option.availability ? ` · ${option.availability}` : ""}
            </div>
            <div className="train-price">
              <span className={`price ${quote?.amountCNY == null ? "muted" : ""}`}>{quote ? formatCNY(quote.amountCNY) : "等待报价"}</span>
              <span style={{ display: "flex", gap: 6, alignItems: "center" }}>
                {quote && <span className="provider-tag">{quote.providerTitle}</span>}
                {quote?.isStale && <span className="stale-tag">历史价格</span>}
                {quote?.bookingURL && (
                  <a className="link-btn" href={quote.bookingURL} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>
                    购买页
                  </a>
                )}
              </span>
            </div>
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
        <input type="number" min="1" max="10000000" step="1" inputMode="numeric" value={actualAmount} onChange={(event) => setActualAmount(event.target.value)} placeholder="例如：1288" autoFocus />
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
      <div className="cost-boundary">房间数暂按每间 2 名成人估算；儿童、单人入住、加床、税费、早餐、押金和取消条件以最终订单页为准。</div>
    </div>
  );
}

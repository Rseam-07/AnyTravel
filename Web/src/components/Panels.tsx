import { useMemo, useState } from "react";
import { useApp } from "../store";
import { formatCNY, meterText } from "../types";
import { bestQuote, distanceMeters } from "../planner";
import type { AccommodationOption } from "../types";

export function WeatherStrip() {
  const { state } = useApp();
  if (!state.weather?.length) return null;
  return (
    <div className="weather-strip">
      {state.weather.slice(0, 8).map((day) => {
        const code = day.code;
        const symbol = code === 0 ? "☀️" : code === 1 ? "🌤️" : code === 2 ? "⛅" : code === 3 ? "☁️" : code <= 48 ? "🌫️" : code <= 67 ? "🌧️" : code <= 82 ? "🌦️" : "⛈️";
        const rain = day.precipitationProbability >= 50;
        return (
          <div key={day.date} className={`weather-card${rain ? " rain" : ""}`}>
            <div className="w-date">{day.date.slice(5).replace("-", "/")}</div>
            <div className="w-symbol">{symbol}</div>
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
  const { state, setFocus, removeStop, relaxPlan, shareURL, saveTrip } = useApp();
  const plan = state.plan;
  const [notice, setNotice] = useState<string | null>(null);
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

  const totalStops = plan.days.reduce((sum, day) => sum + day.stops.length, 0);

  return (
    <div>
      <div className="section-title">
        {state.draft.destination} · {state.draft.dayCount} 天{state.draft.travelers}人 · {totalStops} 处停留
      </div>
      <WeatherStrip />
      {plan.notes.map((note, index) => (
        <div key={index} className="sub-text" style={{ margin: "4px 0 8px" }}>
          {note}
        </div>
      ))}
      {notice && <div className="issue-note">{notice}</div>}
      <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        <button
          className="chip-btn route-flavored"
          onClick={() => {
            void saveTrip();
            setNotice("已收进旅册。");
          }}
        >
          💾 存进旅册
        </button>
        <button
          className="chip-btn route-flavored"
          onClick={() => {
            navigator.clipboard.writeText(shareURL()).catch(() => undefined);
            setNotice("分享链接已复制：对方打开后会自动还原本次条件。");
          }}
        >
          🔗 分享
        </button>
        <button
          className="chip-btn route-flavored"
          onClick={() => {
            window.print();
          }}
        >
          🖨️ 打印/PDF
        </button>
        <button className="chip-btn" title="保留全部地点，按空间关系重新铺松" onClick={() => void relaxPlan()}>
          🌿 铺松一点
        </button>
      </div>
      {plan.days.map((day, dayIndex) => (
        <section
          key={dayIndex}
          className={`day-card${state.selectedDay === dayIndex ? " selected" : ""}`}
          onClick={() => {
            setFocus({ kind: "day", id: String(dayIndex) });
          }}
        >
          <div className="day-head">
            <span className="d-title">{day.title}</span>
            <span className="d-badges">
              {day.badges.map((badge, i) => (
                <span key={i} className={`badge${day.overCapacity ? " warn" : ""}`}>
                  {badge}
                </span>
              ))}
            </span>
          </div>
          {day.stops.map((stop, stopIndex) => (
            <div key={`${stop.place.id}-${stopIndex}`}>
              <div className="stop-route">
                <span>
                  {stop.moveMinutes && stopIndex > 0
                    ? `← 上一站约 ${stop.moveMinutes} 分钟`
                    : stopIndex === 0
                      ? "从住处/中心出发"
                      : ""}
                </span>
                {stop.moveFrom && (
                  <span style={{ marginLeft: "auto", opacity: 0.7 }}>
                    {meterText(distanceMeters(stop.moveFrom, stop.place.coordinate))}
                  </span>
                )}
              </div>
              <div className="stop-row">
                <div className="stop-time">
                  {stop.arrivalText}
                  <br />
                  <span style={{ opacity: 0.55 }}>{stop.departureText}</span>
                </div>
                <div className="stop-body">
                  <div className="stop-name">
                    {stop.place.source === "user" ? "📍 " : ""}
                    {stop.place.name}
                    {stop.isPrimary && <span className="prio">主游览</span>}
                    <span className="badge" style={{ marginLeft: 6 }}>{stop.visitMinutes} 分钟</span>
                  </div>
                  <div className="stop-meta">
                    {stop.place.address && <div>{stop.place.address.slice(0, 60)}</div>}
                    {stop.opening && <div>🕘 {stop.opening}</div>}
                    {stop.ticket?.amountCNY != null && (
                      <div>
                        🎟️ 门票起价 <b>{formatCNY(stop.ticket.amountCNY)}</b>
                        {stop.ticket.bookingURL && (
                          <a
                            className="link-btn"
                            style={{ marginLeft: 6 }}
                            href={stop.ticket.bookingURL}
                            target="_blank"
                            rel="noreferrer"
                            onClick={(e) => e.stopPropagation()}
                          >
                            购买页
                          </a>
                        )}
                      </div>
                    )}
                    {stop.note && <div>🍽️ {stop.note}</div>}
                  </div>
                  <div className="stop-actions">
                    <button
                      className="mini-btn"
                      onClick={(e) => {
                        e.stopPropagation();
                        void removeStop(dayIndex, stopIndex);
                      }}
                    >
                      移除
                    </button>
                  </div>
                </div>
              </div>
            </div>
          ))}
          <div className="day-assessment">{day.assessment}</div>
          <div className="day-foot">
            <span>停留 {Math.round(day.visitMinutes)} 分钟</span>
            <span>移动 {Math.round(day.travelMinutes)} 分钟</span>
            {day.overCapacity && <span className="badge warn">偏满：建议减一站或增加一天</span>}
          </div>
        </section>
      ))}
      <div className="sub-text" style={{ marginTop: 8 }}>
        图上线段为依次连接的真实地点示意；取得 OSRM 路网后会自动换成道路几何。营业时间与闭馆日请在出发前复核。
      </div>
      {!compact && <div style={{ height: 8 }} />}
    </div>
  );
}

export function AccommodationPanel() {
  const { state, setFocus, selectAccommodation } = useApp();
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
      {state.accommodationIssues.map((issue, i) => (
        <div key={i} className="issue-note">
          {issue.providerTitle}：{issue.detail ?? issue.status}
        </div>
      ))}
      {items.length === 0 && state.accommodationIssues.length === 0 && (
        <div className="empty-note">正在等待住宿目录…如果一直没有结果，请检查设置的节点地址与渠道配置。</div>
      )}
      {sorted.map((item) => (
        <StayCard
          key={item.id}
          item={item}
          selected={state.selectedAccommodationID === item.id}
          onSelect={() => selectAccommodation(item.id)}
          onFocus={() => item.coordinate && setFocus({ kind: "accommodation", id: item.id, coordinate: item.coordinate })}
        />
      ))}
    </div>
  );
}

function StayCard({
  item,
  selected,
  onSelect,
  onFocus
}: {
  item: AccommodationOption;
  selected: boolean;
  onSelect: () => void;
  onFocus: () => void;
}) {
  const quote = bestQuote(item.quotes);
  const channelCount = new Set(item.quotes.filter((q) => q.amountCNY != null).map((q) => q.provider)).size;
  return (
    <div className={`stay-card${selected ? " selected" : ""}`} onClick={onSelect}>
      <div className="stay-thumb" style={item.imageURL ? { backgroundImage: `url(${item.imageURL})` } : undefined}>
        {item.imageURL ? "" : "🏨"}
      </div>
      <div className="stay-main">
        <div className="stay-name">
          {item.name}
          {channelCount > 1 && <span className="provider-tag" style={{ marginLeft: 6 }}>{channelCount} 家比价</span>}
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
      </div>
    </div>
  );
}

export function TransportPanel() {
  const { state, selectTransport } = useApp();
  const [direction, setDirection] = useState<"outbound" | "return">("outbound");
  const outbound = state.transports.filter((t) => t.direction === "outbound");
  const retur = state.transports.filter((t) => t.direction === "return");
  const list = direction === "outbound" ? outbound : retur;

  return (
    <div>
      <div className="section-title">怎么去，怎么回</div>
      {!state.draft.origin && (
        <div className="issue-note">先在上方“更多条件”里补充出发地，再去程/返程班次与票价。</div>
      )}
      {state.transportIssues.map((issue, i) => (
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
        return (
          <div
            key={option.id}
            className={`train-card${selected ? " selected" : ""}`}
            onClick={() => selectTransport(option.id)}
          >
            <div className="train-title">{option.title}</div>
            <div className="train-meta">
              {option.departureTime ? `${option.departureTime.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })} 始发` : ""}
              {option.durationMinutes ? ` · 约 ${Math.round(option.durationMinutes)} 分钟` : ""}
              {option.availability ? ` · ${option.availability}` : ""}
            </div>
            <div className="train-price">
              <span className={`price ${quote?.amountCNY == null ? "muted" : ""}`}>{quote ? formatCNY(quote.amountCNY) : "等待报价"}</span>
              <span style={{ display: "flex", gap: 6, alignItems: "center" }}>
                {quote && <span className="provider-tag">{quote.providerTitle}</span>}
                {quote?.bookingURL && (
                  <a className="link-btn" href={quote.bookingURL} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>
                    购买页
                  </a>
                )}
              </span>
            </div>
          </div>
        );
      })}
      {list.length === 0 && state.draft.origin && (
        <div className="empty-note">当前没有可展示的班次：请打开“设置”确认报价节点可达（12306 无需密钥；航班需会话通道）。</div>
      )}
    </div>
  );
}

export function BudgetPanel() {
  const { state } = useApp();
  const rows = useMemo(() => buildCosts(state), [state]);
  const total = rows.reduce((sum, row) => sum + (row.amountCNY ?? 0), 0);
  const budget = state.draft.budgetPerPerson ? state.draft.budgetPerPerson * state.draft.travelers : null;
  const over = budget != null && total > budget;
  return (
    <div>
      <div className="section-title">一路要花多少钱</div>
      {rows.map((row, i) => (
        <div key={i} className="cost-row">
          <span className="cost-label">
            {row.label}
            <span className="cost-kind">
              {row.kind === "live" ? "渠道实时价" : row.kind === "estimate" ? "本地估算（非成交价）" : "预算预留"}
              {row.note ? ` · ${row.note}` : ""}
            </span>
          </span>
          <span className="cost-amount">{formatCNY(row.amountCNY)}</span>
        </div>
      ))}
      <div className="cost-total">
        <span>合计（{state.draft.travelers} 人）</span>
        <span style={{ color: over ? "var(--danger)" : "var(--warm)" }}>{formatCNY(total)}</span>
      </div>
      {budget != null && (
        <div className="sub-text" style={{ marginTop: 8 }}>
          {over ? (
            <span style={{ color: "var(--danger)", fontWeight: 700 }}>
              超出人均预算约 {formatCNY(total - budget)}：试试换住宿档位、改交通席别或减一天。
            </span>
          ) : (
            <>在预算 {formatCNY(budget)} 内，还有 {formatCNY(budget - total)} 余量。</>
          )}
        </div>
      )}
    </div>
  );
}

import type { AppState } from "../store";

function buildCosts(state: AppState): { label: string; amountCNY: number | null; kind: "live" | "estimate" | "reserved"; note?: string }[] {
  const rows: { label: string; amountCNY: number | null; kind: "live" | "estimate" | "reserved"; note?: string }[] = [];
  const draft = state.draft;
  const nights = Math.max(draft.dayCount - 1, 1);

  const outbound = state.transports.find((t) => t.direction === "outbound" && t.id === state.selectedOutboundID);
  const retur = state.transports.find((t) => t.direction === "return" && t.id === state.selectedReturnID);
  for (const [label, option] of [
    ["去程大交通", outbound],
    ["返程大交通", retur]
  ] as const) {
    const quote = option && bestQuote(option.quotes);
    const per = quote?.amountCNY != null ? quote.amountCNY * draft.travelers : null;
    rows.push({
      label,
      amountCNY: per,
      kind: quote?.amountCNY != null ? "live" : "reserved",
      note: quote?.sourceLabel
    });
  }

  const stays = state.accommodations.filter((a) => a.id === state.selectedAccommodationID);
  const stayQuote = stays.length ? bestQuote(stays[0].quotes) : null;
  const stayTotal = stayQuote?.amountCNY != null ? stayQuote.amountCNY * nights * Math.ceil(draft.travelers / 2) : null;
  rows.push({
    label: `住宿（${nights} 晚）`,
    amountCNY: stayTotal,
    kind: stayQuote?.amountCNY != null ? "live" : "reserved",
    note: stayQuote?.amountCNY != null ? `${stays[0].name} · ${stayQuote.providerTitle}` : "选定住处后计费"
  });

  const ticketTotal = Object.values(state.tickets).reduce((sum, t) => sum + (t.amountCNY ?? 0) * draft.travelers, 0);
  rows.push({
    label: "景点门票",
    amountCNY: Object.keys(state.tickets).length ? ticketTotal : null,
    kind: ticketTotal > 0 ? "live" : "reserved",
    note: Object.keys(state.tickets).length ? `${Object.keys(state.tickets).length} 处已查到公开起价` : "公开列表命中后回填"
  });

  const cityTransit = draft.dayCount * draft.travelers * 12;
  rows.push({ label: "市内交通（地铁/公交估算）", amountCNY: cityTransit, kind: "estimate", note: "按每人每天约 12 元估算" });

  const meal = draft.dayCount * draft.travelers * (draft.pace === "relaxed" ? 150 : 120);
  rows.push({ label: "餐饮（估算）", amountCNY: meal, kind: "estimate", note: "按人均每天约 100–150 元估算" });

  return rows;
}

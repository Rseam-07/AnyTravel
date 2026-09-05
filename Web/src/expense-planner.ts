import type { AppState } from "./store";
import type { BookingConfirmation, ProviderQuote } from "./types";

export type ExpenseSource = "confirmed" | "queried" | "reference" | "estimate" | "reserved";

export interface ExpenseLine {
  id: string;
  label: string;
  amountCNY: number;
  source: ExpenseSource;
  note: string;
  pendingItems: string[];
}

export interface ExpenseSummary {
  rows: ExpenseLine[];
  plannedTotalCNY: number;
  confirmedTotalCNY: number;
  quotedTotalCNY: number;
  pendingItems: string[];
}

const SOURCE_TITLE: Record<ExpenseSource, string> = {
  confirmed: "已确认支出",
  queried: "渠道查询价",
  reference: "参考价",
  estimate: "本地估算",
  reserved: "预算预留"
};

export function expenseSourceTitle(source: ExpenseSource): string {
  return SOURCE_TITLE[source];
}

function preferredQuote(quotes: ProviderQuote[]): ProviderQuote | undefined {
  return [...quotes]
    .filter((quote) => quote.amountCNY != null && quote.kind !== "demo")
    .sort((a, b) => {
      const freshness = Number(Boolean(a.isStale)) - Number(Boolean(b.isStale));
      if (freshness !== 0) return freshness;
      const kindRank = (quote: ProviderQuote) => quote.kind === "live" ? 0 : quote.kind === "indicative" ? 1 : 2;
      return kindRank(a) - kindRank(b) || (a.amountCNY ?? Number.MAX_SAFE_INTEGER) - (b.amountCNY ?? Number.MAX_SAFE_INTEGER);
    })[0];
}

function sourceForQuote(quote?: ProviderQuote): ExpenseSource {
  if (!quote) return "reserved";
  if (quote.isStale || quote.kind === "indicative") return "reference";
  if (quote.kind === "live") return "queried";
  if (quote.kind === "budgetEstimate") return "estimate";
  return "reserved";
}

function matchingConfirmation(
  confirmations: BookingConfirmation[],
  kind: BookingConfirmation["kind"],
  itemID?: string | null
): BookingConfirmation | undefined {
  return itemID ? confirmations.find((item) => item.kind === kind && item.itemID === itemID) : undefined;
}

function transportTotal(quote: ProviderQuote | undefined, travelers: number): number | null {
  if (!quote) return null;
  if (quote.totalAmountCNY != null) return quote.totalAmountCNY;
  if (quote.amountCNY == null) return null;
  return quote.unit === "perPerson" ? quote.amountCNY * travelers : quote.amountCNY;
}

function accommodationTotal(quote: ProviderQuote | undefined, travelers: number, nights: number, rooms: number): number | null {
  if (!quote) return null;
  if (quote.totalAmountCNY != null) return quote.totalAmountCNY;
  if (quote.amountCNY == null) return null;
  if (quote.unit === "total") return quote.amountCNY;
  if (quote.unit === "perPerson") return quote.amountCNY * travelers;
  return quote.amountCNY * nights * rooms;
}

export function buildExpenseSummary(state: AppState): ExpenseSummary {
  const { draft } = state;
  const travelers = Math.max(draft.travelers, 1);
  const nights = draft.skipAccommodation ? 0 : Math.max(draft.dayCount - 1, 1);
  const rooms = Math.max(Math.ceil(travelers / 2), 1);
  const totalBudget = Math.max((draft.budgetPerPerson ?? 0) * travelers, 0);
  const rows: ExpenseLine[] = [];

  const transportEntries = [
    { id: "outbound-transport", label: "去程大交通", option: state.transports.find((item) => item.direction === "outbound" && item.id === state.selectedOutboundID) },
    { id: "return-transport", label: "返程大交通", option: state.transports.find((item) => item.direction === "return" && item.id === state.selectedReturnID) }
  ];
  for (const entry of transportEntries) {
    if (draft.skipTransport) {
      rows.push({ id: entry.id, label: entry.label, amountCNY: 0, source: "estimate", note: "已按你的选择跳过", pendingItems: [] });
      continue;
    }
    const quote = entry.option ? preferredQuote(entry.option.quotes) : undefined;
    const confirmation = matchingConfirmation(state.bookingConfirmations, "transport", entry.option?.id);
    const quoted = transportTotal(quote, travelers);
    const actual = confirmation?.actualAmountCNY;
    rows.push({
      id: entry.id,
      label: entry.label,
      amountCNY: actual ?? quoted ?? Math.round(totalBudget * 0.12),
      source: actual != null ? "confirmed" : quoted != null ? sourceForQuote(quote) : "reserved",
      note: actual != null
        ? `${confirmation?.title ?? entry.option?.title ?? entry.label} · 用户记录的订单总额`
        : quoted != null
          ? `${entry.option?.title ?? entry.label} · ${quote?.unit === "perPerson" ? `¥${quote.amountCNY}/人 × ${travelers}人` : "本次行程总价"}${confirmation ? " · 已确认购票，实付未记录" : ""}`
          : "尚未取得可用报价，先留出总预算的 12%",
      pendingItems: quoted == null ? [`${entry.label}票价`] : []
    });
  }

  const stay = state.accommodations.find((item) => item.id === state.selectedAccommodationID);
  const stayQuote = stay ? preferredQuote(stay.quotes) : undefined;
  const stayConfirmation = matchingConfirmation(state.bookingConfirmations, "accommodation", stay?.id);
  const quotedStay = nights === 0 ? 0 : accommodationTotal(stayQuote, travelers, nights, rooms);
  const actualStay = stayConfirmation?.actualAmountCNY;
  const stayPending = nights === 0 ? [] : [
    stayQuote?.taxesIncluded === true ? null : stayQuote?.taxesIncluded === false ? "住宿税费（渠道标记未含）" : "住宿税费",
    stayQuote?.mealPlan ? null : "早餐",
    "住宿押金"
  ].filter((item): item is string => Boolean(item));
  const stayFormula = stayQuote?.totalAmountCNY != null || stayQuote?.unit === "total"
    ? `渠道返回本次入住总价 · ${nights}晚 · ${rooms}间`
    : stayQuote?.amountCNY != null
      ? `¥${stayQuote.amountCNY}/晚 × ${nights}晚 × ${rooms}间`
      : `${nights}晚 × ${rooms}间 · 当前按每间 2 名成人估算`;
  rows.push({
    id: "accommodation",
    label: `住宿（${nights}晚 · ${rooms}间）`,
    amountCNY: nights === 0 ? 0 : actualStay ?? quotedStay ?? Math.round(totalBudget * 0.34),
    source: nights === 0 ? "estimate" : actualStay != null ? "confirmed" : quotedStay != null ? sourceForQuote(stayQuote) : "reserved",
    note: nights === 0
      ? "已跳过或无需过夜"
      : actualStay != null
        ? `${stayConfirmation?.title ?? stay?.name ?? "住宿"} · 用户记录的订单总额`
        : `${stay?.name ?? "住宿待选"} · ${stayFormula}${stayConfirmation ? " · 已确认预订，实付未记录" : ""}`,
    pendingItems: stayPending
  });

  const ticketableIDs = new Set(state.plan?.days.flatMap((day) => day.stops.filter((stop) => stop.place.interest !== "food").map((stop) => stop.place.id)) ?? []);
  const pricedTickets = Object.entries(state.tickets).filter(([id, quote]) => ticketableIDs.has(id) && quote.amountCNY != null);
  const knownTicketTotal = pricedTickets.reduce((sum, [, quote]) => sum + (quote.amountCNY ?? 0) * travelers, 0);
  const unknownTicketCount = Math.max(ticketableIDs.size - pricedTickets.length, 0);
  const ticketEnvelope = Math.round(totalBudget * 0.13);
  rows.push({
    id: "tickets",
    label: "景点与预约",
    amountCNY: unknownTicketCount > 0 ? Math.max(knownTicketTotal, ticketEnvelope) : knownTicketTotal,
    source: unknownTicketCount > 0 ? "reserved" : "reference",
    note: pricedTickets.length === 0
      ? `${ticketableIDs.size}处尚待逐项核价，先保留总预算的 13%`
      : unknownTicketCount > 0
        ? `${pricedTickets.length}处采用公开起价，另${unknownTicketCount}处按预算预留`
        : `${pricedTickets.length}处采用公开起价；票种与优惠仍需复核`,
    pendingItems: unknownTicketCount > 0 ? [`${unknownTicketCount}处景点票价`] : []
  });

  rows.push(
    { id: "meals", label: "餐饮", amountCNY: Math.round(totalBudget * 0.17), source: "reserved", note: `${travelers}人 × ${draft.dayCount}天 · 按轻松节奏预留`, pendingItems: [] },
    { id: "local", label: "市内交通", amountCNY: Math.round(totalBudget * 0.07), source: "reserved", note: "地铁、公交与必要打车的预算额度", pendingItems: [] },
    { id: "buffer", label: "机动金", amountCNY: Math.round(totalBudget * 0.05), source: "reserved", note: "价格波动、临时调整与尚未计入的零散费用", pendingItems: [] }
  );

  const pendingItems = [...new Set(rows.flatMap((row) => row.pendingItems))];
  return {
    rows,
    plannedTotalCNY: rows.reduce((sum, row) => sum + row.amountCNY, 0),
    confirmedTotalCNY: rows.filter((row) => row.source === "confirmed").reduce((sum, row) => sum + row.amountCNY, 0),
    quotedTotalCNY: rows.filter((row) => row.source === "queried" || row.source === "reference").reduce((sum, row) => sum + row.amountCNY, 0),
    pendingItems
  };
}

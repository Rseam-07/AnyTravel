// AnyTravel Web shared domain types.
// These mirror the iOS models (LogisticsModels / TripModels) kept in sync by hand
// until Contracts/ codegen lands (see Documentation/PLAN_TO_1_0.md M0).

export type Interest =
  | "gardens"
  | "culture"
  | "food"
  | "nature"
  | "family"
  | "night";

export const INTERESTS: { id: Interest; title: string; searchTerm: string }[] = [
  { id: "gardens", title: "园林古迹", searchTerm: "名胜古迹 园林 古镇" },
  { id: "culture", title: "人文博物馆", searchTerm: "博物馆 美术馆 纪念馆" },
  { id: "food", title: "本地饮食", searchTerm: "美食 小吃 老街" },
  { id: "nature", title: "自然慢逛", searchTerm: "公园 湖泊 山 步道" },
  { id: "family", title: "亲子体验", searchTerm: "亲子 乐园 科技馆" },
  { id: "night", title: "夜间活动", searchTerm: "夜景 夜市 演出" }
];

export type Pace = "relaxed" | "balanced" | "full";
export const PACE_META: Record<Pace, { title: string; stopsPerDay: number; note: string }> = {
  relaxed: { title: "松弛", stopsPerDay: 2, note: "每天 2 处主要停留，留足午餐与机动时间" },
  balanced: { title: "适中", stopsPerDay: 3, note: "每天 3 处，兼顾景点与舒适" },
  full: { title: "充实", stopsPerDay: 4, note: "每天 4 处，适合来过或体力好" }
};

export type TransportMode = "walking" | "transit" | "driving";
export type LongDistanceMode = "train" | "flight" | "bus" | "self-driving";

export interface Coord {
  lat: number;
  lng: number;
}

export interface TravelPlace {
  id: string;
  name: string;
  address?: string;
  coordinate: Coord;
  interest: Interest;
  source: string; // "Nominatim/OSM" | "backend/amap" | "user"
  opening?: string; // human readable opening hours if any
  rating?: number;
  ticket?: TicketQuote | null;
  planningPriority?: "primary" | "supplemental";
}

export interface TicketQuote {
  provider: string;
  amountCNY?: number | null;
  capturedAt?: string;
  bookingURL?: string;
  note: string;
}

export interface ProviderQuote {
  provider: string;
  providerTitle: string;
  amountCNY?: number | null;
  unit: "perNight" | "total" | "perPerson";
  kind: "live" | "indicative" | "budgetEstimate" | "demo" | "requiresPartnerAccess" | "checkOnProvider";
  capturedAt?: string;
  bookingURL?: string;
  note?: string;
  sourceLabel?: string;
  roomName?: string;
  mealPlan?: string;
  cancellationPolicy?: string;
  taxesIncluded?: boolean;
  availability?: string;
  isStale?: boolean;
}

export interface AccommodationOption {
  id: string;
  name: string;
  brand?: string;
  address?: string;
  coordinate?: Coord;
  starRating?: number;
  description?: string;
  imageURL?: string;
  amenities?: string[];
  tags?: string[];
  officialWebsiteURL?: string;
  quotes: ProviderQuote[];
  attractionDistanceMeters?: number;
  stationDistanceMeters?: number;
  airportDistanceMeters?: number;
  nameDistanceMeters: number;
  nameMeters: number;
}

export interface TransportOption {
  id: string;
  mode: "train" | "flight" | "bus" | "self-driving";
  title: string;
  originName: string;
  destinationName: string;
  direction: "outbound" | "return";
  departureTime?: Date;
  arrivalTime?: Date;
  durationMinutes?: number;
  quotes: ProviderQuote[];
  availability?: string;
  recommendationReasons?: string[];
  isRecommended?: boolean;
  arrivalAccessPoint?: { name: string; kind: "rail" | "airport" | "bus" | "metro"; coordinate: Coord };
  hotelTransferMeters?: number | null;
}

export interface CostRecord {
  category: string;
  label: string;
  amountCNY?: number | null;
  kind: "live" | "estimate" | "reserved";
  note?: string;
}

export interface PlanStop {
  place: TravelPlace;
  arriveMinute?: number;
  leaveMinute?: number;
  arrivalText?: string;
  departureText?: string;
  visitMinutes: number;
  moveMinutes?: number;
  moveFrom?: Coord;
  isPrimary: boolean;
  opening?: string;
  ticket?: TicketQuote | null;
  note?: string;
}

export interface PlanDay {
  dateLabel: string;
  title: string;
  stops: PlanStop[];
  totalMinutes: number;
  visitMinutes: number;
  travelMinutes: number;
  availableMinutes: number;
  overCapacity: boolean;
  assessment: string;
  badges: string[];
  route: { from: Coord; to: Coord }[];
}

export interface Plan {
  days: PlanDay[];
  generatedAt: string;
  totalCostCNY?: number;
  notes: string[];
  engine: "web-heuristic" | "backend";
}

export interface TripDraft {
  origin: string;
  destination: string;
  destinationCoord?: Coord;
  startDate?: string; // yyyy-mm-dd
  dayCount: number;
  travelers: number;
  budgetPerPerson?: number;
  pace: Pace;
  interests: Interest[];
  transportMode: TransportMode;
  longDistanceMode?: LongDistanceMode;
  skipAccommodation: boolean;
  skipTransport: boolean;
}

export interface WeatherDay {
  date: string;
  code: number;
  maxTemp: number;
  minTemp: number;
  precipitationProbability: number;
}

export interface ProviderIssue {
  provider: string;
  providerTitle: string;
  status: string;
  detail?: string;
}

export interface ChannelStatus {
  name: string;
  status: "configured" | "disabled" | "unverified" | "failed";
  detail?: string;
}

export const DAY_BUDGETS: Record<Pace, { start: number; daytimeEnd: number; nightEnd: number; lunch: number; lunchDuration: number; buffer: number }> = {
  relaxed: { start: 10 * 60, daytimeEnd: 17 * 60 + 30, nightEnd: 21 * 60, lunch: 12 * 60, lunchDuration: 90, buffer: 0.2 },
  balanced: { start: 9 * 60 + 30, daytimeEnd: 18 * 60 + 30, nightEnd: 21 * 60 + 30, lunch: 12 * 60, lunchDuration: 75, buffer: 0.15 },
  full: { start: 9 * 60, daytimeEnd: 20 * 60, nightEnd: 22 * 60, lunch: 12 * 60 + 15, lunchDuration: 60, buffer: 0.1 }
};

export const INTEREST_MINUTES: Record<Interest, number> = {
  gardens: 105,
  culture: 120,
  food: 75,
  nature: 120,
  family: 150,
  night: 100
};

export function formatCNY(amount?: number | null): string {
  if (amount == null || Number.isNaN(amount)) return "待查";
  return `¥${Math.round(amount).toLocaleString("zh-CN")}`;
}

export function clockText(minute?: number): string {
  if (minute == null) return "--:--";
  const h = Math.floor(minute / 60);
  const m = Math.round(minute % 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export function durationText(minutes?: number): string {
  if (minutes == null || minutes == 0) return "即刻";
  if (minutes < 60) return `${Math.round(minutes)} 分钟`;
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  return m === 0 ? `${h} 小时` : `${h} 小时 ${m} 分钟`;
}

export function meterText(meters?: number): string {
  if (meters == null) return "距离待查";
  if (meters < 1000) return `${Math.round(meters)} 米`;
  return `${(meters / 1000).toFixed(1)} 公里`;
}

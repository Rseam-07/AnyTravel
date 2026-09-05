import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type ReactNode
} from "react";
import {
  DEFAULT_BACKEND_URL,
  channelStatusFromHealth,
  deepseekChat,
  interpretAssistant,
  fetchAccommodationCatalog,
  fetchHealth,
  fetchPlacesAround,
  fetchTickets,
  fetchTransport,
  loadSettings,
  nominatimSearch,
  osrmRoute,
  providerDisplayName,
  saveSettings,
  weatherForecast,
  type BackendCatalogHotel,
  type BackendTransportOption,
  type ChatMessage,
  type WebSettings
} from "./api";
import { bestQuote, distanceMeters, addDays, planItinerary } from "./planner";
import {
  PACE_META,
  type AccommodationOption,
  type ChannelStatus,
  type Coord,
  type Interest,
  type Plan,
  type ProviderQuote,
  type ProviderIssue,
  type TicketQuote,
  type TransportOption,
  type TravelPlace,
  type TripDraft,
  type WeatherDay
} from "./types";
import { INTERESTS } from "./types";
import { catalogPlaces } from "./catalog";
import { knowledgeCitiesRef, knowledgePlaces, lookupCity, lookupCityCoordinate } from "./knowledge";
import { normalizeActionType, parseAssistantEnvelope, partialAssistantReply, type AssistantAction } from "./chat";

import { AUTOSAVE_KEY, readTripStorage, restoredSnapshot, snapshotTrip, validDraft, writeTripStorage, type SavedTrip } from "./trip-storage";
import { hotelCheckOut, pickPreferredTransport, preserveSelectedItem, quoteTripKey, staleTicketQuotes } from "./quote-refresh";

export type Phase = "welcome" | "compose" | "planning" | "ready" | "failure";

export interface Focus {
  kind: "destination" | "day" | "place" | "accommodation" | "station" | "route";
  id?: string;
  coordinate?: Coord;
}


interface AppState {
  settings: WebSettings;
  phase: Phase;
  draft: TripDraft;
  places: TravelPlace[];
  plan: Plan | null;
  accommodations: AccommodationOption[];
  accommodationIssues: ProviderIssue[];
  transports: TransportOption[];
  transportIssues: ProviderIssue[];
  tickets: Record<string, TicketQuote>;
  ticketIssues: ProviderIssue[];
  weather: WeatherDay[] | null;
  channels: ChannelStatus[];
  focus: Focus | null;
  selectedDay: number;
  selectedAccommodationID: string | null;
  selectedOutboundID: string | null;
  selectedReturnID: string | null;
  notice: string | null;
  failureDetail: string | null;
  backendReachable: boolean;
  chatOpen: boolean;
  chatBusy: boolean;
  savedTrips: SavedTrip[];
  recoveryTrip: SavedTrip | null;
  currentTripID: string;
  storageIssue: string | null;
  lastPlanCost: number | null;
}

function defaultStartDate(): string {
  return new Date(Date.now() + 2 * 86_400_000).toISOString().slice(0, 10);
}

const emptyDraft = (): TripDraft => ({
  origin: "",
  destination: "",
  startDate: defaultStartDate(),
  dayCount: 3,
  travelers: 2,
  budgetPerPerson: 3000,
  pace: "relaxed",
  interests: ["gardens", "culture", "food", "nature"],
  transportMode: "transit",
  skipAccommodation: false,
  skipTransport: false
});

const initialState = (): AppState => ({
  settings: loadSettings(),
  phase: "welcome",
  draft: emptyDraft(),
  places: [],
  plan: null,
  accommodations: [],
  accommodationIssues: [],
  transports: [],
  transportIssues: [],
  tickets: {},
  ticketIssues: [],
  weather: null,
  channels: [],
  focus: null,
  selectedDay: 0,
  selectedAccommodationID: null,
  selectedOutboundID: null,
  selectedReturnID: null,
  notice: null,
  failureDetail: null,
  backendReachable: false,
  chatOpen: false,
  chatBusy: false,
  savedTrips: [],
  recoveryTrip: null,
  currentTripID: crypto.randomUUID(),
  storageIssue: null,
  lastPlanCost: null
});

type Action =
  | { type: "patch"; patch: Partial<AppState> }
  | { type: "patchDraft"; patch: Partial<TripDraft> }
  | { type: "setPlaces"; places: TravelPlace[] }
  | { type: "setPlan"; plan: Plan }
  | { type: "setAccommodations"; items: AccommodationOption[]; issues: ProviderIssue[] }
  | { type: "setTransports"; items: TransportOption[]; issues: ProviderIssue[] }
  | { type: "setTickets"; tickets: Record<string, TicketQuote>; issues: ProviderIssue[] }
  | { type: "setWeather"; weather: WeatherDay[] | null }
  | { type: "setChannel"; channels: ChannelStatus[] }
  | { type: "reset" };

function reducer(state: AppState, action: Action): AppState {
  switch (action.type) {
    case "patch":
      return { ...state, ...action.patch };
    case "patchDraft":
      return { ...state, draft: { ...state.draft, ...action.patch } };
    case "setPlaces":
      return { ...state, places: action.places };
    case "setPlan":
      return { ...state, plan: action.plan };
    case "setAccommodations":
      return { ...state, accommodations: action.items, accommodationIssues: action.issues };
    case "setTransports":
      return { ...state, transports: action.items, transportIssues: action.issues };
    case "setTickets":
      return { ...state, tickets: action.tickets, ticketIssues: action.issues };
    case "setWeather":
      return { ...state, weather: action.weather };
    case "setChannel":
      return { ...state, channels: action.channels };
    case "reset":
      return { ...initialState(), settings: state.settings, savedTrips: state.savedTrips };
    default:
      return state;
  }
}

interface AppApi {
  state: AppState;
  chatStream: string | null;
  updateDraft: (patch: Partial<TripDraft>) => void;
  dismissWelcome: () => void;
  resolveDestination: (query: string) => Promise<Coord | null>;
  searchPlaces: (query: string, coord?: Coord) => Promise<TravelPlace[]>;
  discoverPlaces: () => Promise<TravelPlace[]>;
  generatePlan: () => Promise<void>;
  refreshQuotes: () => Promise<void>;
  refreshWeather: () => Promise<void>;
  refreshChannels: () => Promise<void>;
  setFocus: (focus: Focus | null) => void;
  selectAccommodation: (id: string) => void;
  selectTransport: (id: string) => void;
  removeStop: (dayIndex: number, stopIndex: number) => Promise<void>;
  relaxPlan: () => Promise<void>;
  saveSettings: (settings: WebSettings) => void;
  toggleChat: (open?: boolean) => void;
  sendChat: (text: string) => Promise<string>;
  saveTrip: () => boolean;
  restoreDeletedTrip: (id: string) => void;
  restoreLastSession: () => void;
  loadTrip: (id: string) => void;
  deleteTrip: (id: string) => void;
  shareURL: () => string;
  resetAll: () => void;
}

const AppContext = createContext<AppApi | null>(null);

export function useApp(): AppApi {
  const api = useContext(AppContext);
  if (!api) throw new Error("useApp must be used inside AppProvider");
  return api;
}

const DRAFT_KEY = "anytravel-web:draft";

function loadSavedDraft(): TripDraft | null {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    const draft: unknown = raw ? JSON.parse(raw) : null;
    return validDraft(draft) ? draft : null;
  } catch {
    return null;
  }
}

const NOMINATIM_DELAY_MS = 1150;

function hashId(text: string): string {
  let hash = 0;
  for (let i = 0; i < text.length; i++) hash = (hash * 31 + text.charCodeAt(i)) >>> 0;
  return hash.toString(36);
}

function classifyType(place: { type?: string; class?: string; name: string; address?: Record<string, string> }): Interest {
  const text = `${place.type ?? ""} ${place.class ?? ""} ${place.name}`.toLowerCase();
  if (/(museum|art|美术|博物|文化|历史|memorial|纪念馆)/.test(text)) return "culture";
  if (/(restaurant|fast_food|cafe|food|餐饮|小吃|美食|茶|菜)/.test(text)) return "food";
  if (/(park|公园|湖泊|湖|山|wetland|湿地|forest|森林|步道|island|岛)/.test(text)) return "nature";
  if (/(zoo|动物园|theme_park|游乐|亲子|科技馆|水族馆|aquarium)/.test(text)) return "family";
  if (/(夜|灯光|night|演出|剧院|show)/.test(text)) return "night";
  return "gardens";
}

function isAttractionLike(place: { class?: string; type?: string }): boolean {
  const cls = place.class ?? "";
  const type = place.type ?? "";
  const tourism = /^(attraction|museum|gallery|zoo|theme_park|aquarium|viewpoint|picnic_site|artwork|camp_site|walking)$/.test(type);
  const historic = /^(castle|monument|garden|city_gate|palace|museum|fort|tower|ruins|archaeological_site|memorial|wayside_shrine)$/.test(type);
  const amenityKitchen = /^(restaurant|fast_food|cafe|bar|pub|nightclub|theatre|cinema)$/.test(type);
  const naturalBar = /^(peak|wood|hill|water|wetland|beach|bay|island)$/.test(type);
  return tourism || historic || amenityKitchen || naturalBar;
}

function scorePOI(poi: { name: string; opening?: string | null; rating?: number | null }): number {
  let score = 0;
  const name = poi.name;
  if (/园|宫|博物馆|纪念馆|古镇|老街|寺|塔|桥/.test(name)) score += 6;
  if (/府|中心|广场|公园|culture|museum/.test(name)) score += 2;
  if (/连锁|酒店|宾馆|村|中心$/.test(name)) score -= 3; // chain hotels / trivial names rank lower
  if (poi.opening) score += 1;
  return score;
}

function normalizeInterest(value: string): Interest {
  return INTERESTS.some((i) => i.id === value) ? (value as Interest) : "gardens";
}

function orderByPreferences(places: TravelPlace[], preferred: Interest[]): TravelPlace[] {
  // Keep the mix: preferred interests first, but never all one category at the top.
  const primary = preferred.slice(0, 2);
  const secondary = preferred.filter((i) => !primary.includes(i));
  return [...places].sort((a, b) => {
    const rank = (interest: Interest) =>
      primary.includes(interest) ? 0 : secondary.includes(interest) ? 1 : 2;
    const aScore = rank(a.interest) * 1000 - scorePOI(a);
    const bScore = rank(b.interest) * 1000 - scorePOI(b);
    return aScore - bScore;
  });
}

export function AppProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reducer, undefined, initialState);
  const stateRef = useRef({ ...state, lastChatReply: undefined as string | undefined });
  stateRef.current = { ...state, lastChatReply: stateRef.current.lastChatReply } as never;
  const [chatStream, setChatStream] = useState<string | null>(null);
  const quoteRequestRef = useRef(0);

  const updateDraft = useCallback((patch: Partial<TripDraft>) => {
    stateRef.current.draft = { ...stateRef.current.draft, ...patch };
    dispatch({ type: "patchDraft", patch });
  }, []);

  const setFocus = useCallback((focus: Focus | null) => {
    if (focus?.kind === "day") {
      const selectedDay = Number(focus.id);
      if (Number.isInteger(selectedDay) && selectedDay >= 0) {
        stateRef.current.selectedDay = selectedDay;
        dispatch({ type: "patch", patch: { focus, selectedDay } });
        return;
      }
    }
    dispatch({ type: "patch", patch: { focus } });
  }, []);

  const dismissWelcome = useCallback(() => {
    const saved = loadSavedDraft();
    if (saved && saved.destination) {
      dispatch({ type: "patch", patch: { draft: saved, phase: "compose" } });
    } else {
      dispatch({ type: "patch", patch: { phase: "compose" } });
    }
  }, []);

  const resolveDestination = useCallback(async (query: string): Promise<Coord | null> => {
    const commitDestination = (destination: string, coordinate: Coord) => {
      const current = stateRef.current.draft;
      const changed = current.destination !== destination || !current.destinationCoord || distanceMeters(current.destinationCoord, coordinate) > 1000;
      if (changed) {
        const cleared: Partial<AppState> = {
          places: [],
          plan: null,
          accommodations: [],
          accommodationIssues: [],
          transports: [],
          transportIssues: [],
          tickets: {},
          ticketIssues: [],
          weather: null,
          focus: null,
          selectedDay: 0,
          selectedAccommodationID: null,
          selectedOutboundID: null,
          selectedReturnID: null,
          notice: null,
          failureDetail: null,
          phase: "compose"
        };
        Object.assign(stateRef.current, cleared);
        dispatch({ type: "patch", patch: cleared });
      }
      updateDraft({ destination, destinationCoord: coordinate });
    };

    const localCity = lookupCity(query);
    const localCoordinate = lookupCityCoordinate(query);
    if (localCity && localCoordinate) {
      commitDestination(localCity.city, localCoordinate);
      return localCoordinate;
    }
    try {
      const results = await nominatimSearch(stateRef.current.settings.backendURL, query, 5);
      const city = results.find((r) => r.type === "administrative" || r.addresstype === "city") ?? results[0];
      if (!city || !Number.isFinite(city.latitude) || !Number.isFinite(city.longitude)) return null;
      const coord: Coord = { lat: city.latitude, lng: city.longitude };
      commitDestination(city.name, coord);
      return coord;
    } catch {
      return null;
    }
  }, [updateDraft]);

  const searchPlaces = useCallback(async (query: string, coord?: Coord): Promise<TravelPlace[]> => {
    const center = coord ?? stateRef.current.draft.destinationCoord;
    const results = await nominatimSearch(stateRef.current.settings.backendURL, query, 12);
    const centerCoord = center ?? { lat: 31.3, lng: 120.6 };
    return results
      .filter((r) => isAttractionLike(r))
      .map((r) => ({
        id: `osm-${Math.round(r.latitude * 1e5)}-${Math.round(r.longitude * 1e5)}`,
        name: r.name || r.display_name.split(",")[0],
        address: r.display_name.slice(0, 140),
        coordinate: { lat: r.latitude, lng: r.longitude },
        interest: classifyType(r),
        source: "Nominatim/OSM",
        rating: undefined,
        opening: undefined
      }))
      .filter((p) => distanceMeters(centerCoord, p.coordinate) <= 60000)
      .slice(0, 12);
  }, []);

  const discoverPlaces = useCallback(async (): Promise<TravelPlace[]> => {
    const draft = stateRef.current.draft;
    if (!draft.destination || !draft.destinationCoord) return [];
    const center = draft.destinationCoord;
    const base = stateRef.current.settings.backendURL;

    // Stable local packs come first. The planner should not wait for a remote
    // POI service when the destination is already covered on-device.
    const builtIn = catalogPlaces(draft.destination);
    if (builtIn.length >= 2) {
      dispatch({ type: "setPlaces", places: builtIn });
      return builtIn;
    }
    const guidePlaces = knowledgePlaces(draft.destination, draft.interests);
    if (guidePlaces.length >= 4) {
      dispatch({ type: "setPlaces", places: guidePlaces });
      return guidePlaces;
    }

    // Primary source: OpenStreetMap POIs (tourism/historic/leisure/amenity)
    // fetched through the companion node; no provider key required.
    try {
      const pois = await fetchPlacesAround(base, {
        latitude: center.lat,
        longitude: center.lng,
        radius: 18000,
        limit: 32
      });
      if (pois.length >= 4) {
        const buckets = pois
          .filter((poi) => poi.name && poi.name.length >= 2)
          .map((poi) => ({
            id: poi.id,
            name: poi.name,
            address: poi.address ?? undefined,
            coordinate: { lat: poi.latitude, lng: poi.longitude } as Coord,
            interest: normalizeInterest(poi.interest),
            source: "OpenStreetMap · Overpass" as const,
            opening: poi.opening ?? undefined,
            planningPriority: undefined as "primary" | "supplemental" | undefined
          }));
        const preferred = draft.interests;
        const ranked = orderByPreferences(buckets, preferred);
        const final = ranked.slice(0, 20).map((place, index) => ({
          ...place,
          planningPriority: index < Math.max(PACE_META[draft.pace].stopsPerDay, 2)
            ? ("primary" as const)
            : ("supplemental" as const)
        }));
        dispatch({ type: "setPlaces", places: final });
        return final;
      }
    } catch {
      // Fall through to the Nominatim path below.
    }

    // Last resort: keyword search on Nominatim (weaker for Chinese POI names).
    const queries = ["热门景点 必去", ...INTERESTS.filter((i) => draft.interests.includes(i.id)).map((i) => i.searchTerm)];
    const seen = new Map<string, TravelPlace>();
    let order = 0;
    for (const query of queries) {
      try {
        const results = await searchPlaces(`${draft.destination} ${query}`, draft.destinationCoord);
        for (const place of results) {
          const key = `${Math.round(place.coordinate.lat * 500)}:${Math.round(place.coordinate.lng * 500)}`;
          if (!seen.has(key)) {
            seen.set(key, { ...place, planningPriority: order < 4 ? "primary" : "supplemental" });
          }
          order++;
        }
      } catch {
        /* keep going with other keywords */
      }
      await new Promise((r) => setTimeout(r, NOMINATIM_DELAY_MS));
    }
    const places = [...seen.values()].slice(0, 40);
    dispatch({ type: "setPlaces", places });
    return places;
  }, [searchPlaces]);

  const generatePlan = useCallback(async () => {
    const draft = stateRef.current.draft;
    if (!draft.destination) {
      dispatch({ type: "patch", patch: { phase: "failure", failureDetail: "先告诉我目的地城市。" } });
      return;
    }
    if (!draft.startDate) {
      updateDraft({ startDate: defaultStartDate() });
      draft.startDate = defaultStartDate();
    }
    dispatch({ type: "patch", patch: { phase: "planning", notice: "正在翻阅这座城市的热门去处…" } });
    try {
      let places = stateRef.current.places;
      if (places.length < 2) {
        places = await discoverPlaces();
      }
      if (places.length < 2) throw new Error("地图与在线资料暂时没有找到足够的地点，请换个目的地或兴趣再试。");

      // Build a usable result immediately, then replace matching estimates
      // with real road durations when the public router responds in time.
      const estimatedPlan = planItinerary(places, draft);
      const pairs = estimatedPlan.days.flatMap((day) => day.route).slice(0, 18);
      const realRoutes: { from: Coord; to: Coord; minutes: number }[] = [];
      const mode = draft.transportMode === "walking" ? "walking" : "driving";
      let cursor2 = 0;
      const worker = async () => {
        for (;;) {
          const index = cursor2++;
          if (index >= pairs.length) return;
          const pair = pairs[index];
          try {
            const route = await osrmRoute([pair.from, pair.to], mode);
            if (route) realRoutes.push({ from: pair.from, to: pair.to, minutes: route.durationMinutes });
          } catch {
            /* keep estimate for this segment */
          }
        }
      };
      await Promise.all(Array.from({ length: 6 }, () => worker()));

      const plan = realRoutes.length > 0
        ? planItinerary(places, draft, realRoutes)
        : estimatedPlan;
      stateRef.current.plan = plan;
      stateRef.current.phase = "ready";
      stateRef.current.selectedDay = 0;
      stateRef.current.failureDetail = null;
      dispatch({ type: "setPlan", plan });
      dispatch({ type: "patch", patch: { phase: "ready", notice: null, selectedDay: 0, failureDetail: null } });
      void refreshQuotes();
      void refreshWeather();
    } catch (error) {
      dispatch({
        type: "patch",
        patch: { phase: "failure", failureDetail: error instanceof Error ? error.message : String(error) }
      });
    }
  }, [discoverPlaces]);

  const refreshQuotes = useCallback(async () => {
    const draft = stateRef.current.draft;
    const base = stateRef.current.settings.backendURL;
    const plan = stateRef.current.plan;
    const requestID = ++quoteRequestRef.current;
    const tripKey = quoteTripKey(draft, plan?.generatedAt);

    if (!draft.startDate) {
      dispatch({
        type: "setAccommodations",
        items: [],
        issues: [{ provider: "日期", providerTitle: "行程日期", status: "missing", detail: "先补出发日期，才能查询住宿与班次的实时价格。" }]
      });
      dispatch({
        type: "setTransports",
        items: [],
        issues: [{ provider: "日期", providerTitle: "行程日期", status: "missing", detail: "先补出发日期，才能查询班次与席位价格。" }]
      });
      return;
    }

    const accommodationRequest = draft.skipAccommodation
      ? Promise.resolve({ attempted: false, succeeded: true, items: [] as AccommodationOption[], issues: [] as ProviderIssue[] })
      : fetchAccommodationCatalog(base, {
        destination: draft.destination,
        checkIn: draft.startDate,
        checkOut: hotelCheckOut(draft.startDate, draft.dayCount),
        adults: draft.travelers,
        rooms: Math.max(Math.ceil(draft.travelers / 2), 1),
        size: 20,
        anchors: plan?.days.flatMap((d) => d.stops.map((s) => s.place.name)).slice(0, 6) ?? []
      }).then(catalog => ({
        attempted: true, succeeded: true,
        items: catalog.hotels.map<AccommodationOption>((hotel) => ({
          id: hotel.providerHotelID, name: hotel.name, brand: hotel.brand, address: hotel.address,
          coordinate: hotel.latitude != null && hotel.longitude != null ? { lat: hotel.latitude, lng: hotel.longitude } : undefined,
          starRating: hotel.starRating ?? undefined, description: hotel.description, imageURL: hotel.imageURL,
          amenities: hotel.amenities, tags: hotel.tags, quotes: offersToQuotes(hotel), nameDistanceMeters: 0, nameMeters: 0
        })),
        issues: catalog.diagnostics.map(d => ({ ...d, providerTitle: providerDisplayName(d.provider) }))
      })).catch(error => ({
        attempted: true, succeeded: false, items: [] as AccommodationOption[],
        issues: [{ provider: "service", providerTitle: "在线住宿服务", status: "failed", detail: error instanceof Error ? error.message : String(error) }]
      }));

    const transportRequest = draft.skipTransport || !draft.origin
      ? Promise.resolve({ attempted: false, succeeded: true, items: [] as TransportOption[], issues: [] as ProviderIssue[] })
      : fetchTransport(base, {
          origin: draft.origin,
          destination: draft.destination,
          departureDate: draft.startDate,
          returnDate: addDays(draft.startDate, draft.dayCount - 1),
          adults: draft.travelers,
          modes: ["train", "flight"]
        }).then(transport => ({
          attempted: true, succeeded: true, items: transport.options.map(toTransportOption),
          issues: transport.diagnostics.map(d => ({ ...d, providerTitle: providerDisplayName(d.provider) }))
        })).catch(error => ({
          attempted: true, succeeded: false, items: [] as TransportOption[],
          issues: [{ provider: "service", providerTitle: "在线交通服务", status: "failed", detail: error instanceof Error ? error.message : String(error) }]
        }));

    // Tickets for planned stops.
    const stopNames = plan?.days.flatMap((day) => day.stops
      .filter((stop) => stop.isPrimary && !["food", "night"].includes(stop.place.interest))
      .map((stop) => ({
        id: stop.place.id,
        name: stop.place.name,
        address: stop.place.address,
        interest: stop.place.interest
      }))) ?? [];
    const ticketRequest = stopNames.length === 0
      ? Promise.resolve({ attempted: false, succeeded: true, tickets: {} as Record<string, TicketQuote>, issues: [] as ProviderIssue[] })
      : fetchTickets(base, {
          destination: draft.destination,
          visitDate: draft.startDate,
          attractions: stopNames
        }).then(tickets => {
        const map: Record<string, TicketQuote> = {};
        for (const q of tickets.quotes) {
          const place = stopNames.find((s) => s.id === q.attractionID || s.name === q.name);
          if (place) {
            map[place.id] = {
              provider: "qunar",
              amountCNY: q.amountCNY,
              capturedAt: q.capturedAt,
              bookingURL: q.bookingURL,
              note: q.note ?? "去哪儿公开展示起价；票种与库存需在购买页复核"
            };
          }
        }
        return { attempted: true, succeeded: true, tickets: map,
          issues: tickets.diagnostics.map(d => ({ ...d, providerTitle: providerDisplayName(d.provider) })) };
      }).catch(error => ({
        attempted: true, succeeded: false, tickets: {} as Record<string, TicketQuote>,
        issues: [{ provider: "service", providerTitle: "在线门票服务", status: "failed", detail: error instanceof Error ? error.message : String(error) }]
      }));

    // Run independent searches together, then commit once. A slow response from
    // an older city or date is discarded instead of being painted over a new trip.
    const [accommodationResult, transportResult, ticketResult] = await Promise.all([
      accommodationRequest, transportRequest, ticketRequest
    ]);
    if (requestID !== quoteRequestRef.current || quoteTripKey(stateRef.current.draft, stateRef.current.plan?.generatedAt) !== tripKey) return;

    const current = stateRef.current;
    const catalogItems = draft.skipAccommodation ? [] : preserveSelectedItem(
      accommodationResult.items, current.accommodations, current.selectedAccommodationID, accommodationResult.succeeded
    );
    const transportItems = draft.skipTransport ? [] : preserveSelectedItem(
      transportResult.items, current.transports,
      current.selectedOutboundID ?? current.selectedReturnID, transportResult.succeeded
    );
    // Preserve both directions independently if either chosen option disappeared.
    const finalTransportItems = draft.skipTransport
      ? []
      : preserveSelectedItem(transportItems, current.transports, current.selectedReturnID, transportResult.succeeded);
    const finalTickets = ticketResult.succeeded ? ticketResult.tickets : staleTicketQuotes(current.tickets);

    let selectedAccommodationID = current.selectedAccommodationID;
    let selectedOutboundID = current.selectedOutboundID;
    let selectedReturnID = current.selectedReturnID;
    const picks: string[] = [];
    if (!draft.skipAccommodation && !selectedAccommodationID) {
      const priced = catalogItems
        .flatMap((a) => a.quotes
          .filter((q) => q.amountCNY != null && q.kind !== "demo")
          .map((q) => ({ id: a.id, amount: q.amountCNY ?? 0, title: a.name, provider: q.providerTitle })))
        .sort((a, b) => a.amount - b.amount)[0];
      selectedAccommodationID = priced?.id ?? null;
      if (priced) picks.push(`住宿：${priced.title} ¥${priced.amount}/晚（${priced.provider}）`);
    }
    if (!draft.skipTransport && !selectedOutboundID) {
      const outbound = pickPreferredTransport(finalTransportItems.filter(t => t.direction === "outbound"), draft.longDistanceMode);
      selectedOutboundID = outbound?.id ?? null;
      if (outbound) picks.push(`去程：${summarizeTransport(outbound)}`);
    }
    if (!draft.skipTransport && !selectedReturnID) {
      const retur = pickPreferredTransport(finalTransportItems.filter(t => t.direction === "return"), draft.longDistanceMode);
      selectedReturnID = retur?.id ?? null;
      if (retur) picks.push(`返程：${summarizeTransport(retur)}`);
    }
    const backendSucceeded = [accommodationResult, transportResult, ticketResult].some(result => result.attempted && result.succeeded);
    const patch = {
      accommodations: catalogItems, accommodationIssues: accommodationResult.issues,
      transports: finalTransportItems, transportIssues: transportResult.issues,
      tickets: finalTickets, ticketIssues: ticketResult.issues,
      selectedAccommodationID, selectedOutboundID, selectedReturnID,
      backendReachable: backendSucceeded || current.backendReachable,
      notice: picks.length > 0 ? `已帮你预选：${picks.join("；")}。都可以在对应页更换。` : null
    };
    Object.assign(stateRef.current, patch);
    dispatch({ type: "patch", patch });
  }, []);

function summarizeTransport<T extends { title: string; quotes: { amountCNY?: number | null; providerTitle: string }[] }>(option: T): string {
  const quote = option.quotes.find((q) => q.amountCNY != null);
  return quote ? `${option.title}（¥${quote.amountCNY}，${quote.providerTitle}）` : option.title;
}

  const refreshWeather = useCallback(async () => {
    const draft = stateRef.current.draft;
    const coord = draft.destinationCoord;
    if (!coord) return;
    try {
      const forecast = await weatherForecast(coord, Math.max(draft.dayCount + 5, 10));
      dispatch({ type: "setWeather", weather: forecast.days });
    } catch {
      dispatch({ type: "setWeather", weather: null });
    }
  }, []);

  const refreshChannels = useCallback(async () => {
    const base = stateRef.current.settings.backendURL;
    const health = await fetchHealth(base);
    dispatch({ type: "setChannel", channels: channelStatusFromHealth(health) });
    dispatch({ type: "patch", patch: { backendReachable: Object.keys(health).length > 0 } });
  }, []);

  const selectAccommodation = useCallback((id: string) => {
    dispatch({ type: "patch", patch: { selectedAccommodationID: id } });
    const item = stateRef.current.accommodations.find((a) => a.id === id);
    if (item?.coordinate) setFocus({ kind: "accommodation", id, coordinate: item.coordinate });
  }, [setFocus]);

  const selectTransport = useCallback((id: string) => {
    const option = stateRef.current.transports.find((t) => t.id === id);
    if (!option) return;
    if (option.direction === "outbound") {
      dispatch({ type: "patch", patch: { selectedOutboundID: id } });
    } else {
      dispatch({ type: "patch", patch: { selectedReturnID: id } });
    }
    const coordinate = option.arrivalAccessPoint?.coordinate;
    if (coordinate) setFocus({ kind: "station", id, coordinate });
  }, [setFocus]);

  const rePlanFromPlaces = useCallback(async () => {
    await generatePlan();
  }, [generatePlan]);

  const removeStop = useCallback(
    async (dayIndex: number, stopIndex: number) => {
      const plan = stateRef.current.plan;
      const places = stateRef.current.places;
      if (!plan || !places.length) return;
      const stop = plan.days[dayIndex]?.stops[stopIndex];
      if (!stop) return;
      const nextPlaces = places.filter((p) => p.id !== stop.place.id);
      stateRef.current.places = nextPlaces;
      dispatch({ type: "setPlaces", places: nextPlaces });
      await rePlanFromPlaces();
    },
    [rePlanFromPlaces]
  );

  const relaxPlan = useCallback(async () => {
    const draft = stateRef.current.draft;
    const places = stateRef.current.places;
    const neededDays = Math.max(Math.ceil(places.length / 3), 1);
    updateDraft({ pace: "relaxed", dayCount: Math.max(draft.dayCount, Math.min(neededDays, 10)) });
    await generatePlan();
  }, [generatePlan, updateDraft]);

  const persistSettings = useCallback((settings: WebSettings) => {
    saveSettings(settings);
    stateRef.current.settings = settings;
    dispatch({ type: "patch", patch: { settings } });
  }, []);

  const toggleChat = useCallback((open?: boolean) => {
    dispatch({ type: "patch", patch: { chatOpen: open ?? !stateRef.current.chatOpen } });
  }, []);

  const sendChat = useCallback(
    async (text: string): Promise<string> => {
      const settings = stateRef.current.settings;
      const draft = stateRef.current.draft;
      dispatch({ type: "patch", patch: { chatBusy: true } });
      setChatStream("");
      const messages: ChatMessage[] = [
        {
          role: "system",
          content:
            "你是 AnyTravel 地图旅行规划助手。用户用中文口语表达行程意图。" +
            "你只能执行以下白名单动作（可多选，value 类型要准确）：" +
            '{"type":"setDestination","value":"城市名"}、{"type":"setOrigin","value":"城市名"}' +
            '{"type":"setStartDate","value":"YYYY-MM-DD"}、{"type":"setDayCount","value":3}、' +
            '{"type":"setTravelers","value":2}、{"type":"setBudget","value":3000}、' +
            '{"type":"setPace","value":"relaxed|balanced|full"}、' +
            '{"type":"addInterest","value":"gardens|culture|food|nature|family|night"}、' +
            '{"type":"setTransportMode","value":"walking|transit|driving"}。' +
            "禁止：创建或假装存在具体景点、酒店、班次、票价；不确定的信息写进 reply 询问用户。" +
            '只返回严格 JSON：{"reply":"中文回复（简短，最多2句）","actions":[...]}'
        },
        { role: "user", content: `当前行程：目的地${draft.destination || "未定"}，${draft.dayCount}天，${draft.travelers}人，预算${draft.budgetPerPerson ?? "未定"}元/人，节奏${PACE_META[draft.pace].title}。\n用户说：${text}` }
      ];
      let replyText: string | null = null;
      let actions: AssistantAction[] = [];

      try {
        const result = await interpretAssistant(settings, text, {
          destination: draft.destination,
          origin: draft.origin,
          dayCount: draft.dayCount,
          travelers: draft.travelers,
          budgetPerPerson: draft.budgetPerPerson,
          pace: draft.pace,
          travelMode: draft.transportMode,
          interests: draft.interests,
          startDate: draft.startDate,
          selectedDayIndex: stateRef.current.selectedDay,
          places: (stateRef.current.plan?.days ?? []).flatMap((day, dayIndex) =>
            day.stops.map((stop) => ({ name: stop.place.name, dayIndex, interest: stop.place.interest }))
          )
        });
        replyText = result.reply;
        actions = result.actions;
      } catch {
        if (settings.deepseekKey.trim()) {
          try {
            const answer = await deepseekChat(settings, messages, (partial) => {
              setChatStream(partialAssistantReply(partial) ?? "正在整理你的行程条件…");
            });
            const parsed = parseAssistantEnvelope(answer);
            const plainAnswer = answer.trim();
            replyText = parsed.reply ?? (plainAnswer.startsWith("{") || plainAnswer.startsWith("```") ? null : plainAnswer);
            actions = parsed.actions;
          } catch {
            // The deterministic local parser below still handles common edits.
          }
        }
      }

      let nextDraft: TripDraft = { ...draft, interests: [...draft.interests] };
      let requestedPlan = false;
      for (const action of actions) {
        switch (normalizeActionType(action.type)) {
          case "setDestination": {
            const value = String(action.value ?? "").trim();
            if (!value) break;
            const coordinate = await resolveDestination(value);
            if (coordinate) {
              nextDraft = {
                ...nextDraft,
                destination: lookupCity(value)?.city ?? value,
                destinationCoord: coordinate
              };
            }
            break;
          }
          case "setOrigin":
            nextDraft.origin = String(action.value ?? "").trim();
            break;
          case "setStartDate":
            if (typeof action.value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(action.value)) {
              nextDraft.startDate = action.value;
            }
            break;
          case "setDayCount":
            nextDraft.dayCount = clampInt(action.value, 1, 14, nextDraft.dayCount);
            break;
          case "setTravelers":
            nextDraft.travelers = clampInt(action.value, 1, 10, nextDraft.travelers);
            break;
          case "setBudget":
            nextDraft.budgetPerPerson = clampInt(action.value, 100, 100000, nextDraft.budgetPerPerson ?? 3000);
            break;
          case "setPace":
            if (["relaxed", "balanced", "full"].includes(String(action.value))) {
              nextDraft.pace = action.value as TripDraft["pace"];
            }
            break;
          case "addInterest": {
            const interest = String(action.value) as Interest;
            if (INTERESTS.some((item) => item.id === interest) && !nextDraft.interests.includes(interest)) {
              nextDraft.interests = [...nextDraft.interests, interest];
            }
            break;
          }
          case "removeInterest": {
            const interest = String(action.value) as Interest;
            nextDraft.interests = nextDraft.interests.filter((item) => item !== interest);
            if (nextDraft.interests.length === 0) nextDraft.interests = ["gardens"];
            break;
          }
          case "setTransportMode":
            if (["walking", "transit", "driving"].includes(String(action.value))) {
              nextDraft.transportMode = action.value as TripDraft["transportMode"];
            }
            break;
          case "setLongDistanceMode": {
            const value = String(action.value);
            const mapped = value === "driving" ? "self-driving" : value === "coach" ? "bus" : value;
            if (["train", "flight", "bus", "self-driving"].includes(mapped)) {
              nextDraft.longDistanceMode = mapped as TripDraft["longDistanceMode"];
            }
            break;
          }
          case "generatePlan":
            requestedPlan = String(action.value).toLowerCase() !== "false";
            break;
        }
      }

      if (actions.length === 0) {
        nextDraft = { ...nextDraft, ...localParse(text, nextDraft) };
        const mentioned = knowledgeCitiesRef().find((city) =>
          (!draft.destination && text.includes(city.city)) ||
          text.includes(`去${city.city}`) ||
          text.includes(`到${city.city}`) ||
          text.includes(`目的地${city.city}`) ||
          text.includes(`改成${city.city}`)
        );
        if (mentioned?.coord) {
          await resolveDestination(mentioned.city);
          nextDraft.destination = mentioned.city;
          nextDraft.destinationCoord = mentioned.coord;
        }
        const origin = text.match(/从\s*([\u4e00-\u9fa5]{2,10}?)(?:出发|启程|走)/)?.[1];
        if (origin) nextDraft.origin = origin;
      }

      const changed = JSON.stringify(nextDraft) !== JSON.stringify(draft);
      if (changed) {
        stateRef.current.draft = nextDraft;
        dispatch({ type: "patchDraft", patch: nextDraft });
      }
      replyText ??= changed
        ? "已经把这句话里的条件改好了，我会按新的节奏重新排路线。"
        : "我还没抓到要改的条件。可以直接说目的地、天数、人数、预算或旅行节奏。";
      stateRef.current.lastChatReply = replyText;
      setChatStream(null);
      dispatch({
        type: "patch",
        patch: {
          chatBusy: false,
          notice: changed ? "条件已更新，正在重新整理路线。" : null
        }
      });
      if ((changed || requestedPlan) && nextDraft.destination) void generatePlan();
      return stateRef.current.lastChatReply ?? "";
    },
    [generatePlan, resolveDestination]
  );

  const reportStorageFailure = useCallback((error: unknown) => {
    const detail = error instanceof Error && error.message.includes("原记录") ? error.message : "本机存储未能写入，可能空间不足或被隐私设置限制。当前页面的安排仍在，请先保留页面或打印导出。";
    dispatch({ type: "patch", patch: { storageIssue: detail } });
  }, []);

  const saveTrip = useCallback((): boolean => {
    const current = stateRef.current;
    if (!current.draft.destination) return false;
    const trip = snapshotTrip(current, current.currentTripID);
    const next = [trip, ...current.savedTrips.filter(t => t.id !== trip.id)];
    try {
      writeTripStorage(localStorage, next);
      stateRef.current.savedTrips = next;
      dispatch({ type: "patch", patch: { savedTrips: next, storageIssue: null, notice: "完整方案已存入本机旅册。清理浏览器数据会移除本机记录。" } });
      return true;
    } catch (error) { reportStorageFailure(error); return false; }
  }, [reportStorageFailure]);

  const restoreTrip = useCallback((trip: SavedTrip) => {
    const snapshot = restoredSnapshot(trip);
    const patch: Partial<AppState> = {
      ...snapshot, currentTripID: trip.id, draft: trip.draft, phase: snapshot.plan ? "ready" : "compose",
      accommodationIssues: [], transportIssues: [], ticketIssues: [], weather: null,
      focus: { kind: "destination", coordinate: trip.draft.destinationCoord }, failureDetail: null,
      recoveryTrip: null, chatBusy: false,
      notice: snapshot.plan ? "已恢复原方案与选择，未重新排行程。保存的价格是历史记录，购买前请刷新复核。" : "已恢复行程条件，可以接着规划。"
    };
    Object.assign(stateRef.current, patch);
    dispatch({ type: "patch", patch });
  }, []);

  const loadTrip = useCallback((id: string) => {
    const trip = stateRef.current.savedTrips.find(t => t.id === id && !t.deletedAt);
    if (trip) restoreTrip(trip);
  }, [restoreTrip]);

  const restoreLastSession = useCallback(() => {
    const trip = stateRef.current.recoveryTrip;
    if (trip) restoreTrip(trip);
  }, [restoreTrip]);

  const changeDeletedState = useCallback((id: string, deleted: boolean) => {
    const next = stateRef.current.savedTrips.map(t => t.id === id ? { ...t, deletedAt: deleted ? new Date().toISOString() : undefined } : t);
    try {
      writeTripStorage(localStorage, next);
      stateRef.current.savedTrips = next;
      dispatch({ type: "patch", patch: { savedTrips: next, storageIssue: null } });
    } catch (error) { reportStorageFailure(error); }
  }, [reportStorageFailure]);
  const deleteTrip = useCallback((id: string) => changeDeletedState(id, true), [changeDeletedState]);
  const restoreDeletedTrip = useCallback((id: string) => changeDeletedState(id, false), [changeDeletedState]);

  const shareURL = useCallback((): string => {
    const draft = stateRef.current.draft;
    const payload = encodeURIComponent(btoa(unescape(encodeURIComponent(JSON.stringify({ draft })))));
    return `${location.origin}${location.pathname}#t=${payload}`;
  }, []);

  const resetAll = useCallback(() => {
    Object.assign(stateRef.current, initialState(), {
      settings: stateRef.current.settings,
      savedTrips: stateRef.current.savedTrips
    });
    dispatch({ type: "reset" });
  }, []);

  useEffect(() => {
    const saved = readTripStorage(localStorage);
    const recovery = readTripStorage(localStorage, AUTOSAVE_KEY);
    const patch = { savedTrips: saved.trips, recoveryTrip: recovery.trips[0] ?? null, storageIssue: saved.issue ?? recovery.issue };
    Object.assign(stateRef.current, patch);
    dispatch({ type: "patch", patch });
    const match = location.hash.match(/#t=(.+)/);
    if (match) {
      try {
        const parsed = JSON.parse(decodeURIComponent(escape(atob(decodeURIComponent(match[1]))))) as { draft: unknown };
        if (validDraft(parsed.draft)) {
          const shared = { draft: { ...emptyDraft(), ...parsed.draft }, phase: "compose" as const };
          Object.assign(stateRef.current, shared);
          dispatch({ type: "patch", patch: shared });
        }
      } catch { dispatch({ type: "patch", patch: { storageIssue: "这个分享链接未能读取，本机行程没有改变。" } }); }
    }
  }, []);

  const persistCurrentSession = useCallback(() => {
    const current = stateRef.current;
    if (current.phase === "welcome" || !current.draft.destination) return;
    try {
      writeTripStorage(localStorage, [snapshotTrip(current, current.currentTripID)], AUTOSAVE_KEY);
      localStorage.setItem(DRAFT_KEY, JSON.stringify(current.draft));
    } catch (error) { reportStorageFailure(error); }
  }, [reportStorageFailure]);

  useEffect(() => {
    const timer = window.setTimeout(persistCurrentSession, 500);
    return () => window.clearTimeout(timer);
  }, [state.draft, state.plan, state.places, state.accommodations, state.transports, state.tickets,
    state.selectedDay, state.selectedAccommodationID, state.selectedOutboundID, state.selectedReturnID, persistCurrentSession]);

  useEffect(() => {
    const onVisibility = () => { if (document.visibilityState === "hidden") persistCurrentSession(); };
    window.addEventListener("pagehide", persistCurrentSession);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.removeEventListener("pagehide", persistCurrentSession);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [persistCurrentSession]);

  // Auto refresh channels when backend URL changes.
  useEffect(() => {
    void refreshChannels();
  }, [state.settings.backendURL, refreshChannels]);

  const value = useMemo<AppApi>(
    () => ({
      state,
      chatStream,
      updateDraft,
      dismissWelcome,
      resolveDestination,
      searchPlaces,
      discoverPlaces,
      generatePlan,
      refreshQuotes,
      refreshWeather,
      refreshChannels,
      setFocus,
      selectAccommodation,
      selectTransport,
      removeStop,
      relaxPlan,
      saveSettings: persistSettings,
      toggleChat,
      sendChat,
      saveTrip,
      loadTrip,
      deleteTrip,
      restoreDeletedTrip,
      restoreLastSession,
      shareURL,
      resetAll
    }),
    [
      state,
      updateDraft,
      dismissWelcome,
      resolveDestination,
      searchPlaces,
      discoverPlaces,
      generatePlan,
      refreshQuotes,
      refreshWeather,
      refreshChannels,
      setFocus,
      selectAccommodation,
      selectTransport,
      removeStop,
      relaxPlan,
      persistSettings,
      toggleChat,
      sendChat,
      saveTrip,
      loadTrip,
      deleteTrip,
      restoreDeletedTrip,
      restoreLastSession,
      shareURL,
      resetAll
    ]
  );

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

function offersToQuotes(hotel: BackendCatalogHotel): ProviderQuote[] {
  const offers = hotel.offers ?? [];
  if (offers.length > 0) {
    return offers.map((offer) => ({
      provider: offer.provider,
      providerTitle: providerDisplayName(offer.provider),
      amountCNY: offer.amountCNY ?? null,
      unit: offer.unit === "total" ? "total" : offer.unit === "perPerson" ? "perPerson" : "perNight",
      kind: quoteKind(offer.kind, offer.amountCNY),
      capturedAt: offer.capturedAt ?? hotel.capturedAt,
      bookingURL: offer.bookingURL,
      note: offer.note,
      sourceLabel: offer.source,
      roomName: offer.roomName,
      mealPlan: offer.mealPlan,
      cancellationPolicy: offer.cancellationPolicy,
      taxesIncluded: offer.taxesIncluded,
      availability: offer.availability
    }));
  }
  if (hotel.provider) {
    return [
      {
        provider: hotel.provider,
        providerTitle: providerDisplayName(hotel.provider),
        amountCNY: hotel.amountCNY ?? null,
        unit: hotel.unit === "total" ? "total" : "perNight",
        kind: quoteKind(hotel.kind, hotel.amountCNY),
        capturedAt: hotel.capturedAt,
        note: hotel.note ?? "到渠道查看当前房型和价格",
        sourceLabel: hotel.source
      }
    ];
  }
  return [];
}

function quoteKind(kind?: string | null, amount?: number | null): ProviderQuote["kind"] {
  switch (kind) {
    case "live":
      return "live";
    case "indicative":
      return "indicative";
    case "budgetEstimate":
      return "budgetEstimate";
    case "demo":
      return "demo";
    case "requiresPartnerAccess":
      return "requiresPartnerAccess";
    default:
      return amount == null ? "checkOnProvider" : "live";
  }
}

function toTransportOption(option: BackendTransportOption): TransportOption {
  const offers = option.offers ?? [];
  const quotes: ProviderQuote[] =
    offers.length > 0
      ? offers.map((offer) => ({
          provider: offer.provider,
          providerTitle: providerDisplayName(offer.provider),
          amountCNY: offer.amountCNY ?? null,
          unit: "perPerson",
          kind: quoteKind(offer.kind, offer.amountCNY),
          capturedAt: offer.capturedAt ?? option.capturedAt,
          bookingURL: offer.bookingURL,
          note: `${offer.fareName} · ${offer.note}`,
          sourceLabel: offer.source,
          availability: offer.availability
        }))
      : [
          {
            provider: option.provider,
            providerTitle: providerDisplayName(option.provider),
            amountCNY: option.amountCNY ?? null,
            unit: "perPerson",
            kind: quoteKind(option.kind, option.amountCNY),
            capturedAt: option.capturedAt,
            bookingURL: option.bookingURL,
            note: `${option.fareName ?? ""} · ${option.note ?? ""}`.trim(),
            sourceLabel: option.source,
            availability: option.availability
          }
        ];
  const mode = option.mode as TransportOption["mode"];
  return {
    id: `${option.provider}-${option.direction ?? "out"}-${option.serviceNumber ?? option.departureTime ?? option.amountCNY ?? Math.random().toString(36).slice(2, 8)}`,
    mode,
    title: `${option.serviceNumber ?? providerDisplayName(option.provider)} · ${option.originName ?? ""}→${option.destinationName ?? ""}`,
    originName: option.originName ?? "",
    destinationName: option.destinationName ?? "",
    direction: option.direction === "return" ? "return" : "outbound",
    departureTime: option.departureTime ? new Date(option.departureTime) : undefined,
    arrivalTime: option.arrivalTime ? new Date(option.arrivalTime) : undefined,
    durationMinutes: option.durationMinutes ?? undefined,
    quotes,
    availability: option.availability,
    recommendationReasons: [],
    isRecommended: false
  };
}

function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(Math.round(n), min), max);
}

function localParse(
  text: string,
  draft: TripDraft
): Partial<TripDraft> {
  const patch: Partial<TripDraft> = {};
  const days = text.match(/(\d{1,2})\s*天/);
  if (days) patch.dayCount = clampInt(days[1], 1, 14, draft.dayCount);
  const people = text.match(/(\d{1,2})\s*人/);
  if (people) patch.travelers = clampInt(people[1], 1, 10, draft.travelers);
  const budget = text.match(/(\d+(?:\.\d+)?)\s*(万)?\s*(?:元|块|块钱|预算)/);
  if (budget) {
    let amount = Number(budget[1]);
    if (budget[2]) amount = amount * 10000;
    patch.budgetPerPerson = clampInt(amount, 100, 100000, draft.budgetPerPerson ?? 3000);
  }
  if (/(松弛|轻松|佛系|慢)/.test(text)) patch.pace = "relaxed";
  else if (/(紧凑|充实|赶|满满)/.test(text)) patch.pace = "full";
  else if (/(适中|标准)/.test(text)) patch.pace = "balanced";
  if (/(地铁|公交|公共交通)/.test(text)) patch.transportMode = "transit";
  else if (/(走路|步行)/.test(text)) patch.transportMode = "walking";
  else if (/(打车|自驾|开车|租车)/.test(text)) patch.transportMode = "driving";
  const interests = new Set(draft.interests);
  if (/(带娃|孩子|亲子|儿童)/.test(text)) interests.add("family");
  if (/(博物馆|美术馆|人文|历史)/.test(text)) interests.add("culture");
  if (/(吃|美食|小吃|夜市)/.test(text)) interests.add("food");
  if (/(自然|公园|山水|徒步|海边)/.test(text)) interests.add("nature");
  if (/(夜景|夜游|演出)/.test(text)) interests.add("night");
  if (interests.size !== draft.interests.length) patch.interests = [...interests];
  return patch;
}

export type { AppState };

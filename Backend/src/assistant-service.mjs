const allowedPaces = new Set(["relaxed", "balanced", "full"]);
const allowedTravelModes = new Set(["walking", "transit", "driving"]);
const allowedLongDistanceModes = new Set(["auto", "train", "flight", "driving", "coach"]);
const allowedAccommodationSorts = new Set(["recommended", "lowestPrice", "closestToAttractions", "closestToTransit"]);
const allowedInterests = new Set(["gardens", "culture", "food", "nature", "family", "night"]);
const allowedActionTypes = new Set([
  "set_destination",
  "set_origin",
  "set_pace",
  "set_travel_mode",
  "set_long_distance_mode",
  "set_skip_accommodation",
  "set_skip_transport",
  "set_day_count",
  "set_travelers",
  "set_adults",
  "set_children_ages",
  "set_rooms",
  "set_seniors",
  "set_mobility",
  "set_budget",
  "set_start_date",
  "set_end_date",
  "set_accommodation_max_price",
  "set_accommodation_sort",
  "add_interest",
  "remove_interest",
  "generate_plan",
  "focus_place",
  "remove_place"
]);

export async function interpretAssistantRequest(request, options = {}) {
  const env = options.env || process.env;
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  const now = options.now || (() => new Date());
  const cleanRequest = validateAssistantRequest(request);
  if (typeof env.AI?.run === "function") {
    const model = env.WORKERS_AI_MODEL || "@cf/qwen/qwen3-30b-a3b-fp8";
    try {
      const upstream = await env.AI.run(model, {
        messages: [
          { role: "system", content: `${systemPrompt}\n/no_think` },
          { role: "user", content: JSON.stringify(cleanRequest) }
        ],
        response_format: { type: "json_object" },
        max_tokens: 1024,
        temperature: 0.1
      });
      const content = upstream?.choices?.[0]?.message?.content ?? upstream?.response;
      const normalized = normalizeAssistantPayload(typeof content === "object" ? JSON.stringify(content) : content, cleanRequest.context.places);
      return { ...normalized, model, mode: "managed", capturedAt: now().toISOString() };
    } catch {
      return interpretAssistantLocally(cleanRequest, { now, degradedFrom: "workers_ai_unavailable" });
    }
  }
  const deepseekKey = String(env.DEEPSEEK_API_KEY || "").trim();
  const zaiKey = String(env.ZAI_API_KEY || "").trim();
  const apiKey = deepseekKey || zaiKey;
  if (!apiKey || typeof fetchImpl !== "function") {
    return interpretAssistantLocally(cleanRequest, {
      now,
      degradedFrom: apiKey ? "network_unavailable" : "managed_model_not_configured"
    });
  }

  const baseURL = normalizeHTTPSBaseURL(
    deepseekKey
      ? env.DEEPSEEK_BASE_URL || "https://api.deepseek.com"
      : env.ZAI_BASE_URL || "https://open.bigmodel.cn/api/paas/v4"
  );
  const model = String(
    deepseekKey
      ? env.DEEPSEEK_MODEL || "deepseek-chat"
      : env.ZAI_MODEL || "glm-5.3-flash"
  ).trim();
  const endpoint = new URL("chat/completions", baseURL);

  let response;
  try {
    response = await fetchImpl(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model,
        temperature: 0.1,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: JSON.stringify(cleanRequest) }
        ]
      }),
      signal: AbortSignal.timeout(45_000)
    });
  } catch (error) {
    const code = error?.name === "TimeoutError" ? "assistant_timeout" : "assistant_network_error";
    return interpretAssistantLocally(cleanRequest, { now, degradedFrom: code });
  }

  if (!response.ok) {
    return interpretAssistantLocally(cleanRequest, { now, degradedFrom: `upstream_http_${response.status}` });
  }

  let upstream;
  try {
    upstream = await response.json();
  } catch {
    return interpretAssistantLocally(cleanRequest, { now, degradedFrom: "upstream_invalid_json" });
  }
  const content = upstream?.choices?.[0]?.message?.content;
  let normalized;
  try {
    normalized = normalizeAssistantPayload(content, cleanRequest.context.places);
  } catch {
    return interpretAssistantLocally(cleanRequest, { now, degradedFrom: "upstream_invalid_contract" });
  }
  return {
    ...normalized,
    model,
    mode: "managed",
    capturedAt: now().toISOString()
  };
}

export function validateAssistantRequest(request) {
  if (!request || typeof request !== "object") {
    throw new AssistantError("invalid_request", 400, "JSON body is required");
  }
  const input = String(request.input || "").trim();
  if (!input) throw new AssistantError("invalid_request", 400, "input is required");
  if (input.length > 1_000) throw new AssistantError("invalid_request", 400, "input is too long");

  const source = request.context && typeof request.context === "object" ? request.context : {};
  const places = Array.isArray(source.places)
    ? source.places.slice(0, 80).map((place) => ({
        name: String(place?.name || "").trim().slice(0, 120),
        dayIndex: clampInteger(place?.dayIndex, 0, 6, 0),
        interest: String(place?.interest || "").trim().slice(0, 40)
      })).filter((place) => place.name)
    : [];
  return {
    input,
    context: {
      destination: String(source.destination || "").trim().slice(0, 120),
      dayCount: clampInteger(source.dayCount, 1, 7, 3),
      budgetPerPerson: clampInteger(source.budgetPerPerson, 1_000, 30_000, 3_000),
      pace: allowedPaces.has(source.pace) ? source.pace : "relaxed",
      travelMode: allowedTravelModes.has(source.travelMode) ? source.travelMode : "walking",
      selectedDayIndex: clampInteger(source.selectedDayIndex, 0, 6, 0),
      interests: Array.isArray(source.interests)
        ? source.interests.map(String).map((value) => value.slice(0, 40)).slice(0, 12)
        : [],
      origin: String(source.origin || "").trim().slice(0, 120),
      travelers: clampInteger(source.travelers, 1, 12, 1),
      adults: clampInteger(source.adults, 1, 8, null),
      childrenAges: normalizeChildrenAges(source.childrenAges),
      rooms: clampInteger(source.rooms, 1, 4, null),
      seniorTravelers: clampInteger(source.seniorTravelers, 0, 8, 0),
      mobilityNeed: ["none", "stroller", "wheelchair"].includes(source.mobilityNeed)
        ? source.mobilityNeed
        : "none",
      startDate: validDay(source.startDate) ? source.startDate : null,
      endDate: validDay(source.endDate) ? source.endDate : null,
      longDistanceMode: allowedLongDistanceModes.has(source.longDistanceMode) ? source.longDistanceMode : null,
      skipAccommodation: Boolean(source.skipAccommodation),
      skipTransport: Boolean(source.skipTransport),
      accommodationMaxNightlyPrice: clampInteger(source.accommodationMaxNightlyPrice, 100, 10_000, null),
      accommodationSort: allowedAccommodationSorts.has(source.accommodationSort)
        ? source.accommodationSort
        : "recommended",
      places
    }
  };
}

export function normalizeAssistantPayload(content, places = []) {
  let parsed;
  try {
    const text = typeof content === "string" ? content.trim() : "";
    const withoutFence = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
    parsed = JSON.parse(withoutFence);
  } catch {
    throw new AssistantError("assistant_invalid_response", 502, "智能服务没有返回约定的 JSON");
  }
  const canonicalPlaces = new Map(places.map((place) => [normalizeName(place.name), place.name]));
  const actions = [];
  for (const candidate of Array.isArray(parsed.actions) ? parsed.actions.slice(0, 16) : []) {
    const type = String(candidate?.type || "");
    if (!allowedActionTypes.has(type)) continue;
    if (type === "set_destination" || type === "set_origin") {
      const value = String(candidate.value || "").trim().slice(0, 80);
      if (value) actions.push({ type, value });
    } else if (type === "set_pace" && allowedPaces.has(candidate.value)) {
      actions.push({ type, value: candidate.value });
    } else if (type === "set_travel_mode" && allowedTravelModes.has(candidate.value)) {
      actions.push({ type, value: candidate.value });
    } else if (type === "set_long_distance_mode" && allowedLongDistanceModes.has(candidate.value)) {
      actions.push({ type, value: candidate.value });
    } else if ((type === "set_skip_accommodation" || type === "set_skip_transport")
      && ["true", "false"].includes(String(candidate.value).toLowerCase())) {
      actions.push({ type, value: String(candidate.value).toLowerCase() });
    } else if (type === "set_day_count") {
      const value = clampInteger(candidate.value, 1, 7, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if (type === "set_travelers") {
      const value = clampInteger(candidate.value, 1, 12, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if (type === "set_adults") {
      const value = clampInteger(candidate.value, 1, 8, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if (type === "set_children_ages") {
      const ages = normalizeChildrenAges(candidate.value);
      actions.push({ type, value: ages.join(",") });
    } else if (type === "set_rooms") {
      const value = clampInteger(candidate.value, 1, 4, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if (type === "set_seniors") {
      const value = clampInteger(candidate.value, 0, 8, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if (type === "set_mobility" && ["none", "stroller", "wheelchair"].includes(String(candidate.value))) {
      actions.push({ type, value: String(candidate.value) });
    } else if (type === "set_budget") {
      const value = clampInteger(candidate.value, 1_000, 30_000, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if ((type === "set_start_date" || type === "set_end_date") && validDay(candidate.value)) {
      actions.push({ type, value: candidate.value });
    } else if (type === "set_accommodation_max_price") {
      const value = clampInteger(candidate.value, 100, 10_000, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if (type === "set_accommodation_sort" && allowedAccommodationSorts.has(candidate.value)) {
      actions.push({ type, value: candidate.value });
    } else if ((type === "add_interest" || type === "remove_interest") && allowedInterests.has(candidate.value)) {
      actions.push({ type, value: candidate.value });
    } else if (type === "generate_plan" && ["true", "false"].includes(String(candidate.value).toLowerCase())) {
      actions.push({ type, value: String(candidate.value).toLowerCase() });
    } else if (type === "focus_place" || type === "remove_place") {
      const canonical = canonicalPlaces.get(normalizeName(candidate.value));
      if (canonical) actions.push({ type, value: canonical });
    }
  }
  const reply = String(parsed.reply || "我读懂了这句话，但没有找到可以安全执行的改动。")
    .trim()
    .slice(0, 600);
  return { reply, actions };
}

/**
 * Deterministic safety net for fields that can be changed without guessing.
 * It keeps basic natural-language map control available when the hosted model
 * has no credit or is temporarily unreachable.
 */
export function interpretAssistantLocally(cleanRequest, options = {}) {
  const now = options.now || (() => new Date());
  const input = cleanRequest.input.normalize("NFKC");
  const actions = [];
  const singleton = new Set([
    "set_destination", "set_origin", "set_pace", "set_travel_mode", "set_long_distance_mode",
    "set_skip_accommodation", "set_skip_transport", "set_day_count", "set_travelers", "set_adults",
    "set_children_ages", "set_rooms", "set_seniors", "set_mobility", "set_budget", "set_start_date",
    "set_end_date", "set_accommodation_max_price", "set_accommodation_sort", "generate_plan"
  ]);
  const add = (type, value) => {
    const text = String(value);
    if (singleton.has(type)) {
      const existing = actions.findIndex((action) => action.type === type);
      if (existing >= 0) actions.splice(existing, 1);
    }
    if (!actions.some((action) => action.type === type && action.value === text)) {
      actions.push({ type, value: text });
    }
  };

  const route = input.match(/从\s*([\p{Script=Han}A-Za-z·]{2,16}?)(?:出发)?\s*(?:去|到|前往)\s*([\p{Script=Han}A-Za-z·]{2,16}?)(?=游玩|游览|旅行|旅游|玩|[一二两三四五六七八九十\d]+天|[，。,.；;\s]|$)/u);
  if (route) {
    add("set_origin", cleanLocation(route[1]));
    add("set_destination", cleanLocation(route[2]));
  } else {
    const origin = input.match(/(?:从|出发地(?:是|在|定在)?)\s*([\p{Script=Han}A-Za-z·]{2,16}?)(?=[，。,.；;\s]|出发|$)/u);
    const destination = input.match(/(?:想去|要去|前往|目的地(?:是|在|定在)?)\s*([\p{Script=Han}A-Za-z·]{2,16}?)(?=[，。,.；;\s]|旅行|旅游|游玩|玩|[一二两三四五六七八九十\d]+天|$)/u);
    if (origin) add("set_origin", cleanLocation(origin[1]));
    if (destination && !/^(?:这些|那些|这里|那里|哪儿|哪里|什么)/.test(destination[1])) {
      add("set_destination", cleanLocation(destination[1]));
    }
  }

  const dayNight = input.match(/([一二两三四五六七八九十\d]+)\s*天(?:\s*([一二两三四五六七八九十\d]+)\s*晚)?/);
  const nights = input.match(/(?:住|停留)?\s*([一二两三四五六七八九十\d]+)\s*晚/);
  const dayCount = dayNight ? naturalInteger(dayNight[1]) : nights ? naturalInteger(nights[1]) + 1 : null;
  if (dayCount) add("set_day_count", clampInteger(dayCount, 1, 7, 3));

  const dateMatches = [...input.matchAll(/(?:(\d{4})\s*年)?\s*(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]/g)]
    .map((match) => resolveNaturalDate(match, now()))
    .filter(Boolean);
  if (dateMatches[0]) add("set_start_date", dateMatches[0]);
  if (dateMatches[1]) add("set_end_date", dateMatches[1]);
  else if (dateMatches[0] && dayCount) add("set_end_date", addUTCDateDays(dateMatches[0], dayCount - 1));

  const explicitAdults = input.match(/([一二两三四五六七八九十\d]+)\s*(?:位|个)?\s*成人/);
  const explicitTravelers = input.match(/([一二两三四五六七八九十\d]+)\s*(?:位|个)?\s*(?:人|同行)/);
  const childrenAges = [...input.matchAll(/(?:孩子|儿童|小朋友|宝宝)[^，。,.；;]{0,10}?([0-9]{1,2})\s*岁/g)]
    .map((match) => Number(match[1]))
    .filter((age) => age >= 0 && age <= 17)
    .slice(0, 6);
  let adults = explicitAdults ? naturalInteger(explicitAdults[1]) : null;
  let travelers = explicitTravelers ? naturalInteger(explicitTravelers[1]) : null;
  if (!adults && /我和(?:我的)?父母/.test(input)) adults = 3;
  if (adults) add("set_adults", clampInteger(adults, 1, 8, 1));
  if (childrenAges.length) add("set_children_ages", childrenAges.join(","));
  if (!travelers && adults) travelers = adults + childrenAges.length;
  if (travelers) add("set_travelers", clampInteger(travelers, 1, 12, 1));

  const rooms = input.match(/([一二两三四五六七八九十\d]+)\s*间(?:房|客房)?/);
  if (rooms) add("set_rooms", clampInteger(naturalInteger(rooms[1]), 1, 4, 1));
  const seniors = input.match(/([一二两三四五六七八九十\d]+)\s*(?:位|个)?\s*(?:老人|长辈)/);
  if (seniors) add("set_seniors", clampInteger(naturalInteger(seniors[1]), 0, 8, 0));
  if (/轮椅|无障碍/.test(input)) add("set_mobility", "wheelchair");
  else if (/婴儿车|童车/.test(input)) add("set_mobility", "stroller");

  const budget = input.match(/(?:每人|人均)?\s*(?:预算|控制在|不超过|大约|约)?\s*[¥￥]?\s*(\d{3,6})\s*元?(?:\/人|每人)?/);
  if (budget && /预算|每人|人均|控制|不超过/.test(input.slice(Math.max(0, (budget.index ?? 0) - 8), (budget.index ?? 0) + budget[0].length + 8))) {
    add("set_budget", clampInteger(budget[1], 1_000, 30_000, 3_000));
  }
  const nightly = input.match(/(?:酒店|住宿|房价)[^，。,.；;]{0,12}?(?:每晚|一晚|不超过|上限)\s*[¥￥]?\s*(\d{2,5})/);
  if (nightly) add("set_accommodation_max_price", clampInteger(nightly[1], 100, 10_000, 500));

  if (/轻松|松弛|悠闲|慢慢|别赶|不赶/.test(input)) add("set_pace", "relaxed");
  else if (/特种兵|紧凑|排满|多跑|高强度/.test(input)) add("set_pace", "full");
  else if (/适中|均衡|正常强度/.test(input)) add("set_pace", "balanced");
  if (/公交|地铁|公共交通/.test(input)) add("set_travel_mode", "transit");
  else if (/步行|走路/.test(input)) add("set_travel_mode", "walking");
  else if (/市内自驾|市内开车|租车/.test(input)) add("set_travel_mode", "driving");
  if (/高铁|动车|火车/.test(input)) add("set_long_distance_mode", "train");
  else if (/飞机|机票|航班/.test(input)) add("set_long_distance_mode", "flight");
  else if (/大巴|长途汽车/.test(input)) add("set_long_distance_mode", "coach");
  else if (/自驾|开车去/.test(input)) add("set_long_distance_mode", "driving");

  if (/不住酒店|不需要住宿|跳过住宿/.test(input)) add("set_skip_accommodation", "true");
  else if (/要住|需要住宿|找酒店|订酒店/.test(input)) add("set_skip_accommodation", "false");
  if (/不看交通|不需要交通|跳过交通/.test(input)) add("set_skip_transport", "true");
  else if (/查车票|查机票|推荐交通/.test(input)) add("set_skip_transport", "false");

  const interestRules = [
    ["gardens", /园林|古镇|古街|古迹|寺庙|建筑/],
    ["culture", /博物馆|美术馆|展览|人文|历史|文化/],
    ["food", /美食|吃|小吃|餐厅|菜|夜宵/],
    ["nature", /自然|山水|公园|徒步|湖|海|森林/],
    ["family", /亲子|孩子|儿童|乐园|动物园|海洋馆/],
    ["night", /夜景|夜游|夜市|酒吧|演出/]
  ];
  const interestInput = actions.filter(a => a.type === "set_origin" || a.type === "set_destination")
    .reduce((text, action) => text.replaceAll(action.value, ""), input);
  for (const [interest, pattern] of interestRules) if (pattern.test(interestInput)) add("add_interest", interest);
  if (/最便宜|低价优先|价格从低/.test(input)) add("set_accommodation_sort", "lowestPrice");
  else if (/离景点近|景点附近/.test(input)) add("set_accommodation_sort", "closestToAttractions");
  else if (/离地铁近|交通方便|车站附近/.test(input)) add("set_accommodation_sort", "closestToTransit");

  for (const place of cleanRequest.context.places) {
    const escaped = place.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (new RegExp(`(?:删除|移除|不去|去掉)[^，。,.；;]{0,4}${escaped}`).test(input)) add("remove_place", place.name);
    else if (new RegExp(`(?:看看|定位|聚焦|找到)[^，。,.；;]{0,4}${escaped}`).test(input)) add("focus_place", place.name);
  }
  if (/(?:规划|安排|制定|生成)[^，。,.；;]{0,10}(?:行程|路线|旅行)|(?:行程|路线)[^，。,.；;]{0,8}(?:规划|安排)/.test(input)) {
    add("generate_plan", "true");
  }

  const safeActions = actions.filter((action) => action.value && allowedActionTypes.has(action.type)).slice(0, 16);
  const reply = safeActions.length
    ? `云端理解暂时没有回应，我先把能确认的 ${safeActions.length} 项旅途线索落在地图上；你仍可继续用一句话调整。`
    : "云端理解暂时没有回应，这句话里也没有可安全执行的明确改动；城市、日期、预算和节奏都可以直接告诉我。";
  return {
    reply,
    actions: safeActions,
    model: "local-intent-v1",
    mode: "local-fallback",
    degradedFrom: options.degradedFrom || null,
    capturedAt: now().toISOString()
  };
}

function cleanLocation(value) {
  return String(value || "").trim().replace(/(?:市|地区)$/u, "").slice(0, 80);
}

function naturalInteger(value) {
  const text = String(value || "").trim();
  if (/^\d+$/.test(text)) return Number(text);
  const digits = { 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
  if (text === "十") return 10;
  if (text.startsWith("十")) return 10 + (digits[text[1]] || 0);
  if (text.endsWith("十")) return (digits[text[0]] || 0) * 10;
  if (text.includes("十")) return (digits[text[0]] || 0) * 10 + (digits[text[2]] || 0);
  return digits[text] || 0;
}

function resolveNaturalDate(match, reference) {
  let year = Number(match[1] || reference.getFullYear());
  const month = Number(match[2]);
  const day = Number(match[3]);
  let candidate = validCalendarDate(year, month, day);
  if (!match[1] && candidate && candidate.getTime() < startOfUTCDay(reference).getTime()) {
    candidate = validCalendarDate(++year, month, day);
  }
  return candidate?.toISOString().slice(0, 10) || null;
}

function validCalendarDate(year, month, day) {
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day ? date : null;
}

function startOfUTCDay(date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function addUTCDateDays(value, count) {
  const date = new Date(`${value}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}

function normalizeName(value) {
  return String(value || "").normalize("NFKC").trim().toLocaleLowerCase("zh-CN");
}

function clampInteger(value, minimum, maximum, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.round(number), minimum), maximum);
}

function normalizeChildrenAges(value) {
  const values = Array.isArray(value)
    ? value
    : String(value ?? "").split(/[，,、;；\s]+/).filter(Boolean);
  return values
    .map((age) => Number(age))
    .filter((age) => Number.isInteger(age) && age >= 0 && age <= 17)
    .slice(0, 6);
}

function validDay(value) {
  const text = String(value || "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return false;
  const date = new Date(`${text}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === text;
}

function normalizeHTTPSBaseURL(value) {
  let url;
  try { url = new URL(String(value)); }
  catch { throw new AssistantError("assistant_not_configured", 503, "智能服务地址无效"); }
  if (url.protocol !== "https:") {
    throw new AssistantError("assistant_not_configured", 503, "托管智能服务必须使用 HTTPS");
  }
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url;
}

const systemPrompt = `你是 AnyTravel 的旅行意图控制器。用户可以从一句完全自由的中文开始，也可以修改现有计划。只返回 JSON：
{"reply":"简洁、温暖、略有诗意的中文回应","actions":[{"type":"动作","value":"值"}]}
允许动作：
- set_destination: 用户明确说出的城市或区域
- set_origin: 出发城市
- set_day_count: 1 到 7
- set_travelers: 1 到 12
- set_adults: 成人数，1 到 8
- set_children_ages: 儿童年龄数组或逗号分隔年龄，0 到 17 岁，最多 6 个
- set_rooms: 房间数，1 到 4
- set_seniors: 需要照顾的老人数量，0 到 8
- set_mobility: none | stroller | wheelchair
- set_pace: relaxed | balanced | full
- set_travel_mode: walking | transit | driving
- set_long_distance_mode: auto | train | flight | driving | coach
- set_skip_accommodation / set_skip_transport: true | false
- set_budget: 1000 到 30000 的整数
- set_start_date / set_end_date: yyyy-MM-dd
- set_accommodation_max_price: 100 到 10000 的每晚价格
- set_accommodation_sort: recommended | lowestPrice | closestToAttractions | closestToTransit
- add_interest / remove_interest: gardens | culture | food | nature | family | night
- generate_plan: true | false；用户明确要求规划或安排行程时为 true
- focus_place: 必须与 context.places 中某个 name 完全相同
- remove_place: 必须与 context.places 中某个 name 完全相同
目的地会再由地图服务核验，可以提取用户明确说出的地点，但不要臆造。不要生成链接、代码或额外字段。无法安全操作时 actions 返回空数组。回复不超过 120 个汉字。`;

export class AssistantError extends Error {
  constructor(code, status, message) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

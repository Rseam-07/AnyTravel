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
  "set_day_count",
  "set_travelers",
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
  const apiKey = String(env.ZAI_API_KEY || "").trim();
  if (!apiKey) throw new AssistantError("assistant_not_configured", 503, "智能服务尚未配置");
  if (typeof fetchImpl !== "function") throw new AssistantError("assistant_unavailable", 503, "当前运行环境无法联网");

  const cleanRequest = validateAssistantRequest(request);
  const baseURL = normalizeHTTPSBaseURL(env.ZAI_BASE_URL || "https://open.bigmodel.cn/api/paas/v4");
  const model = String(env.ZAI_MODEL || "glm-5.3-flash").trim();
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
    throw new AssistantError(code, 502, "智能服务暂时没有回应");
  }

  if (!response.ok) {
    throw new AssistantError("assistant_upstream_error", 502, `智能服务返回 ${response.status}`);
  }

  let upstream;
  try {
    upstream = await response.json();
  } catch {
    throw new AssistantError("assistant_invalid_response", 502, "智能服务返回了无法读取的内容");
  }
  const content = upstream?.choices?.[0]?.message?.content;
  const normalized = normalizeAssistantPayload(content, cleanRequest.context.places);
  return {
    ...normalized,
    model,
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
      travelers: clampInteger(source.travelers, 1, 8, 1),
      startDate: validDay(source.startDate) ? source.startDate : null,
      endDate: validDay(source.endDate) ? source.endDate : null,
      longDistanceMode: allowedLongDistanceModes.has(source.longDistanceMode) ? source.longDistanceMode : null,
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
    } else if (type === "set_day_count") {
      const value = clampInteger(candidate.value, 1, 7, null);
      if (value !== null) actions.push({ type, value: String(value) });
    } else if (type === "set_travelers") {
      const value = clampInteger(candidate.value, 1, 8, null);
      if (value !== null) actions.push({ type, value: String(value) });
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

function normalizeName(value) {
  return String(value || "").normalize("NFKC").trim().toLocaleLowerCase("zh-CN");
}

function clampInteger(value, minimum, maximum, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.round(number), minimum), maximum);
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
- set_travelers: 1 到 8
- set_pace: relaxed | balanced | full
- set_travel_mode: walking | transit | driving
- set_long_distance_mode: auto | train | flight | driving | coach
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

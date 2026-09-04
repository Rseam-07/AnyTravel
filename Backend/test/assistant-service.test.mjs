import assert from "node:assert/strict";
import test from "node:test";
import {
  AssistantError,
  interpretAssistantRequest,
  normalizeAssistantPayload,
  validateAssistantRequest
} from "../src/assistant-service.mjs";

const context = {
  destination: "苏州",
  dayCount: 3,
  budgetPerPerson: 3_000,
  pace: "full",
  travelMode: "walking",
  selectedDayIndex: 0,
  interests: ["culture"],
  places: [
    { name: "拙政园", dayIndex: 0, interest: "gardens" },
    { name: "苏州博物馆", dayIndex: 0, interest: "culture" }
  ]
};

test("rejects an empty assistant instruction", () => {
  assert.throws(
    () => validateAssistantRequest({ input: "  ", context }),
    (error) => error instanceof AssistantError && error.code === "invalid_request"
  );
});

test("allows only typed actions and existing place names", () => {
  const result = normalizeAssistantPayload(JSON.stringify({
    reply: "已经替你放慢脚步，并把视线落在拙政园。",
    actions: [
      { type: "set_pace", value: "relaxed" },
      { type: "focus_place", value: "拙政园" },
      { type: "remove_place", value: "寒山寺" },
      { type: "set_budget", value: 999_999 },
      { type: "open_url", value: "https://example.com" }
    ]
  }), context.places);

  assert.deepEqual(result.actions, [
    { type: "set_pace", value: "relaxed" },
    { type: "focus_place", value: "拙政园" },
    { type: "set_budget", value: "30000" }
  ]);
});

test("accepts a complete free-form trip action set but clamps unsafe values", () => {
  const result = normalizeAssistantPayload(JSON.stringify({
    reply: "苏州已在地图上亮起。",
    actions: [
      { type: "set_destination", value: "苏州" },
      { type: "set_origin", value: "上海" },
      { type: "set_day_count", value: 9 },
      { type: "set_travelers", value: 2 },
      { type: "set_start_date", value: "2026-10-02" },
      { type: "set_end_date", value: "not-a-date" },
      { type: "set_long_distance_mode", value: "train" },
      { type: "set_accommodation_max_price", value: 600 },
      { type: "set_accommodation_sort", value: "lowestPrice" },
      { type: "generate_plan", value: true }
    ]
  }), context.places);

  assert.deepEqual(result.actions, [
    { type: "set_destination", value: "苏州" },
    { type: "set_origin", value: "上海" },
    { type: "set_day_count", value: "7" },
    { type: "set_travelers", value: "2" },
    { type: "set_start_date", value: "2026-10-02" },
    { type: "set_long_distance_mode", value: "train" },
    { type: "set_accommodation_max_price", value: "600" },
    { type: "set_accommodation_sort", value: "lowestPrice" },
    { type: "generate_plan", value: "true" }
  ]);
});

test("calls the OpenAI-compatible endpoint without exposing the key in the body", async () => {
  let capturedURL;
  let capturedOptions;
  const fetchImpl = async (url, options) => {
    capturedURL = url;
    capturedOptions = options;
    return new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify({
        reply: "路线正在慢下来。",
        actions: [{ type: "set_travel_mode", value: "transit" }]
      }) } }]
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  const result = await interpretAssistantRequest(
    { input: "公交优先", context },
    {
      fetchImpl,
      env: {
        ZAI_API_KEY: "secret-for-test",
        ZAI_BASE_URL: "https://open.bigmodel.cn/api/paas/v4",
        ZAI_MODEL: "glm-5.3-flash"
      },
      now: () => new Date("2026-08-31T12:00:00.000Z")
    }
  );

  assert.equal(capturedURL.href, "https://open.bigmodel.cn/api/paas/v4/chat/completions");
  assert.equal(capturedOptions.headers.authorization, "Bearer secret-for-test");
  assert.equal(capturedOptions.body.includes("secret-for-test"), false);
  assert.deepEqual(result.actions, [{ type: "set_travel_mode", value: "transit" }]);
  assert.equal(result.model, "glm-5.3-flash");
  assert.equal(result.capturedAt, "2026-08-31T12:00:00.000Z");
});

test("requires a server-side managed key", async () => {
  await assert.rejects(
    interpretAssistantRequest({ input: "轻松一点", context }, { env: {} }),
    (error) => error instanceof AssistantError && error.code === "assistant_not_configured"
  );
});

test("prefers a server-side DeepSeek configuration when both providers exist", async () => {
  let capturedURL;
  let capturedOptions;
  const fetchImpl = async (url, options) => {
    capturedURL = url;
    capturedOptions = options;
    return new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify({ reply: "已调整。", actions: [] }) } }]
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  const result = await interpretAssistantRequest(
    { input: "松弛一点", context },
    {
      fetchImpl,
      env: {
        DEEPSEEK_API_KEY: "deepseek-secret",
        DEEPSEEK_MODEL: "deepseek-chat",
        ZAI_API_KEY: "fallback-secret"
      }
    }
  );

  assert.equal(capturedURL.href, "https://api.deepseek.com/chat/completions");
  assert.equal(capturedOptions.headers.authorization, "Bearer deepseek-secret");
  assert.equal(result.model, "deepseek-chat");
});

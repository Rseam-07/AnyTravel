import assert from "node:assert/strict";

const base = process.env.ANYTRAVEL_SERVICE_URL || "http://127.0.0.1:8795";
async function call(path, body, token, origin = "https://rseam-07.github.io") {
  const response = await fetch(`${base}${path}`, { method: body ? "POST" : "GET", headers: {
    origin, ...(body ? { "content-type": "application/json" } : {}), ...(token ? { authorization: `Bearer ${token}` } : {})
  }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(55_000) });
  return { response, data: await response.json() };
}
const health = await call("/health");
assert.equal(health.response.status, 200); assert.equal(health.data.service, "anytravel-companion");
assert.equal(health.response.headers.get("access-control-allow-origin"), "https://rseam-07.github.io");
assert.equal((await call("/health", undefined, undefined, "https://untrusted.example")).response.status, 403);
const preflight = await fetch(`${base}/v1/handbooks`, { method: "OPTIONS", headers: { origin: "https://rseam-07.github.io", "access-control-request-method": "POST" } });
assert.equal(preflight.status, 204);
assert.equal((await call("/v1/assistant/interpret", { input: "" })).response.status, 400);
const book = { version: 1, id: "smoke-fixture", title: "Release smoke fixture", days: [], places: [], tickets: [], todos: [], documents: [], flights: [], rentals: [], stays: [], ledger: { bills: [], travelers: [] }, notes: ["Nonpersonal test data ".repeat(10000)] };
const created = await call("/v1/handbooks", { book }); assert.equal(created.response.status, 201);
const { id, token } = created.data;
const route = `/v1/handbooks/${id}`;
assert.equal((await call(route)).response.status, 401);
assert.deepEqual((await call(route, undefined, token)).data.book, book);
const updates = await Promise.all([call(route, { book: { ...book, title: "One" }, revision: 1 }, token), call(route, { book: { ...book, title: "Two" }, revision: 1 }, token)]);
assert.deepEqual(updates.map(r => r.response.status).sort(), [200, 409]);
assert.equal((await call(route, undefined, token)).data.revision, 2);
console.log("PASS Workers identity, CORS, preflight, validation, private multi-chunk storage and simultaneous-edit conflict.");

if (process.argv.includes("--live")) {
  const date = new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10);
  const out = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);
  const checks = [
    ["hotels", "/v1/accommodations/search", { destination: "苏州", checkIn: date, checkOut: out, adults: 2, rooms: 1, size: 10, anchors: ["拙政园"] }],
    ["railway", "/v1/quotes/transport", { origin: "上海", destination: "苏州", departureDate: date, adults: 2, modes: ["train"] }],
    ["flights", "/v1/quotes/transport", { origin: "宁波", destination: "天津", departureDate: date, adults: 2, modes: ["flight"] }],
    ["assistant", "/v1/assistant/interpret", { input: "从上海去苏州玩三天，两个人，轻松一点", context: { destination: "苏州", dayCount: 3, travelers: 2, places: [], interests: [] } }]
  ];
  for (const [name, path, body] of checks) {
    const result = await call(path, body);
    const rows = result.data.hotels || result.data.options || [];
    const priced = rows.filter(row => row.amountCNY > 0).length;
    console.log(JSON.stringify({ check: name, http: result.response.status, results: rows.length, priced, model: result.data.model, actions: result.data.actions?.length, diagnostics: result.data.diagnostics?.map(d => ({ provider: d.provider, status: d.status })) }));
    assert.equal(result.response.status, 200);
    if (name !== "assistant") assert.ok(priced > 0, `${name} returned no numeric prices`);
    else { assert.ok(result.data.actions?.length > 0); assert.equal(result.data.mode, "managed"); }
  }
}

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHandbookStore } from "../src/handbook-service.mjs";
import { createApp } from "../src/server.mjs";
const book = () => ({ version: 1, id: "test-book", title: "旅行手册", days: [], places: [], flights: [], stays: [], rentals: [], todos: [], tickets: [], documents: [], ledger: { travelers: [], bills: [], settings: { baseCurrency: "CNY" } } });
test("handbook store persists the whole book including settings, authenticates, and rejects concurrent stale writes", async () => {
  const dir = await mkdtemp(join(tmpdir(), "handbook-test-"));
  try {
    const s = createHandbookStore(dir), b = book(); b.todos.push({ id: "todo", text: "备份", completed: true });
    const c = await s.create(b); assert.equal(c.revision, 1);
    assert.deepEqual((await createHandbookStore(dir).get(c.id, c.token)).book, b);
    assert.ok(!(await readFile(join(dir, c.id + ".json"), "utf8")).includes(c.token));
    await assert.rejects(s.get(c.id, "x".repeat(43)), e => e.status === 401);
    await assert.rejects(s.get("../../secret", c.token), e => e.status === 401);
    const updates = await Promise.allSettled([s.update(c.id, c.token, { ...b, title: "A" }, 1), s.update(c.id, c.token, { ...b, title: "B" }, 1)]);
    assert.equal(updates.filter(r => r.status === "fulfilled").length, 1);
    assert.equal(updates.find(r => r.status === "rejected").reason.status, 409);
    assert.equal((await s.get(c.id, c.token)).book.title, "A");
  } finally { await rm(dir, { recursive: true, force: true }); }
});
test("handbook store validates body and enforces room quota", async () => {
  const dir = await mkdtemp(join(tmpdir(), "handbook-test-"));
  try { const s = createHandbookStore(dir, { maxRooms: 1 }); await assert.rejects(s.create({}), e => e.status === 400); await s.create(book()); await assert.rejects(s.create(book()), e => e.status === 503); } finally { await rm(dir, { recursive: true, force: true }); }
});
test("handbook HTTP API returns an explicit disabled state and never an empty shared ledger", async () => {
  const s = createApp({ env: {} }); await new Promise(resolve => s.listen(0, "127.0.0.1", resolve));
  try { const r = await fetch(`http://127.0.0.1:${s.address().port}/v1/handbooks`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ book: book() }) }); assert.equal(r.status, 503); } finally { await new Promise(resolve => s.close(resolve)); }
});

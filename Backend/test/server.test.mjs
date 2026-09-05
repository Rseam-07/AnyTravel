import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, symlink, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../src/server.mjs";
import { BoundedCache } from "../src/lib/bounded-cache.mjs";

test("public app serves Web and truthful health together, never repository secrets", async () => {
  const directory = await mkdtemp(join(tmpdir(), "anytravel-http-test-"));
  const webRoot = join(directory, "web"); await mkdir(webRoot);
  await writeFile(join(webRoot, "index.html"), "<!doctype html><title>AnyTravel</title>");
  await writeFile(join(directory, "secret.json"), '{"private":"do-not-serve"}');
  await symlink(join(directory, "secret.json"), join(webRoot, "outside.json"));
  const server = createApp({ webRoot, env: { ROLLINGGO_API_KEY: "test-only-private-value", CORS_ALLOW_ORIGINS: "https://allowed.example" } });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const health = await (await fetch(base + "/health")).json();
    assert.equal(health.service, "anytravel-companion");
    assert.equal(health.rollinggo, "configured");
    assert.equal(health.assistant, "disabled");
    assert.equal(health.fliggyFlights, "public");
    assert(!JSON.stringify(health).includes("test-only-private-value"));
    const page = await fetch(base + "/");
    assert.match(page.headers.get("content-type"), /text\/html/);
    assert.match(await page.text(), /AnyTravel/);
    for (const path of ["/.env", "/outside.json", "/missing.js", "/v1/missing"]) assert.equal((await fetch(base + path)).status, 404);
    assert.equal((await fetch(base + "/health", { headers: { Origin: "https://untrusted.example" } })).headers.get("access-control-allow-origin"), null);
    assert.equal((await fetch(base + "/health", { headers: { Origin: "https://allowed.example" } })).headers.get("access-control-allow-origin"), "https://allowed.example");
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
});

test("price cache expires stale entries and stays within a fixed memory count", () => {
  let now = 10;
  const cache = new BoundedCache(2, () => now);
  cache.set("a", { value: 1, expiresAt: 20 });
  cache.set("b", { value: 2, expiresAt: 30 });
  cache.set("c", { value: 3, expiresAt: 40 });
  assert.equal(cache.size, 2); assert.equal(cache.get("a"), undefined);
  now = 31;
  assert.equal(cache.get("b"), undefined);
  assert.equal(cache.get("c").value, 3);
});

import { randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, readdir, rename, writeFile, unlink } from "node:fs/promises";
import { join } from "node:path";

export class HandbookError extends Error { constructor(status, message) { super(message); this.status = status; } }
const hash = token => createHash("sha256").update(token).digest();
// One Node process owns this directory; atomic rename protects readers and restarts.
export function createHandbookStore(directory, { maxRooms = 250 } = {}) {
  let tail = Promise.resolve();
  const serial = task => { const next = tail.then(task); tail = next.catch(() => {}); return next; };
  function checkBook(book) {
    if (!book || book.version !== 1 || typeof book.title !== "string" || typeof book.id !== "string" || !["days", "places", "tickets", "todos", "documents", "flights", "rentals", "stays"].every(k => Array.isArray(book[k])) || !book.ledger || !Array.isArray(book.ledger.bills) || !Array.isArray(book.ledger.travelers)) throw new HandbookError(400, "invalid_handbook");
    if (Buffer.byteLength(JSON.stringify(book)) > 32 * 1024 * 1024) throw new HandbookError(413, "handbook_too_large");
  }
  async function write(id, record) {
    const dest = join(directory, `${id}.json`), temp = `${dest}.${randomBytes(6).toString("hex")}.tmp`;
    try { await writeFile(temp, JSON.stringify(record), { mode: 0o600, flag: "wx" }); await rename(temp, dest); } finally { await unlink(temp).catch(() => {}); }
  }
  async function read(id, token) {
    if (!/^[\w-]{16,64}$/.test(id) || !/^[\w-]{40,64}$/.test(token || "")) throw new HandbookError(401, "invalid_share_code");
    let data; try { data = JSON.parse(await readFile(join(directory, `${id}.json`), "utf8")); } catch (e) { if (e.code === "ENOENT") throw new HandbookError(404, "handbook_not_found"); throw e; }
    if (!timingSafeEqual(hash(token), Buffer.from(data.tokenHash, "hex"))) throw new HandbookError(401, "invalid_share_code");
    return data;
  }
  return {
    create: book => serial(async () => {
      checkBook(book); await mkdir(directory, { recursive: true, mode: 0o700 });
      if ((await readdir(directory)).filter(f => f.endsWith(".json")).length >= maxRooms) throw new HandbookError(503, "handbook_storage_full");
      const id = randomBytes(18).toString("base64url"), token = randomBytes(32).toString("base64url");
      await write(id, { revision: 1, tokenHash: hash(token).toString("hex"), book, updatedAt: new Date().toISOString() }); return { id, token, revision: 1 };
    }),
    async get(id, token) { const { revision, book, updatedAt } = await read(id, token); return { revision, book, updatedAt }; },
    update: (id, token, book, revision) => serial(async () => {
      const old = await read(id, token); if (!Number.isSafeInteger(revision) || revision !== old.revision) throw new HandbookError(409, "handbook_conflict"); checkBook(book);
      const next = { ...old, revision: old.revision + 1, book, updatedAt: new Date().toISOString() }; await write(id, next); return { revision: next.revision, updatedAt: next.updatedAt };
    })
  };
}

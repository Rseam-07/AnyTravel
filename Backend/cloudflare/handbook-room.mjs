import { DurableObject } from "cloudflare:workers";
import { randomBytes, createHash, timingSafeEqual } from "node:crypto";

const digest = token => createHash("sha256").update(token).digest();
const fail = (status, error) => Response.json({ error }, { status });
export class HandbookRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec("CREATE TABLE IF NOT EXISTS books (id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, revision INTEGER NOT NULL, updated_at TEXT NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS chunks (book_id TEXT NOT NULL, sequence INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(book_id, sequence))");
  }
  async fetch(request) {
    const id = new URL(request.url).pathname.split("/")[3];
    const token = (request.headers.get("authorization") || "").replace(/^Bearer /, "");
    if (request.method !== "GET" && request.method !== "POST") return fail(405, "method_not_allowed");
    let body;
    if (request.method === "POST") {
      // Decode the body before the synchronous transaction; every revision
      // check happens inside it so simultaneous uploads cannot lose updates.
      const { readJSON } = await import("./worker.mjs");
      try { body = await readJSON(request, 34 * 1024 * 1024); } catch (e) { return fail(e.status || 400, e.message); }
    }
    if (!id && request.method !== "POST") return fail(405, "method_not_allowed");
    const book = body?.book;
    if (request.method === "POST" && (!book || book.version !== 1 || typeof book.title !== "string" || typeof book.id !== "string" ||
      !["days", "places", "tickets", "todos", "documents", "flights", "rentals", "stays"].every(k => Array.isArray(book[k])) ||
      !Array.isArray(book.ledger?.bills) || !Array.isArray(book.ledger?.travelers))) return fail(400, "invalid_handbook");
    const text = book ? JSON.stringify(book) : "";
    if (new TextEncoder().encode(text).byteLength > 32 * 1024 * 1024) return fail(413, "handbook_too_large");
    return this.ctx.storage.transactionSync(() => {
      let old;
      if (id) {
        if (!/^[\w-]{16,64}$/.test(id) || !/^[\w-]{40,64}$/.test(token)) return fail(401, "invalid_share_code");
        old = this.sql.exec("SELECT * FROM books WHERE id = ?", id).toArray()[0];
        if (!old) return fail(404, "handbook_not_found");
        if (!timingSafeEqual(digest(token), Buffer.from(old.token_hash, "hex"))) return fail(401, "invalid_share_code");
        if (request.method === "GET") {
          const data = this.sql.exec("SELECT body FROM chunks WHERE book_id = ? ORDER BY sequence", id).toArray().map(row => row.body).join("");
          return Response.json({ book: JSON.parse(data), revision: old.revision, updatedAt: old.updated_at });
        }
        if (!Number.isSafeInteger(body.revision) || body.revision !== old.revision) return fail(409, "handbook_conflict");
      } else if (this.sql.exec("SELECT COUNT(*) AS count FROM books").one().count >= 100) return fail(503, "handbook_storage_full");
      const roomID = id || randomBytes(18).toString("base64url");
      const newToken = id ? token : randomBytes(32).toString("base64url");
      const revision = (old?.revision || 0) + 1, updatedAt = new Date().toISOString();
      this.sql.exec("INSERT OR REPLACE INTO books (id, token_hash, revision, updated_at) VALUES (?, ?, ?, ?)", roomID, digest(newToken).toString("hex"), revision, updatedAt);
      this.sql.exec("DELETE FROM chunks WHERE book_id = ?", roomID);
      // SQL values have a size limit. Small chunks also permit complete PDF
      // backups to travel with the book without needing a separate R2 account.
      for (let i = 0; i < text.length; i += 16000) this.sql.exec("INSERT INTO chunks (book_id, sequence, body) VALUES (?, ?, ?)", roomID, i, text.slice(i, i + 16000));
      return Response.json(id ? { revision, updatedAt } : { id: roomID, token: newToken, revision }, { status: id ? 200 : 201 });
    });
  }
}

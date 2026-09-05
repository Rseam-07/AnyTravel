export class BoundedCache {
  #entries = new Map();
  constructor(maxEntries = 200, now = Date.now) { this.maxEntries = maxEntries; this.now = now; }
  get(key) {
    const entry = this.#entries.get(key);
    if (entry && entry.expiresAt > this.now()) return entry;
    this.#entries.delete(key);
    return undefined;
  }
  set(key, entry) {
    for (const [existing, value] of this.#entries) if (value.expiresAt <= this.now()) this.#entries.delete(existing);
    this.#entries.delete(key);
    this.#entries.set(key, entry);
    while (this.#entries.size > this.maxEntries) this.#entries.delete(this.#entries.keys().next().value);
  }
  get size() { return this.#entries.size; }
}

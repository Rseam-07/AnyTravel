/** Public routing only. Provider credentials never belong in this file. */
export function normalizeServiceURL(value: string): string | null {
  try {
    const url = new URL(value.trim());
    const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (url.protocol !== "https:" && !(local && url.protocol === "http:")) return null;
    if (url.username || url.password || url.search || url.hash) return null;
    url.pathname = url.pathname.replace(/\/+$/, "") + "/";
    return url.href;
  } catch { return null; }
}

export function resolveServiceURL(override: string, preset: string, origin: string): string {
  return normalizeServiceURL(override) ?? normalizeServiceURL(preset) ?? normalizeServiceURL(origin) ?? "";
}

export function isLegacyLocalService(value: unknown): boolean {
  return typeof value === "string" && /^http:\/\/(?:127\.0\.0\.1|localhost):8787\/?$/.test(value);
}

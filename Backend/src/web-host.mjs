import { readFile, realpath, stat } from "node:fs/promises";
import { resolve, relative, extname, sep } from "node:path";

const contentTypes = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json", ".svg": "image/svg+xml", ".png": "image/png",
  ".ico": "image/x-icon", ".woff2": "font/woff2", ".jpg": "image/jpeg" };

/** Only the built Web directory is public. Never serve repository files or symlinks escaping it. */
export async function serveWeb(request, response, webRoot) {
  if (!["GET", "HEAD"].includes(request.method)) return false;
  let path;
  try { path = decodeURIComponent(new URL(request.url, "http://localhost").pathname); } catch { return false; }
  if (path.startsWith("/v1/") || path === "/health" || path.includes("\0") || path.includes("\\") ||
      path.split("/").some(part => part.startsWith("."))) return false;
  let root;
  try { root = await realpath(webRoot); } catch { return false; }
  let candidate = resolve(root, "." + path);
  if (path.endsWith("/")) candidate = resolve(candidate, "index.html");
  try {
    candidate = await realpath(candidate);
  } catch {
    if (extname(path)) return false;
    candidate = resolve(root, "index.html");
    try { candidate = await realpath(candidate); } catch { return false; }
  }
  const rel = relative(root, candidate);
  if (rel.startsWith(".." + sep) || rel === ".." || rel.startsWith(sep)) return false;
  const type = contentTypes[extname(candidate)];
  if (!type) return false;
  try {
    const info = await stat(candidate);
    if (!info.isFile()) return false;
    const contents = request.method === "HEAD" ? undefined : await readFile(candidate);
    response.setHeader("content-type", type);
    response.setHeader("cache-control", path.startsWith("/assets/") ? "public, max-age=31536000, immutable" : "no-cache");
    response.setHeader("content-length", info.size);
    response.writeHead(200);
    response.end(contents);
    return true;
  } catch { return false; }
}

const CACHE_NAME = "anytravel-shell-v0.8.4-planner-20260928-r3";
const APP_SHELL = ["./", "./logo.svg", "./manifest.webmanifest", "./icons/icon-192.png", "./icons/icon-512.png", ...["ledger.html", "ledger.js", "ledger.css", "brand.css", "bridge.js", "runtime-storage.js"].map(f => `./vendor/travel-plan-page/${f}`)];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL.slice(1));
    const indexResponse = await fetch("./");
    await cache.put("./", indexResponse.clone());
    // Include lazy map and handbook chunks before the first offline visit.
    const assets = await (await fetch("./offline-assets.json", { cache: "no-store" })).json();
    await cache.addAll(assets.filter(path => /^\.\/assets\/[\w.-]+\.(js|css)$/.test(path)));
  })());
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    // Keep one previous shell so already-open tabs can still load their lazy
    // chunks after a deployment. A normal navigation fetches the new document.
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key.startsWith("anytravel-shell-") && key !== CACHE_NAME).slice(0, -1).map((key) => caches.delete(key))))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          void caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          return response;
        })
        .catch(async () => (await caches.match(request)) || (await caches.match("./")))
    );
    return;
  }

  if (["script", "style", "font", "image"].includes(request.destination)) {
    event.respondWith(
      // Public static assets are identical for anonymous CORS and same-origin
      // requests. Precache requests can otherwise miss a Vary: Origin response.
      caches.match(request, { ignoreVary: true }).then((cached) => {
        const update = fetch(request).then((response) => {
          if (response.ok) void caches.open(CACHE_NAME).then((cache) => cache.put(request, response.clone()));
          return response;
        });
        if (cached) { event.waitUntil(update.catch(() => {})); return cached; }
        return update;
      })
    );
  }
});

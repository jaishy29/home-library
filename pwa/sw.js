// Keeps the app working offline. Bump VERSION when shipping changes.
const VERSION = "v1";
const SHELL = ["./", "index.html", "app.js", "vendor/zxing.min.js", "manifest.webmanifest", "icons/icon-180.png", "icons/icon-192.png", "icons/icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open("shell-" + VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith("shell-") && k !== "shell-" + VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET") return;
  // App files: network first so updates arrive, cache as fallback for offline.
  if (url.origin === location.origin) {
    e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open("shell-" + VERSION).then(c => c.put(e.request, copy)); return r; }).catch(() => caches.match(e.request).then(r => r || caches.match("index.html"))));
    return;
  }
  // Book covers and fonts: cache after first view so they show offline.
  if (/covers\.openlibrary\.org|archive\.org|books\.google|googleusercontent|fonts\.(googleapis|gstatic)\.com/.test(url.hostname)) {
    e.respondWith(caches.open("media").then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(r => { if (r.ok || r.type === "opaque") c.put(e.request, r.clone()); return r; }))));
  }
});

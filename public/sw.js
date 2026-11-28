// Service worker KDDF Market : site installable + mode hors ligne de base (page d'accueil + page « hors ligne »).
// Règles de sécurité :
//  - on ne met JAMAIS en cache les pages privées ni les API (paiements, téléchargements, comptes) ;
//  - la copie de la page d'accueil est TOUJOURS récupérée SANS cookies (credentials: "omit") : jamais de données d'un compte connecté dans le cache.
const VERSION = "kddf-v3";
const STATIC_CACHE = `${VERSION}-static`;
const PAGES_CACHE = `${VERSION}-pages`;
const OFFLINE_URL = "/offline";
const HOME_URL = "/";
const PRIVATE_PREFIXES = ["/api", "/auth", "/dashboard", "/library", "/admin", "/download", "/login", "/checkout", "/panier", "/litige", "/reset-password", "/mot-de-passe-oublie"];

// Copie anonyme d'une page publique (sans cookies) dans le cache des pages.
function cacheAnonymous(url) {
  return fetch(url, { credentials: "omit", redirect: "follow" })
    .then((res) => (res.ok && res.type === "basic" ? caches.open(PAGES_CACHE).then((c) => c.put(url, res)) : undefined))
    .catch(() => undefined);
}

self.addEventListener("install", (event) => {
  // Page d'accueil + page hors ligne mises en cache dès l'installation. Si le réseau est coupé à ce moment-là,
  // le service worker s'installe quand même (la copie sera refaite à la première visite en ligne).
  event.waitUntil(Promise.all([cacheAnonymous(HOME_URL), cacheAnonymous(OFFLINE_URL)]).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => !k.startsWith(VERSION)).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (PRIVATE_PREFIXES.some((p) => url.pathname === p || url.pathname.startsWith(p + "/"))) return;

  // Fichiers statiques : cache d'abord
  if (url.pathname.startsWith("/_next/static/") || url.pathname.startsWith("/icons/")) {
    event.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(STATIC_CACHE).then((c) => c.put(req, copy));
        return res;
      }))
    );
    return;
  }

  // Pages : réseau d'abord ; hors ligne -> page d'accueil en cache (pour "/") sinon page « hors ligne »
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (url.pathname === HOME_URL) event.waitUntil(cacheAnonymous(HOME_URL)); // garde la copie d'accueil à jour
          return res;
        })
        .catch(() =>
          caches.open(PAGES_CACHE).then((c) =>
            (url.pathname === HOME_URL ? c.match(HOME_URL) : Promise.resolve(undefined))
              .then((home) => home || c.match(OFFLINE_URL))
              .then((r) => r || Response.error())
          )
        )
    );
  }
});

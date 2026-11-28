/** @type {import('next').NextConfig} */

// En-têtes de sécurité appliqués à toutes les pages.
const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "SAMEORIGIN" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), payment=(self)" },
];

const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  // Les erreurs TypeScript, elles, font échouer le build (voulu) ; ESLint n'est pas installé : on ne le lance pas pendant le build.
  typescript: { ignoreBuildErrors: false },
  eslint: { ignoreDuringBuilds: true },
  images: {
    remotePatterns: [{ protocol: "https", hostname: "**.supabase.co" }],
  },
  // Les URLs de webhooks « /api/webhooks/<passerelle> » (pluriel, celles à saisir chez Fapshi, Flutterwave, NOWPayments)
  // sont des alias des routes /api/webhook/<passerelle> : les deux écritures fonctionnent.
  async rewrites() {
    return [
      { source: "/api/webhooks/nowpayments", destination: "/api/webhook/crypto" },
      { source: "/api/webhooks/:provider", destination: "/api/webhook/:provider" },
    ];
  },
  async headers() {
    return [
      { source: "/:path*", headers: securityHeaders },
      {
        // Le service worker ne doit jamais rester en cache : sinon une mise à jour du site n'arrive pas chez les utilisateurs.
        source: "/sw.js",
        headers: [
          { key: "Content-Type", value: "application/javascript; charset=utf-8" },
          { key: "Cache-Control", value: "no-cache, no-store, must-revalidate" },
          { key: "Service-Worker-Allowed", value: "/" },
        ],
      },
      {
        source: "/manifest.json",
        headers: [
          { key: "Content-Type", value: "application/manifest+json; charset=utf-8" },
          { key: "Cache-Control", value: "public, max-age=3600" },
        ],
      },
    ];
  },
};

export default nextConfig;

/** Adresse IP du visiteur derrière Vercel (Vercel écrase x-forwarded-for : la première valeur est celle du client). */
export function clientIpFrom(h: { get(name: string): string | null }): string | null {
  const raw = h.get("x-forwarded-for") ?? h.get("x-real-ip");
  const ip = raw ? raw.split(",")[0].trim() : "";
  return ip.length >= 3 && ip.length <= 64 ? ip : null;
}

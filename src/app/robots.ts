import type { MetadataRoute } from "next";
import { appUrl } from "@/lib/env";

// Les moteurs de recherche voient la boutique, jamais les espaces privés (compte, administration, paiement, téléchargements).
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: "*", allow: "/", disallow: ["/admin", "/dashboard", "/api/", "/download/", "/checkout", "/library", "/litige", "/reset-password", "/auth/"] }],
    sitemap: `${appUrl()}/sitemap.xml`,
  };
}

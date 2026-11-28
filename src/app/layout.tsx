import { LEGAL_LINKS } from "@/lib/legal";
import type { Metadata, Viewport } from "next";
import { Sora, DM_Sans } from "next/font/google";
import "./globals.css";
import Link from "next/link";
import Navbar from "@/components/Navbar";
import PwaRegister from "@/components/PwaRegister";
import WelcomePosters from "@/components/WelcomePosters";
import WelcomeGuideButton from "@/components/WelcomeGuideButton";
import InstallPrompt from "@/components/InstallPrompt";
import InstallButton from "@/components/InstallButton";
import { appUrl } from "@/lib/env";

const display = Sora({ subsets: ["latin"], variable: "--font-display" });
const body = DM_Sans({ subsets: ["latin"], variable: "--font-body" });

const name = process.env.NEXT_PUBLIC_APP_NAME || "KDDF Market";

// Adresse du site pour les liens absolus (partage, Open Graph). Jamais d'exception : une URL mal saisie ne doit pas casser le build.
function siteUrl(): URL {
  try {
    return new URL(appUrl());
  } catch {
    return new URL("http://localhost:3000");
  }
}

export const metadata: Metadata = {
  title: { default: `${name} — Vendez vos produits digitaux`, template: `%s · ${name}` },
  description: "Vendez et achetez des ebooks, formations, licences, coaching, services et produits physiques. Paiement Mobile Money (MTN, Orange), cartes bancaires et crypto.",
  metadataBase: siteUrl(),
  // --- PWA : application installable (logos dans /public/icons) ---
  applicationName: name,
  manifest: "/manifest.json",
  icons: {
    icon: [
      { url: "/icons/icon-32.png", sizes: "32x32", type: "image/png" },
      { url: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
    ],
    apple: [{ url: "/icons/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
  appleWebApp: { capable: true, title: name, statusBarStyle: "black-translucent" },
  formatDetection: { telephone: false },
  openGraph: {
    type: "website",
    siteName: name,
    locale: "fr_FR",
    images: [{ url: "/og.png", width: 1200, height: 630, alt: name }],
  },
};

// Mobile : largeur de l'appareil, zoom autorisé (accessibilité), prise en charge de l'encoche (viewport-fit=cover)
export const viewport: Viewport = {
  themeColor: "#0B0B10",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body className={`${display.variable} ${body.variable} font-sans min-h-screen`}>
        <Navbar />
        <PwaRegister />
        <InstallPrompt />
        <WelcomePosters />
        <main className="mx-auto w-full max-w-6xl px-4 pb-24 pt-6 sm:px-6">{children}</main>
        <footer className="space-y-4 border-t border-white/5 px-4 py-8 text-center text-xs text-zinc-500">
          <InstallButton />
          <p className="flex flex-wrap justify-center gap-x-4 gap-y-1">
            <Link href="/suivre-commande" className="underline hover:text-white">Suivre ma commande</Link>
            <Link href="/services" className="underline hover:text-white">Services pour vendeurs</Link>
            <Link href="/support" className="underline hover:text-white">Aide et support</Link>
            <WelcomeGuideButton />
          </p>
          <p className="flex flex-wrap justify-center gap-x-4 gap-y-1">
            {LEGAL_LINKS.map((l) => <Link key={l.href} href={l.href} className="underline hover:text-white">{l.label}</Link>)}
          </p>
          <p>© {new Date().getFullYear()} {name} — Paiements sécurisés</p>
        </footer>
      </body>
    </html>
  );
}

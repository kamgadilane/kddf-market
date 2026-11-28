import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import CountrySelector from "@/components/CountrySelector";
import CartLink from "@/components/CartLink";
import IpBeacon from "@/components/IpBeacon";
import MobileMenu, { type MobileMenuItem } from "@/components/MobileMenu";
import QuickSearch from "@/components/QuickSearch";
import NotificationBell from "@/components/NotificationBell";
import { searchItems } from "@/lib/siteMap";

export default async function Navbar() {
  const supabase = createClient();
  const { data } = await supabase.auth.getUser();
  const name = process.env.NEXT_PUBLIC_APP_NAME || "KDDF Market";

  // Le lien "Admin" n'apparaît que pour le compte administrateur (profiles.role = 'admin')
  let isAdmin = false;
  if (data.user) {
    const { data: profile } = await supabase.from("profiles").select("role").eq("id", data.user.id).maybeSingle();
    isAdmin = (profile as { role?: string } | null)?.role === "admin";
  }

  // Les options rangées dans le "classeur" (menu mobile)
  const items: MobileMenuItem[] = [{ href: "/grossistes", label: "Grossistes", icon: "📦" }];
  if (data.user) {
    if (isAdmin) items.push({ href: "/admin", label: "Admin", icon: "🛡️" });
    items.push({ href: "/library", label: "Mes achats", icon: "📚" });
    items.push({ href: "/securite", label: "Sécurité du compte", icon: "🔐" });
    items.push({ href: "/dashboard", label: "Espace créateur", icon: "📊", primary: true });
  } else {
    items.push({ href: "/login", label: "Connexion", icon: "🔑" });
    items.push({ href: "/login?mode=signup", label: "Vendre sur " + name, icon: "🚀", primary: true });
  }

  const searchable = searchItems(!!data.user, isAdmin);

  return (
    <header className="site-header sticky top-0 z-40 border-b border-white/5 bg-ink-950/70 backdrop-blur-xl">
      <nav className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <Link href="/" className="flex shrink-0 items-center gap-2 font-display text-lg font-bold tracking-tight">
          <Image src="/logo.png" alt={name} width={36} height={36} className="rounded-lg" priority /> <span className="hidden whitespace-nowrap sm:inline">{name}</span>
        </Link>

        {/* Ordinateur : tous les boutons alignés */}
        <div className="hidden min-w-0 items-center justify-end gap-2 text-sm lg:flex [&_a]:whitespace-nowrap [&_button]:whitespace-nowrap">
          <CountrySelector />
          <QuickSearch items={searchable} variant="desktop" />
          {data.user && <NotificationBell variant="desktop" />}
          <Link href="/grossistes" className="btn-ghost !px-3 !py-2">Grossistes</Link>
          <CartLink />
          {data.user ? (
            <>
              {isAdmin && <Link href="/admin" className="btn-ghost !px-3 !py-2">Admin</Link>}
              <Link href="/library" className="btn-ghost !px-3 !py-2">Mes achats</Link>
              <Link href="/securite" className="btn-ghost !px-3 !py-2" aria-label="Sécurité du compte" title="Sécurité du compte">🔐</Link>
              <Link href="/dashboard" className="btn-primary !px-3 !py-2">Espace créateur</Link>
              <form action="/auth/signout" method="post">
                <button className="btn-ghost !px-3 !py-2" aria-label="Se déconnecter">Quitter</button>
              </form>
            </>
          ) : (
            <>
              <Link href="/login" className="btn-ghost !px-3 !py-2">Connexion</Link>
              <Link href="/login?mode=signup" className="btn-primary !px-3 !py-2">Vendre</Link>
            </>
          )}
        </div>

        {/* Mobile / tablette : panier visible + un seul bouton "menu" qui ouvre le classeur */}
        <div className="flex items-center gap-2 lg:hidden">
          <QuickSearch items={searchable} variant="mobile" />
          {data.user && <NotificationBell variant="mobile" />}
          <CartLink />
          <MobileMenu items={items} signedIn={!!data.user}>
            <CountrySelector inline />
          </MobileMenu>
        </div>
      </nav>
      {data.user && <IpBeacon />}
    </header>
  );
}

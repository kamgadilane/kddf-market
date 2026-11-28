import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// Options d'un cookie telles que Supabase les fournit
type CookieOptions = {
  path?: string;
  maxAge?: number;
  domain?: string;
  secure?: boolean;
  httpOnly?: boolean;
  sameSite?: "lax" | "strict" | "none" | boolean;
  expires?: Date;
};

export function createClient() {
  const store = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (list: { name: string; value: string; options?: CookieOptions }[]) => {
          try {
            list.forEach(({ name, value, options }) => store.set(name, value, options));
          } catch {
            // appelé depuis un Server Component : le middleware rafraîchit la session
          }
        },
      },
    }
  );
}

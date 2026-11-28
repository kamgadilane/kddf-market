import { NextResponse } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";

// Page de retour des liens envoyés par email (confirmation d'inscription, mot de passe oublié) :
// ouvre la session de l'utilisateur, puis le redirige vers une page de NOTRE site uniquement.
//
// Deux formats de lien sont acceptés :
//  1. ?token_hash=…&type=… (modèles d'email de supabase/email-templates) : fonctionne dans N'IMPORTE quel
//     navigateur ou application mail, même si le lien est ouvert ailleurs que sur l'appareil d'inscription ;
//  2. ?code=… (ancien format PKCE) : ne fonctionne que dans le navigateur où l'inscription a été faite.
const OTP_TYPES: readonly EmailOtpType[] = ["signup", "invite", "magiclink", "recovery", "email_change", "email"];

function isOtpType(value: string | null): value is EmailOtpType {
  return value !== null && (OTP_TYPES as readonly string[]).includes(value);
}

export async function GET(req: Request): Promise<NextResponse> {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type");
  const next = url.searchParams.get("next") ?? "/dashboard";
  const safeNext = next.startsWith("/") && !next.startsWith("//") && !next.includes("\\") ? next : "/dashboard";
  // Un mot de passe oublié mène toujours à la page « nouveau mot de passe », quoi qu'il y ait dans « next ».
  const target = type === "recovery" ? "/reset-password" : safeNext;

  const supabase = createClient();

  if (tokenHash && isOtpType(type)) {
    const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (error) return NextResponse.redirect(new URL("/login?error=lien_invalide", url.origin));
    return NextResponse.redirect(new URL(target, url.origin));
  }

  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      // Lien expiré, déjà utilisé, ou ouvert dans un autre navigateur que celui de la demande
      return NextResponse.redirect(new URL("/login?error=lien_invalide", url.origin));
    }
  }
  return NextResponse.redirect(new URL(target, url.origin));
}

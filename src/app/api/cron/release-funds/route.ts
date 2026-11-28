// Tâche planifiée (Vercel Cron, 1 fois par jour — voir vercel.json). Elle fait deux choses :
//  1) rattrape les paiements dont le webhook n'est jamais arrivé (Fapshi ne renvoie pas les webhooks) ;
//  2) libère les fonds arrivés à échéance : "en attente" -> "disponible" ;
//  3) prévient par email les vendeurs dont un produit dort depuis 3 jours ;
//  4) renvoie les emails restés en file d'attente (Resend indisponible) et nettoie les anciennes données techniques.
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { syncBoostPayment, syncFapshiTransaction, syncProPayment } from "@/lib/fulfillment";
import { sendInactiveProductEmail } from "@/lib/email";
import { processOutbox } from "@/lib/mailer";
import { productUrl } from "@/lib/share";
import { asRows } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(req: Request): Promise<NextResponse> {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Non autorisé" }, { status: 401 });
  }

  const db = createAdminClient();
  const since = new Date(Date.now() - 26 * 3600 * 1000).toISOString(); // un lien Fapshi expire après 24 h
  const before = new Date(Date.now() - 60 * 1000).toISOString();

  const { data } = await db
    .from("transactions")
    .select("fapshi_trans_id")
    .in("status", ["pending", "failed"])
    .not("fapshi_trans_id", "is", null)
    .gte("created_at", since)
    .lte("created_at", before)
    .order("created_at", { ascending: true })
    .limit(25);

  const counts: Record<string, number> = {};
  for (const row of asRows<{ fapshi_trans_id: string }>(data)) {
    const r = await syncFapshiTransaction(row.fapshi_trans_id, { source: "cron", minAgeSeconds: 60 });
    counts[r] = (counts[r] ?? 0) + 1;
  }

  // Paiements de boost dont le webhook n'est pas arrivé
  const { data: boosts } = await db
    .from("product_boosts")
    .select("fapshi_trans_id")
    .in("status", ["pending", "failed"])
    .not("fapshi_trans_id", "is", null)
    .gte("created_at", since)
    .lte("created_at", before)
    .limit(25);
  for (const row of asRows<{ fapshi_trans_id: string }>(boosts)) {
    const r = await syncBoostPayment(row.fapshi_trans_id, { source: "cron", minAgeSeconds: 60 });
    counts[`boost_${r}`] = (counts[`boost_${r}`] ?? 0) + 1;
  }

  // Paiements d'abonnement Pro dont le webhook n'est pas arrivé
  const { data: pros } = await db
    .from("pro_subscriptions")
    .select("fapshi_trans_id")
    .in("status", ["pending", "failed"])
    .not("fapshi_trans_id", "is", null)
    .gte("created_at", since)
    .lte("created_at", before)
    .limit(25);
  for (const row of asRows<{ fapshi_trans_id: string }>(pros)) {
    const r = await syncProPayment(row.fapshi_trans_id, { source: "cron", minAgeSeconds: 60 });
    counts[`pro_${r}`] = (counts[`pro_${r}`] ?? 0) + 1;
  }

  const { data: released, error } = await db.rpc("release_due_funds", { p_user: null });
  if (error) console.error("[cron] libération des fonds :", error.message);

  // Email aux vendeurs dont un produit "dort" depuis 3 jours (0 vente, 0 partage, moins de 10 vues)
  let emailed = 0;
  const { data: sleeping } = await db.rpc("inactive_products_to_notify");
  for (const p of asRows<{ product_id: string; seller_id: string; title: string }>(sleeping)) {
    try {
      const { data: seller } = await db.auth.admin.getUserById(p.seller_id);
      const to = seller.user?.email;
      if (!to) continue;
      const r = await sendInactiveProductEmail({ to, productTitle: p.title, productUrl: productUrl(p.product_id) });
      // "skipped" (pas de clé Resend) ou "failed" : on ne marque rien, la relance sera retentée demain
      if (r === "sent" || r === "queued") {
        await db.from("products").update({ last_inactivity_email_at: new Date().toISOString() }).eq("id", p.product_id);
        emailed += 1;
      }
    } catch (e) {
      console.error("[cron] email d'inactivité non envoyé", e instanceof Error ? e.message : e);
    }
  }

  // Emails en file d'attente (réessais) puis nettoyage des journaux de plus de 30 jours (plan gratuit Supabase) :
  // fraud_logs fermés, IP, événements de paiement, compteurs anti-abus, emails envoyés/abandonnés (fonction SQL purge_old_logs)
  const outbox = await processOutbox(20);
  const purged = await db.rpc("purge_old_logs");
  if (purged.error) console.error("[cron] nettoyage des journaux :", purged.error.message);

  return NextResponse.json({
    checked: counts,
    released: typeof released === "number" ? released : 0,
    inactivityEmails: emailed,
    outbox,
    purged: purged.error ? null : purged.data,
  });
}

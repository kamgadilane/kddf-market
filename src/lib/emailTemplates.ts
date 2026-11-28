// Modèles d'emails KDDF Market (HTML + texte brut). Fonctions PURES : aucune dépendance serveur, faciles à tester.
// Chaque modèle renvoie { subject, html, text }. L'envoi est fait par lib/mailer.ts (Resend + file de réessai).
import { appName, appUrl } from "@/lib/env";
import { formatFcfa } from "@/lib/money";
import { renderTemplate } from "@/lib/emails/render";

export interface EmailMessage {
  subject: string;
  html: string;
  text: string;
}

export function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** Cadre commun : fond sombre, carte centrée, texte d'aperçu (preheader) masqué. */
function shell(title: string, inner: string, preheader: string): string {
  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark light"><title>${esc(title)}</title></head>
<body style="margin:0;padding:0;background:#0B0B10">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent">${esc(preheader)}</div>
  <div style="background:#0B0B10;padding:24px 12px;font-family:Arial,Helvetica,sans-serif;color:#E5E7EB;line-height:1.55">
    <div style="max-width:520px;margin:auto;background:#111118;border:1px solid #22222F;border-radius:16px;padding:28px">
      <h1 style="margin:0 0 14px;font-size:22px;color:#ffffff">${title}</h1>
      ${inner}
      <p style="font-size:12px;color:#9CA3AF;margin:28px 0 0">${esc(appName())} · <a href="${esc(appUrl())}" style="color:#9CA3AF">${esc(appUrl().replace(/^https?:\/\//, ""))}</a></p>
    </div>
  </div>
</body></html>`;
}

function button(href: string, label: string): string {
  return `<p style="margin:24px 0"><a href="${esc(href)}" style="background:#6366F1;color:#ffffff;padding:13px 22px;border-radius:10px;text-decoration:none;font-weight:bold;display:inline-block">${esc(label)}</a></p>
<p style="font-size:12px;color:#9CA3AF;word-break:break-all;margin:0">Si le bouton ne marche pas, copiez ce lien : ${esc(href)}</p>`;
}

// ---------------------------------------------------------------------------------------------
// 1. Acheteur : confirmation d'achat
// ---------------------------------------------------------------------------------------------
export function purchaseEmail(a: {
  name: string | null;
  productTitle: string;
  portalUrl: string;
  licenseKey: string | null;
  isPhysical: boolean;
  totalFcfa: number;
}): EmailMessage {
  const intro = a.isPhysical
    ? "Le vendeur prépare votre commande. Suivez son avancement (confirmée, expédiée, livrée) depuis le lien ci-dessous."
    : "Votre achat est prêt : vous pouvez le télécharger dès maintenant.";
  const license = a.licenseKey
    ? `<p style="margin:16px 0;padding:12px 16px;background:#181822;border-radius:10px;font-family:monospace;color:#34D399">Clé de licence : ${esc(a.licenseKey)}</p>`
    : "";
  const buttonLabel = a.isPhysical ? "Suivre ma commande" : "Accéder à mon téléchargement";
  const html = renderTemplate("recu_paiement", {
    name: a.name ?? "",
    product_title: a.productTitle,
    total: formatFcfa(a.totalFcfa),
    intro,
    license_block: license,
    portal_url: a.portalUrl,
    button_label: buttonLabel,
  });
  const text = [
    `Bonjour ${a.name ?? ""},`,
    `Votre paiement de ${formatFcfa(a.totalFcfa)} pour « ${a.productTitle} » est confirmé.`,
    intro,
    a.licenseKey ? `Clé de licence : ${a.licenseKey}` : "",
    `${a.isPhysical ? "Suivre ma commande" : "Accéder à mon téléchargement"} : ${a.portalUrl}`,
    "Le lien est personnel : ne le partagez pas.",
    appName(),
  ].filter(Boolean).join("\n\n");
  return { subject: `Votre achat : ${a.productTitle}`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 2. Vendeur : commande de produit physique à préparer (en ligne ou cash)
// ---------------------------------------------------------------------------------------------
export function sellerNewOrderEmail(a: {
  productTitle: string;
  quantity: number;
  deliveryLabel: string;
  buyerName: string | null;
  buyerPhone: string | null;
  address: string | null;
  dashboardUrl: string;
  cash?: boolean;
}): EmailMessage {
  const cashHtml = a.cash
    ? "<p><strong>Paiement en CASH à la livraison</strong> : le client paie quand il reçoit le produit. La commission KDDF en vigueur sera prélevée sur votre prochain retrait.</p>"
    : "";
  const html = shell(
    "Nouvelle commande à préparer 📦",
    `<p><strong>${esc(a.productTitle)}</strong> × ${a.quantity}</p>
     <p>Livraison : ${esc(a.deliveryLabel)}</p>
     <p>Client : ${esc(a.buyerName ?? "—")} · ${esc(a.buyerPhone ?? "—")}</p>
     ${a.address ? `<p>Adresse : ${esc(a.address)}</p>` : ""}
     ${cashHtml}
     ${button(a.dashboardUrl, "Voir la commande")}`,
    `Nouvelle commande : ${a.productTitle} × ${a.quantity}`
  );
  const text = [
    `Nouvelle commande : ${a.productTitle} × ${a.quantity}`,
    `Livraison : ${a.deliveryLabel}`,
    `Client : ${a.buyerName ?? "—"} · ${a.buyerPhone ?? "—"}`,
    a.address ? `Adresse : ${a.address}` : "",
    a.cash ? "Paiement en CASH à la livraison. La commission KDDF en vigueur sera prélevée sur votre prochain retrait." : "",
    `Voir la commande : ${a.dashboardUrl}`,
  ].filter(Boolean).join("\n\n");
  return { subject: `Nouvelle commande : ${a.productTitle}`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 3. Vendeur : relance d'un produit qui dort
// ---------------------------------------------------------------------------------------------
export function inactiveProductEmail(a: { productTitle: string; productUrl: string }): EmailMessage {
  const html = shell(
    "Ton produit dort 😴",
    `<p>Ton produit <strong>${esc(a.productTitle)}</strong> dort sur ${esc(appName())}.</p>
     <p>Partage ton lien sur WhatsApp / TikTok pour avoir tes premières ventes.</p>
     ${button(a.productUrl, "Ouvrir mon produit")}`,
    `Ton produit « ${a.productTitle} » n'a ni vente ni partage depuis 3 jours`
  );
  const text = `Ton produit « ${a.productTitle} » dort sur ${appName()}.\n\nPartage ton lien sur WhatsApp / TikTok pour avoir tes premières ventes :\n${a.productUrl}`;
  return { subject: `Ton produit « ${a.productTitle} » dort sur ${appName()}`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 4. Vendeur : nouvelle vente (module 12)
// ---------------------------------------------------------------------------------------------
export function sellerSaleEmail(a: { productTitle: string; totalFcfa: number; sellerShareFcfa: number }): EmailMessage {
  const html = renderTemplate("notification_vendeur", {
    product_title: a.productTitle,
    total: formatFcfa(a.totalFcfa),
    seller_share: formatFcfa(a.sellerShareFcfa),
    orders_url: `${appUrl()}/dashboard/orders`,
  });
  const text = `Nouvelle vente ! ${a.productTitle} - ${formatFcfa(a.totalFcfa)}\nVotre part : ${formatFcfa(a.sellerShareFcfa)} (en attente de libération).\n${appUrl()}/dashboard/orders`;
  return { subject: `Nouvelle vente ! ${a.productTitle} - ${formatFcfa(a.totalFcfa)}`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 5. Affilié : commission gagnée (module 12)
// ---------------------------------------------------------------------------------------------
export function affiliateCommissionEmail(a: { productTitle: string; feeFcfa: number }): EmailMessage {
  const html = renderTemplate("notification_affilie", {
    product_title: a.productTitle,
    commission: formatFcfa(a.feeFcfa),
    wallet_url: `${appUrl()}/dashboard/wallet`,
  });
  const text = `Tu as gagné ${formatFcfa(a.feeFcfa)} de commission.\nVente de « ${a.productTitle} » grâce à ton lien.\n${appUrl()}/dashboard/wallet`;
  return { subject: `Tu as gagné ${formatFcfa(a.feeFcfa)} de commission`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 6. Vendeurs : changement de commission de la plateforme
// ---------------------------------------------------------------------------------------------
export function commissionChangeEmail(message: string): EmailMessage {
  const html = shell(
    `Changement de commission sur ${esc(appName())}`,
    `<p>Bonjour,</p><p>${esc(message)}</p>${button(`${appUrl()}/dashboard`, "Ouvrir mon tableau de bord")}`,
    "La commission de la plateforme a changé"
  );
  const text = `Bonjour,\n\n${message}\n\n${appUrl()}/dashboard`;
  return { subject: `Changement de commission sur ${appName()}`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 7. Propriétaire : nouveau message de support
// ---------------------------------------------------------------------------------------------
export function supportAlertEmail(m: { name: string; email: string; categoryLabel: string; message: string; pageUrl: string | null; imageCount: number }): EmailMessage {
  const html = shell(
    "Nouveau message de support",
    `<p><strong>${esc(m.name)}</strong> (${esc(m.email)}) · ${esc(m.categoryLabel)}</p>
     <p style="white-space:pre-wrap;background:#181822;border-radius:10px;padding:12px 16px">${esc(m.message)}</p>
     ${m.pageUrl ? `<p>Page concernée : ${esc(m.pageUrl)}</p>` : ""}
     <p>${m.imageCount} capture(s) jointe(s).</p>
     ${button(`${appUrl()}/admin/support`, "Ouvrir dans l'admin")}`,
    `${m.name} : ${m.message.slice(0, 80)}`
  );
  const text = `${m.name} (${m.email}) · ${m.categoryLabel}\n\n${m.message}\n\n${m.pageUrl ? `Page : ${m.pageUrl}\n` : ""}${m.imageCount} capture(s) jointe(s).\n${appUrl()}/admin/support`;
  return { subject: `[Support] ${m.categoryLabel} · ${m.name}`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 7 bis. Alerte administrateur : une page a planté chez un visiteur (avec la notice « que faire »)
// ---------------------------------------------------------------------------------------------
export function adminErrorAlertEmail(m: { message: string; url: string | null; digest: string | null; title: string; cause: string; steps: string[]; urgencyLabel: string }): EmailMessage {
  const list = m.steps.map((s) => `<li style="margin:6px 0">${esc(s)}</li>`).join("");
  const html = shell(
    "Une erreur est survenue sur le site",
    `<p style="margin:0 0 6px"><strong>${esc(m.title)}</strong> · ${esc(m.urgencyLabel)}</p>
     <p style="white-space:pre-wrap;background:#181822;border-radius:10px;padding:12px 16px;font-family:monospace;font-size:13px">${esc(m.message.slice(0, 300))}</p>
     <p style="margin:6px 0">${m.url ? `Page : ${esc(m.url)}<br>` : ""}${m.digest ? `Référence : ${esc(m.digest)}` : ""}</p>
     <p style="margin:16px 0 4px"><strong>Cause probable</strong><br>${esc(m.cause)}</p>
     <p style="margin:16px 0 4px"><strong>Quoi faire</strong></p>
     <ol style="margin:0;padding-left:20px">${list}</ol>
     ${button(`${appUrl()}/admin/erreurs`, "Ouvrir le journal des erreurs")}
     <p style="font-size:12px;color:#9CA3AF">Vous recevez au plus un email de ce type toutes les 30 minutes.</p>`,
    `${m.title} : ${m.message.slice(0, 80)}`
  );
  const text = `${m.title} (${m.urgencyLabel})\n\n${m.message.slice(0, 300)}\n${m.url ? `Page : ${m.url}\n` : ""}${m.digest ? `Référence : ${m.digest}\n` : ""}\nCause probable : ${m.cause}\n\nQuoi faire :\n${m.steps.map((s, i) => `${i + 1}. ${s}`).join("\n")}\n\nJournal : ${appUrl()}/admin/erreurs`;
  return { subject: `[Alerte] ${m.title}`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 8. Nouveau compte : email de bienvenue (confirmation d'inscription)
// ---------------------------------------------------------------------------------------------
export function welcomeEmail(a: { name: string | null }): EmailMessage {
  const html = renderTemplate("confirmation_inscription", { name: a.name ?? "", dashboard_url: `${appUrl()}/dashboard` });
  const text = `Bonjour ${a.name ?? ""},\n\nBienvenue sur ${appName()} ! Votre compte est créé.\nOuvrir mon espace : ${appUrl()}/dashboard\n\nGarantie KDDF Market : Si le produit n'est pas conforme, retour sous 48h, remboursement sous 7 jours. Valable UNIQUEMENT si le paiement est fait sur KDDF Market.`;
  return { subject: `Bienvenue sur ${appName()} !`, html, text };
}

// ---------------------------------------------------------------------------------------------
// 9. Litige : ouverture (acheteur + vendeur prévenus) et décision de l'admin
// ---------------------------------------------------------------------------------------------
export function disputeEmail(a: { recipientName: string | null; headline: string; productTitle: string; orderId: string; message: string }): EmailMessage {
  const url = `${appUrl()}/litige/${a.orderId}`;
  const html = renderTemplate("litige", {
    recipient_name: a.recipientName ?? "",
    headline: a.headline,
    product_title: a.productTitle,
    order_ref: a.orderId.slice(0, 8).toUpperCase(),
    message: a.message,
    dispute_url: url,
  });
  const text = `${a.headline}\n\nCommande « ${a.productTitle} » (réf. ${a.orderId.slice(0, 8).toUpperCase()})\n\n${a.message}\n\nVoir le litige : ${url}`;
  return { subject: `${a.headline} : ${a.productTitle}`, html, text };
}

// Génère les affiches publicitaires de KDDF Market (PNG) : 8 affiches en 2 formats.
//   feed/  1080 x 1350 : publications Facebook, Instagram, WhatsApp, LinkedIn
//   story/ 1080 x 1920 : statuts WhatsApp, stories Instagram / Facebook, TikTok
// Utilisation (avec Node 18+ et Playwright installés) :
//   SITE_URL="mon-site.vercel.app" WHATSAPP="+237689644382" node marketing/generer-affiches.mjs
// Les images sortent dans marketing/affiches/feed et marketing/affiches/story.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const here = path.dirname(fileURLToPath(import.meta.url));
const SITE_URL = (process.env.SITE_URL || "kddf-market.vercel.app").replace(/^https?:\/\//, "").replace(/\/$/, "");
const WHATSAPP = process.env.WHATSAPP || "+237 689 644 382";
const logo = "data:image/png;base64," + fs.readFileSync(path.join(here, "..", "public", "logo.png")).toString("base64");

const POSTERS = [
  { id: "01-lancement", emoji: "🛍️", from: "#1E1B4B", to: "#4338CA", accent: "#A5B4FC", kicker: "Nouveau au Cameroun",
    title: "Achetez. Vendez. <em>Gagnez.</em>", text: "KDDF Market, la marketplace des produits digitaux et physiques, faite pour vous.",
    chips: ["Guides & formations", "Produits physiques", "Paiement Mobile Money"], cta: "Découvrir maintenant" },
  { id: "02-vendeurs", emoji: "🚀", from: "#312E81", to: "#6D28D9", accent: "#C4B5FD", kicker: "Pour les vendeurs",
    title: "Ouvrez votre boutique en <em>2 minutes</em>", text: "Publiez vos produits, recevez vos paiements et retirez vos gains en Mobile Money.",
    chips: ["Démarrage gratuit", "Retrait Mobile Money", "Statistiques en direct"], cta: "Ouvrir ma boutique" },
  { id: "03-acheteurs", emoji: "📲", from: "#064E3B", to: "#0F766E", accent: "#6EE7B7", kicker: "Pour les acheteurs",
    title: "Payez avec votre <em>téléphone</em>, recevez en 1 clic", text: "Choisissez, payez en MTN MoMo ou Orange Money, téléchargez tout de suite.",
    chips: ["Livraison instantanée du digital", "Suivi de colis", "Reçu par email"], cta: "Voir les produits" },
  { id: "04-paiements", emoji: "💳", from: "#0F172A", to: "#1E40AF", accent: "#93C5FD", kicker: "Tous les moyens de paiement",
    title: "Un seul paiement, <em>tous</em> vos moyens", text: "Payez comme vous voulez, en FCFA, en euro ou en dollar.",
    chips: ["MTN MoMo · Orange Money", "Visa · Mastercard", "PayPal · Crypto"], cta: "Payer en toute simplicité" },
  { id: "05-affiliation", emoji: "🤝", from: "#134E4A", to: "#0E7490", accent: "#67E8F9", kicker: "Affiliation",
    title: "Recommandez, <em>gagnez</em> jusqu'à 50&nbsp;%", text: "Partagez votre lien : vous touchez une commission à chaque vente réalisée grâce à vous.",
    chips: ["Votre lien personnel", "Gains suivis en direct", "Retrait Mobile Money"], cta: "Devenir affilié" },
  { id: "06-confiance", emoji: "🛡️", from: "#1E3A8A", to: "#1D4ED8", accent: "#BFDBFE", kicker: "Confiance",
    title: "Vendeurs <em>vérifiés</em>. Achats garantis.", text: "Chaque vendeur est contrôlé par carte d'identité avant de publier. Retour sous 48 h si le produit n'est pas conforme.",
    chips: ["Identité contrôlée", "Garantie KDDF Market", "Compte protégé (2FA)"], cta: "Acheter en confiance" },
  { id: "07-application", emoji: "📱", from: "#3B0764", to: "#7E22CE", accent: "#E9D5FF", kicker: "Application gratuite",
    title: "Installez KDDF Market sur votre <em>écran d'accueil</em>", text: "Sur Android, iPhone ou ordinateur : une vraie application, sans magasin d'applications.",
    chips: ["Android : bouton « Installer »", "iPhone : Partager > Écran d'accueil", "PC : icône d'installation du navigateur"], cta: "Installer l'application" },
  { id: "08-service-client", emoji: "💬", from: "#0F172A", to: "#334155", accent: "#5EEAD4", kicker: "Service client",
    title: "Une question ? <em>On vous répond</em>", text: "Paiement, commande, compte : écrivez-nous avec une capture d'écran, nous vous aidons.",
    chips: [`WhatsApp : ${WHATSAPP}`, "Page « Aide et support »", "Réponse dès que possible"], cta: "Nous contacter" },
];

function html(p, w, h) {
  const story = h > 1500;
  const s = story ? 1.15 : 1;
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><style>
*{box-sizing:border-box;margin:0}
body{width:${w}px;height:${h}px;font-family:'Poppins','Inter',sans-serif;color:#fff;overflow:hidden;
 background:radial-gradient(circle at 15% 12%,${p.accent}40,transparent 42%),radial-gradient(circle at 90% 88%,${p.accent}30,transparent 48%),linear-gradient(160deg,${p.from},${p.to});position:relative}
.ring{position:absolute;border-radius:50%;border:2px solid ${p.accent}33}
.r1{width:760px;height:760px;right:-260px;top:${story ? 300 : 180}px}.r2{width:520px;height:520px;left:-200px;bottom:${story ? 420 : 260}px}
.wrap{position:relative;height:100%;padding:${story ? 110 : 64}px 80px ${story ? 130 : 70}px;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:20px;font-weight:700;font-size:40px;letter-spacing:-.5px}
.brand img{width:76px;height:76px;border-radius:20px}
.main{flex:1;display:flex;flex-direction:column;justify-content:center;gap:${story ? 34 : 22}px;min-height:0}
.emoji{width:${story ? 160 : 112}px;height:${story ? 160 : 112}px;border-radius:36px;display:flex;align-items:center;justify-content:center;font-size:${story ? 94 : 64}px;font-family:'Noto Color Emoji';
 background:${p.accent}26;border:2px solid ${p.accent}77;box-shadow:0 0 90px ${p.accent}66}
.kicker{font-size:${story ? 30 : 26}px;font-weight:700;letter-spacing:.22em;text-transform:uppercase;color:${p.accent}}
h1{font-size:${story ? 96 : 76}px;line-height:1.05;font-weight:800;letter-spacing:-2px}
h1 em{font-style:normal;color:${p.accent}}
.text{font-size:${story ? 38 : 32}px;line-height:1.38;color:#ffffffdd;max-width:900px}
.chips{display:flex;flex-direction:column;gap:${story ? 18 : 12}px;margin-top:4px}
.chip{display:flex;align-items:center;gap:18px;font-size:${story ? 36 : 30}px;font-weight:600;background:#00000040;border:1px solid #ffffff22;border-radius:24px;padding:${story ? 20 : 15}px 28px}
.chip i{width:18px;height:18px;border-radius:50%;background:${p.accent};flex:none;box-shadow:0 0 18px ${p.accent}}
.foot{flex:none;display:flex;align-items:center;justify-content:space-between;gap:24px;background:${p.accent};color:#0B0B10;border-radius:34px;padding:${story ? 28 : 22}px 36px}
.cta{font-size:32px;font-weight:800;white-space:nowrap}.url{font-size:26px;font-weight:700;text-align:right;white-space:nowrap}
</style></head><body><div class="ring r1"></div><div class="ring r2"></div>
<div class="wrap"><div class="brand"><img src="${logo}" alt="">KDDF Market</div>
<div class="main"><div class="emoji">${p.emoji}</div><div class="kicker">${p.kicker}</div><h1>${p.title}</h1><p class="text">${p.text}</p>
<div class="chips">${p.chips.map((c) => `<div class="chip"><i></i>${c}</div>`).join("")}</div></div>
<div class="foot"><div class="cta">${p.cta} →</div><div class="url">${SITE_URL}</div></div></div></body></html>`;
}

const browser = await chromium.launch();
for (const [folder, w, h] of [["feed", 1080, 1350], ["story", 1080, 1920]]) {
  fs.mkdirSync(path.join(here, "affiches", folder), { recursive: true });
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  for (const p of POSTERS) {
    await page.setContent(html(p, w, h), { waitUntil: "load" });
    await page.screenshot({ path: path.join(here, "affiches", folder, `kddf-market-${p.id}.png`) });
  }
  await page.close();
}
await browser.close();
console.log("Affiches générées dans marketing/affiches");

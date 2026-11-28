// Contenu des affiches de bienvenue (affichées au premier passage d'un visiteur, et rouvrables avec « Revoir le guide »).
// Les chiffres qui se règlent dans l'admin (commissions, limite de produits) ne sont volontairement PAS écrits ici.

import { legalInfo } from "@/lib/legal";

export interface Poster {
  id: string;
  emoji: string;
  kicker: string;
  title: string;
  text: string;
  bullets: string[];
  /** Dégradé de fond (deux couleurs sombres de la charte) + couleur d'accent. */
  from: string;
  to: string;
  accent: string;
  cta?: { label: string; href: string };
}

/** Numéro WhatsApp du service client : variable NEXT_PUBLIC_SUPPORT_WHATSAPP, sinon le téléphone de l'éditeur. */
export function supportWhatsapp(): string {
  const raw = (process.env.NEXT_PUBLIC_SUPPORT_WHATSAPP ?? "").trim() || legalInfo().phone;
  return raw.replace(/\D/g, "");
}

export function supportEmail(): string {
  return (process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? "").trim() || legalInfo().email;
}

export function posters(): Poster[] {
  const wa = supportWhatsapp();
  const mail = supportEmail();
  return [
    {
      id: "bienvenue",
      emoji: "👋",
      kicker: "Bienvenue",
      title: "KDDF Market, la marketplace qui vous ressemble",
      text: "Achetez, vendez et gagnez de l'argent avec des produits digitaux et physiques, partout au Cameroun et au-delà.",
      bullets: ["Guides, formations, fichiers, licences", "Produits physiques avec livraison", "Paiement en Mobile Money, carte, PayPal ou crypto"],
      from: "#1E1B4B", to: "#4338CA", accent: "#A5B4FC",
    },
    {
      id: "acheter",
      emoji: "🛒",
      kicker: "Acheter",
      title: "Acheter en 3 étapes simples",
      text: "Pas besoin d'être expert : en quelques secondes, votre achat est payé et livré.",
      bullets: ["1. Choisissez un produit (la loupe 🔍 vous aide à chercher)", "2. Payez avec MTN MoMo, Orange Money, carte, PayPal ou crypto", "3. Téléchargez tout de suite, ou suivez votre colis avec votre code KDDF-XXXX"],
      from: "#064E3B", to: "#0F766E", accent: "#6EE7B7",
      cta: { label: "Voir les produits", href: "/" },
    },
    {
      id: "vendre",
      emoji: "🚀",
      kicker: "Vendre",
      title: "Ouvrez votre boutique en 2 minutes",
      text: "Créez un compte, publiez vos produits et recevez vos paiements directement sur votre portefeuille.",
      bullets: ["Boutique gratuite pour démarrer, sans abonnement obligatoire", "Retrait de vos gains en Mobile Money", "Statistiques de ventes en temps réel dans votre espace créateur"],
      from: "#312E81", to: "#6D28D9", accent: "#C4B5FD",
      cta: { label: "Ouvrir ma boutique", href: "/login?mode=signup" },
    },
    {
      id: "benefices",
      emoji: "🎁",
      kicker: "Vos avantages",
      title: "Pourquoi choisir KDDF Market ?",
      text: "Tout est pensé pour que vous gagniez du temps et de la tranquillité.",
      bullets: ["Paiements sécurisés, devises FCFA, euro et dollar", "Garantie : retour sous 48 h, remboursement sous 7 jours si le produit n'est pas conforme (paiement fait sur KDDF Market)", "Téléchargement automatique et reçu par email", "Retrait express possible pour les vendeurs pressés"],
      from: "#7C2D12", to: "#B45309", accent: "#FCD34D",
    },
    {
      id: "affiliation",
      emoji: "🤝",
      kicker: "Affiliation",
      title: "Gagnez en recommandant",
      text: "Pas de produit à vendre ? Partagez le lien d'un produit et touchez une commission à chaque vente réalisée grâce à vous.",
      bullets: ["Votre lien personnel dans l'espace créateur", "Commission fixée par le vendeur (jusqu'à 50 %)", "Suivi de vos gains et retrait en Mobile Money"],
      from: "#134E4A", to: "#0E7490", accent: "#67E8F9",
      cta: { label: "Devenir affilié", href: "/login?mode=signup" },
    },
    {
      id: "securite",
      emoji: "🛡️",
      kicker: "Sécurité",
      title: "Des vendeurs vérifiés, un compte protégé",
      text: "Pour éviter les arnaques, chaque vendeur est contrôlé avant de publier. Vous pouvez aussi protéger votre compte.",
      bullets: ["Vendeurs vérifiés par carte d'identité", "Protection 2FA facultative (code à 6 chiffres)", "Numéro de téléphone confirmé par SMS", "Anti-fraude et litiges traités par l'équipe"],
      from: "#1E3A8A", to: "#1D4ED8", accent: "#93C5FD",
      cta: { label: "Sécuriser mon compte", href: "/securite" },
    },
    {
      id: "installer",
      emoji: "📲",
      kicker: "Application",
      title: "Installez KDDF Market sur votre téléphone ou PC",
      text: "Comme une vraie application, sans passer par un magasin d'applications.",
      bullets: ["Android / PC (Chrome, Edge) : bouton « Installer » en bas de la page", "iPhone (Safari) : Partager, puis « Sur l'écran d'accueil »", "Elle s'ouvre en plein écran, comme une application"],
      from: "#3B0764", to: "#7E22CE", accent: "#E9D5FF",
    },
    {
      id: "service-client",
      emoji: "💬",
      kicker: "Service client",
      title: "Un problème ? On vous répond",
      text: "Paiement, commande, compte, bug : écrivez-nous, avec une capture d'écran si possible.",
      bullets: [
        wa ? `WhatsApp : +${wa}` : "WhatsApp : voir la page Aide",
        `Email : ${mail}`,
        "Ou le formulaire de la page « Aide et support »",
      ],
      from: "#0F172A", to: "#334155", accent: "#5EEAD4",
      cta: { label: "Contacter le service client", href: "/support" },
    },
  ];
}

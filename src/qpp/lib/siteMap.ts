// Plan du site pour la recherche rapide (loupe de l'en-tête) : chaque page avec des mots-clés pour la retrouver facilement.
export type SearchSection = "site" | "dashboard" | "admin";

export interface SearchItem {
  href: string;
  label: string;
  hint: string; // petite description affichée sous le titre
  section: SearchSection;
  keywords: string; // mots que l'utilisateur peut taper (sans accent, en minuscules)
}

export const SECTION_LABELS: Record<SearchSection, string> = {
  site: "Le site",
  dashboard: "Espace créateur",
  admin: "Administration",
};

const SITE: SearchItem[] = [
  { href: "/", label: "Accueil et catalogue", hint: "Tous les produits", section: "site", keywords: "produits boutique acheter catalogue accueil home" },
  { href: "/grossistes", label: "Grossistes", hint: "Acheter en gros ou devenir grossiste", section: "site", keywords: "gros revendre revendeur devenir grossiste candidature carte identite" },
  { href: "/services", label: "Services", hint: "Couverture, coaching et autres services", section: "site", keywords: "service visuel couverture coaching aide creation" },
  { href: "/suivre-commande", label: "Suivre ma commande", hint: "Avec votre numéro et le code KDDF-XXXX", section: "site", keywords: "suivi colis livraison commande code numero tracking" },
  { href: "/panier", label: "Mon panier", hint: "Les produits que vous allez commander", section: "site", keywords: "panier achat commander" },
  { href: "/support", label: "Aide et support", hint: "Contacter l'équipe", section: "site", keywords: "aide contact support probleme question whatsapp message" },
  { href: "/conditions", label: "Conditions d'utilisation et de vente", hint: "Règles du site, commissions, retraits", section: "site", keywords: "conditions cgu cgv regles contrat vente utilisation" },
  { href: "/confidentialite", label: "Confidentialité", hint: "Vos données personnelles", section: "site", keywords: "confidentialite donnees personnelles cookies vie privee rgpd" },
  { href: "/remboursement", label: "Remboursement et litiges", hint: "Que faire en cas de problème", section: "site", keywords: "remboursement litige probleme retour rembourser colis non recu" },
  { href: "/mentions-legales", label: "Mentions légales", hint: "Éditeur et hébergeur du site", section: "site", keywords: "mentions legales editeur hebergeur contact" },
  { href: "/international", label: "International", hint: "Pays disponibles et prochaines ouvertures", section: "site", keywords: "pays devise etranger international liste attente" },
];

const SITE_SIGNED_IN: SearchItem[] = [
  { href: "/securite", label: "Sécurité du compte", hint: "2FA, téléphone et identité", section: "site", keywords: "securite 2fa double authentification telephone sms code protection compte identite verification" },
  { href: "/dashboard/verification", label: "Vérification d'identité", hint: "Carte d'identité + selfie pour publier", section: "dashboard", keywords: "identite verification carte cni selfie video verifier badge publier kyc" },
  { href: "/library", label: "Mes achats", hint: "Téléchargements et commandes", section: "site", keywords: "achats telechargement bibliotheque commandes recu pdf livre" },
];

const SITE_SIGNED_OUT: SearchItem[] = [
  { href: "/login", label: "Connexion", hint: "Se connecter à son compte", section: "site", keywords: "connexion login connecter compte mot de passe" },
  { href: "/login?mode=signup", label: "Créer un compte vendeur", hint: "Vendre sur KDDF Market", section: "site", keywords: "inscription inscrire creer compte vendre vendeur" },
];

const DASHBOARD: SearchItem[] = [
  { href: "/dashboard", label: "Vue d'ensemble", hint: "Ventes, revenus et alertes", section: "dashboard", keywords: "statistiques ventes revenus chiffre affaires tableau de bord accueil" },
  { href: "/dashboard/products", label: "Catalogue", hint: "Mes produits : modifier, prix, stock", section: "dashboard", keywords: "produits modifier prix stock supprimer publier catalogue" },
  { href: "/dashboard/products/new", label: "Ajouter un produit", hint: "Publier un nouveau produit", section: "dashboard", keywords: "nouveau produit ajouter creer publier vendre mettre en vente" },
  { href: "/dashboard/orders", label: "Commandes", hint: "Traiter et livrer les commandes", section: "dashboard", keywords: "commandes clients livraison expedier cash confirmer litige" },
  { href: "/dashboard/promote", label: "Promouvoir", hint: "Boost : produit à la une", section: "dashboard", keywords: "boost promouvoir promotion publicite visibilite a la une" },
  { href: "/dashboard/pro", label: "Abonnement Pro", hint: "Commission réduite et badge", section: "dashboard", keywords: "pro abonnement commission reduite badge prolonger" },
  { href: "/dashboard/wallet", label: "Mes gains et retraits", hint: "Solde, retrait normal ou express", section: "dashboard", keywords: "gains retrait retirer argent solde paiement express frais mobile money momo" },
  { href: "/dashboard/affiliates", label: "Affiliation", hint: "Mes liens et commissions d'affilié", section: "dashboard", keywords: "affiliation affilie lien parrainage commission partager" },
  { href: "/dashboard/shop", label: "Ma boutique", hint: "Nom, logo et adresse de la boutique", section: "dashboard", keywords: "boutique nom logo adresse slug description vitrine" },
  { href: "/dashboard/settings", label: "Mon profil", hint: "Mes informations et mon WhatsApp", section: "dashboard", keywords: "profil compte informations whatsapp telephone nom email supprimer compte telecharger donnees" },
];

const ADMIN: SearchItem[] = [
  { href: "/admin", label: "Tableau de bord", hint: "Chiffres du site", section: "admin", keywords: "tableau de bord statistiques revenus accueil admin" },
  { href: "/admin/annonces", label: "Annonces (cloche)", hint: "Envoyer un message à tous les utilisateurs", section: "admin", keywords: "annonce notification cloche message communiquer envoyer utilisateurs" },
  { href: "/admin/identite", label: "Identités des vendeurs", hint: "Valider ou refuser les cartes d'identité", section: "admin", keywords: "identite verification carte cni selfie valider refuser vendeurs securite regles telephone 2fa" },
  { href: "/admin/sellers", label: "Vendeurs", hint: "Liste et contrôle des vendeurs", section: "admin", keywords: "vendeurs bloquer verifier comptes" },
  { href: "/admin/orders", label: "Commandes", hint: "Toutes les commandes", section: "admin", keywords: "commandes ventes livraison" },
  { href: "/admin/withdrawals", label: "Retraits", hint: "Demandes à payer (express en tête)", section: "admin", keywords: "retraits payer vendeurs express argent" },
  { href: "/admin/products", label: "Produits à valider", hint: "Modération des produits", section: "admin", keywords: "produits valider moderation approuver refuser" },
  { href: "/admin/support", label: "Messages", hint: "Messages reçus du support", section: "admin", keywords: "messages support aide tickets" },
  { href: "/admin/commissions", label: "Commissions et tarifs", hint: "Taux, Pro, frais de retrait, express, exemptions", section: "admin", keywords: "commission tarifs pro frais retrait express exempter lancement taux frais de service paypal carte crypto limite produits gratuit" },
  { href: "/admin/pub", label: "Pub et bannières", hint: "Bannières sponsorisées, produit de la semaine", section: "admin", keywords: "pub publicite banniere sponsor produit semaine" },
  { href: "/admin/fraude", label: "Anti-fraude", hint: "Comptes et achats suspects", section: "admin", keywords: "fraude suspect bloquer ip" },
  { href: "/admin/litiges", label: "Litiges", hint: "Réclamations des acheteurs", section: "admin", keywords: "litiges reclamation remboursement dispute" },
  { href: "/admin/validation", label: "Validation", hint: "Candidatures grossistes et vérifications", section: "admin", keywords: "validation grossiste candidature verifier avis" },
  { href: "/admin/erreurs", label: "Erreurs du site", hint: "Pages qui ont planté chez les visiteurs", section: "admin", keywords: "erreurs bugs plantage journal problemes technique" },
  { href: "/admin/payouts", label: "Payouts", hint: "Paiements aux vendeurs", section: "admin", keywords: "payouts paiements vendeurs transferts" },
];

/** Pages proposées à la recherche, selon le statut de la personne connectée. */
export function searchItems(signedIn: boolean, isAdmin: boolean): SearchItem[] {
  return [
    ...SITE,
    ...(signedIn ? SITE_SIGNED_IN : SITE_SIGNED_OUT),
    ...(signedIn ? DASHBOARD : []),
    ...(isAdmin ? ADMIN : []),
  ];
}

/** « Été » -> « ete » : on compare sans accents ni majuscules. */
export function normalize(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

/** Les éléments dont l'un des mots tapés se retrouve dans le titre, la description ou les mots-clés (tous les mots doivent correspondre). */
export function filterItems(items: SearchItem[], query: string): SearchItem[] {
  const words = normalize(query).split(/\s+/).filter(Boolean);
  if (words.length === 0) return items;
  const scored = items
    .map((it) => {
      const label = normalize(it.label);
      const hay = `${label} ${normalize(it.hint)} ${it.keywords}`;
      if (!words.every((w) => hay.includes(w))) return null;
      const score = words.reduce((n, w) => n + (label.startsWith(w) ? 3 : label.includes(w) ? 2 : 1), 0);
      return { it, score };
    })
    .filter((x): x is { it: SearchItem; score: number } => x !== null);
  return scored.sort((a, b) => b.score - a.score).map((x) => x.it);
}

// Services payants proposés par KDDF Market (page /services). Modifiez librement les titres, textes et PRIX ci-dessous (FCFA entiers) :
// ils sont affichés tels quels, et la commande se fait par WhatsApp (NEXT_PUBLIC_SUPPORT_WHATSAPP).
export interface PaidService {
  id: string;
  title: string;
  description: string;
  price: number;
  /** « à partir de » : le prix final dépend de la demande */
  from?: boolean;
  unit?: string;
}

export const PAID_SERVICES: readonly PaidService[] = [
  { id: "page", title: "Création de ma page produit", description: "Titre qui donne envie, description claire et mise en forme de votre fiche produit, prête à vendre.", price: 5000 },
  { id: "visuel", title: "Couverture / visuel de produit", description: "Une image de couverture soignée pour votre guide, formation ou produit, aux bonnes dimensions.", price: 3000 },
  { id: "lancement", title: "Lancement accompagné", description: "Vérification de votre boutique, plan de partage (WhatsApp, statuts, réseaux) et conseils pour vos premières ventes.", price: 10000 },
  { id: "coaching", title: "Coaching 1 h : vendre en ligne", description: "Une séance en visio ou par WhatsApp pour définir votre offre, votre prix et votre stratégie.", price: 7500, unit: "la séance" },
  { id: "pub", title: "Votre marque sur l'accueil", description: "Une bannière « Sponsorisé » en page d'accueil de KDDF Market, vue par tous les visiteurs.", price: 15000, from: true, unit: "pour 7 jours" },
];

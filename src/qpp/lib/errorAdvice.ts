// Notice « que faire ? » pour l'administrateur : chaque erreur du journal est reconnue par son texte et accompagnée
// d'une cause probable et d'étapes simples. Utilisé par Admin > Erreurs ET par l'email d'alerte (aucune donnée secrète ici).

export interface Advice {
  title: string;
  cause: string;
  steps: string[];
  /** 0 = sans importance, 1 = à surveiller, 2 = à corriger vite */
  urgency: 0 | 1 | 2;
}

const RULES: { test: RegExp; advice: Advice }[] = [
  {
    test: /ChunkLoadError|Loading chunk|dynamically imported module|Failed to load script/i,
    advice: {
      title: "Fichier du site introuvable (mise à jour en cours)",
      cause: "Le visiteur avait ouvert le site AVANT votre dernière mise en ligne : son navigateur cherche un ancien fichier qui n'existe plus.",
      steps: ["Rien à corriger : c'est normal juste après un déploiement.", "Le visiteur règle le problème en rechargeant la page.", "Si cela arrive en continu pendant plus d'une heure : Vercel > Deployments, vérifiez que le dernier déploiement est « Ready »."],
      urgency: 0,
    },
  },
  {
    test: /Minified React error #(418|423|425)|hydrat/i,
    advice: {
      title: "Affichage différent entre le serveur et le navigateur",
      cause: "Souvent causé par une extension du navigateur du visiteur (traduction automatique, bloqueur de pub) qui modifie la page.",
      steps: ["Si c'est rare et chez un seul visiteur : ignorez.", "Si cela revient chez beaucoup de visiteurs sur la même page : notez la page (colonne « Page ») et envoyez-la moi avec la référence."],
      urgency: 0,
    },
  },
  {
    test: /schema cache|could not find the (table|function)|relation .* does not exist|function .* does not exist/i,
    advice: {
      title: "Une partie de la base de données n'est pas installée",
      cause: "Le site utilise une fonction ou une table qui n'existe pas encore dans votre Supabase (mise à jour SQL non lancée).",
      steps: ["Supabase > SQL Editor.", "Collez le fichier de mise à jour de votre version (ex. supabase/mise-a-jour-identite.sql) puis cliquez Run.", "Lancez ensuite supabase/verifier-installation.sql : toutes les lignes doivent afficher « OK »."],
      urgency: 2,
    },
  },
  {
    test: /invalid api key|no api key|apikey|NEXT_PUBLIC_SUPABASE|SUPABASE_SERVICE_ROLE|supabaseUrl is required/i,
    advice: {
      title: "Clés Supabase absentes ou fausses",
      cause: "Une variable d'environnement Supabase est vide ou incorrecte sur Vercel.",
      steps: ["Vercel > Settings > Environment Variables.", "Vérifiez NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY et SUPABASE_SERVICE_ROLE_KEY (Supabase > Project Settings > API).", "Enregistrez puis Deployments > Redeploy."],
      urgency: 2,
    },
  },
  {
    test: /failed to fetch|fetch failed|networkerror|network request|load failed|timed? ?out|econn|enotfound/i,
    advice: {
      title: "Problème de connexion",
      cause: "Le visiteur a perdu sa connexion internet, ou Supabase / un service de paiement n'a pas répondu.",
      steps: ["Si c'est isolé : ignorez (réseau mobile instable).", "Si cela se répète : ouvrez le tableau de bord Supabase et vérifiez que le projet n'est pas « Paused » (plan gratuit : il se met en pause après 7 jours sans activité).", "Vérifiez aussi status.vercel.com."],
      urgency: 1,
    },
  },
  {
    test: /jwt expired|invalid jwt|refresh token|auth session missing/i,
    advice: {
      title: "Session expirée",
      cause: "Le visiteur est resté connecté trop longtemps ou s'est déconnecté dans un autre onglet.",
      steps: ["Rien à corriger : il lui suffit de se reconnecter."],
      urgency: 0,
    },
  },
  {
    test: /fapshi|flutterwave|paypal|nowpayments|paiement|payment/i,
    advice: {
      title: "Erreur liée à un paiement",
      cause: "Un service de paiement a refusé ou n'a pas répondu à la demande.",
      steps: ["Vérifiez les clés du service concerné dans Vercel > Environment Variables (FAPSHI_*, FLW_*, PAYPAL_*, NOWPAYMENTS_*).", "Ouvrez Admin > Payouts et Admin > Commandes : y a-t-il des paiements « en attente » à rattraper ?", "Si un client dit avoir payé sans recevoir son produit : Admin > Litiges."],
      urgency: 2,
    },
  },
  {
    test: /row-level security|permission denied|violates row/i,
    advice: {
      title: "Droits refusés dans la base",
      cause: "Une action a été refusée par les règles de sécurité (session expirée, ou mise à jour SQL non lancée).",
      steps: ["Lancez supabase/verifier-installation.sql dans Supabase : cherchez une ligne « MANQUANT ».", "S'il y en a une, relancez le fichier de mise à jour correspondant."],
      urgency: 1,
    },
  },
];

const FALLBACK: Advice = {
  title: "Erreur inconnue",
  cause: "Le site a rencontré un problème que je ne reconnais pas encore.",
  steps: [
    "Notez la page (colonne « Page ») et la référence.",
    "Vercel > votre projet > Logs : collez la référence dans la recherche pour voir le détail technique.",
    "Si l'erreur revient souvent (« fois en 30 jours »), envoyez-moi une capture de cette ligne : je corrige le code.",
  ],
  urgency: 1,
};

/** Notice adaptée à un message d'erreur du journal. */
export function adviceFor(message: string): Advice {
  return RULES.find((r) => r.test.test(message))?.advice ?? FALLBACK;
}

export const URGENCY_LABEL: Record<Advice["urgency"], string> = { 0: "Sans gravité", 1: "À surveiller", 2: "À corriger vite" };

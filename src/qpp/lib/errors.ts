// Explication des erreurs : chaque message dit la CAUSE exacte puis propose une SOLUTION.
// Fonctionne pour les erreurs de la base (codes métier), de Supabase (auth, stockage, droits) et du réseau.

export interface Explained {
  cause: string;
  fix: string;
}

/** Erreurs métier levées par les fonctions SQL (le code est le texte de l'exception). */
const DB: Record<string, Explained> = {
  produit_introuvable: { cause: "Ce produit n'existe plus, est dépublié ou n'a pas encore été validé.", fix: "Revenez à l'accueil et choisissez un autre produit." },
  email_invalide: { cause: "L'adresse email saisie n'a pas un format valide.", fix: "Vérifiez l'orthographe (ex. nom@gmail.com) et réessayez." },
  connexion_requise: { cause: "Vous n'êtes pas connecté ou votre session a expiré.", fix: "Connectez-vous puis recommencez l'action." },
  quantite_invalide: { cause: "La quantité demandée n'est pas valide.", fix: "Indiquez un nombre entier supérieur ou égal à 1." },
  compte_requis_gros: { cause: "Une commande de gros demande un compte KDDF Market (c'est ce qui protège l'acheteur et le grossiste).", fix: "Créez votre compte gratuit ou connectez-vous, puis recommencez la commande." },
  cod_interdit_gros: { cause: "Le paiement à la livraison n'existe pas pour les commandes de gros : l'argent est gardé par KDDF Market jusqu'à la réception.", fix: "Payez en ligne (Mobile Money, carte, PayPal ou crypto)." },
  quantite_gros_invalide: { cause: "Une commande de gros se fait à partir de 10 pièces et jusqu'à 1 000 pièces.", fix: "Indiquez une quantité entre 10 et 1 000. Au-delà, demandez un devis par WhatsApp." },
  produit_gros_introuvable: { cause: "Ce produit n'est plus proposé en gros, ou son grossiste n'est plus vérifié.", fix: "Revenez sur la page Grossistes et choisissez une autre offre." },
  stock_gros_insuffisant: { cause: "Le grossiste n'a pas assez de pièces disponibles en gros pour cette quantité.", fix: "Diminuez la quantité ou demandez un devis par WhatsApp." },
  achat_propre_produit: { cause: "Vous ne pouvez pas acheter votre propre produit.", fix: "Utilisez un autre compte acheteur." },
  stock_insuffisant: { cause: "Il n'y a pas assez de stock pour cette quantité.", fix: "Diminuez la quantité ou contactez le vendeur." },
  livraison_invalide: { cause: "Ce mode de livraison n'est pas proposé pour ce produit.", fix: "Choisissez un autre mode de livraison dans la liste." },
  telephone_invalide: { cause: "Le numéro de téléphone n'a pas un format valide.", fix: "Saisissez un numéro camerounais, par exemple 6XXXXXXXX." },
  adresse_invalide: { cause: "L'adresse de livraison est trop courte.", fix: "Indiquez le quartier, la rue et un repère." },
  affiliation_invalide: { cause: "La commission d'affilié choisie n'est pas valide (elle doit être un nombre entier de 1 % à 50 %, jamais plus).", fix: "Choisissez une valeur entre 1 % et 50 % avec le curseur." },
  acces_refuse: { cause: "Votre compte n'a pas le droit d'effectuer cette action.", fix: "Connectez-vous avec le bon compte, ou contactez le support." },
  commande_invalide: { cause: "Cette action n'est pas possible dans l'état actuel de la commande.", fix: "Actualisez la page pour voir le statut à jour." },
  transition_invalide: { cause: "Ce changement de statut n'est pas autorisé à cette étape.", fix: "Actualisez la page et utilisez le bouton proposé pour l'étape suivante." },
  motif_invalide: { cause: "Le motif est trop court.", fix: "Décrivez le problème en au moins 5 caractères." },
  fonds_deja_liberes: { cause: "Les fonds de cette commande ont déjà été versés au vendeur.", fix: "Contactez le support pour un éventuel remboursement." },
  methode_invalide: { cause: "Le moyen de retrait choisi n'est pas valide.", fix: "Choisissez un moyen dans la liste proposée." },
  destination_invalide: { cause: "Le compte de réception saisi n'a pas un format valide pour ce moyen de retrait.", fix: "PayPal : votre email PayPal. Crypto : l'adresse complète de votre portefeuille. Virement : IBAN ou numéro de compte suivi du nom de la banque." },
  montant_minimum: { cause: "Le montant est inférieur au minimum de retrait (1 000 FCFA).", fix: "Saisissez au moins 1 000 FCFA." },
  solde_insuffisant: { cause: "Votre solde disponible est inférieur au montant demandé.", fix: "Demandez un montant plus petit. Les fonds « en attente » ne sont pas encore retirables." },
  retrait_deja_traite: { cause: "Ce retrait a déjà été traité.", fix: "Actualisez la page." },
  resultat_invalide: { cause: "Le résultat choisi n'est pas valide.", fix: "Actualisez la page et recommencez." },
  transaction_invalide: { cause: "Cette transaction ne peut pas être remboursée dans son état actuel.", fix: "Actualisez la page pour voir son statut." },
  cod_interdit_digital: { cause: "Le paiement à la livraison n'existe pas pour les produits digitaux.", fix: "Payez en ligne avec Orange Money ou MTN MoMo." },
  paiement_invalide: { cause: "Le moyen de paiement choisi n'est pas valide.", fix: "Choisissez Orange Money / MTN MoMo, ou le paiement à la livraison pour un produit physique." },
  vendeur_bloque: { cause: "Ce vendeur est suspendu par KDDF Market.", fix: "Choisissez un produit d'un autre vendeur." },
  compte_bloque: { cause: "Votre compte a été bloqué par l'administration.", fix: "Contactez le support de KDDF Market pour connaître la raison." },
  compte_en_verification: { cause: "Activité suspecte : vos retraits sont suspendus le temps d'une vérification.", fix: "Contactez le support de KDDF Market." },
  encaissement_requis: { cause: "Une commande payée à la livraison se termine en encaissant le cash.", fix: "Cliquez sur « Cash encaissé (livrée) »." },
  avis_non_autorise: { cause: "Vous ne pouvez noter qu'une commande dont vous avez confirmé la réception.", fix: "Cliquez d'abord sur « J'ai reçu mon produit », puis laissez votre avis." },
  avis_deja_envoye: { cause: "Vous avez déjà donné votre avis sur cette commande.", fix: "Un seul avis par commande est possible." },
  note_invalide: { cause: "La note n'est pas comprise entre 1 et 5.", fix: "Cliquez sur une étoile pour choisir votre note." },
  action_interdite: { cause: "Cette action est réservée à l'administrateur.", fix: "Connectez-vous avec le compte administrateur." },
  compte_trop_recent: { cause: "Votre compte a été créé il y a moins de 24 heures.", fix: "Revenez demain pour envoyer votre candidature grossiste." },
  liste_pleine: { cause: "La liste d'attente de ce pays est complète pour le moment.", fix: "Réessayez plus tard ou contactez le support." },
  fichier_invalide: { cause: "Le fichier envoyé n'est pas rattaché à votre compte.", fix: "Envoyez à nouveau le fichier depuis cette page, puis validez." },
  pays_invalide: { cause: "Ce pays n'est pas proposé pour l'instant.", fix: "Choisissez un pays dans la liste." },
  deja_grossiste: { cause: "Votre compte est déjà validé comme grossiste.", fix: "Rendez-vous dans « Grossistes » pour gérer vos produits en gros." },
  grossiste_requis: { cause: "Cette action est réservée aux grossistes validés par KDDF Market.", fix: "Envoyez votre candidature depuis la page « Grossistes » et attendez la validation." },
  candidature_introuvable: { cause: "Aucune candidature en attente pour ce compte.", fix: "Actualisez la page." },
  produit_invalide: { cause: "Ce produit ne peut pas être utilisé pour cette action (il doit être physique et vous appartenir).", fix: "Choisissez un de vos produits physiques." },
  prix_gros_invalide: { cause: "Les prix de gros ne sont pas cohérents (le prix par 50 doit être inférieur ou égal au prix par 10, lui-même inférieur au prix de détail).", fix: "Corrigez les prix puis enregistrez à nouveau." },
  stock_invalide: { cause: "Le stock saisi n'est pas valide.", fix: "Indiquez un nombre entier supérieur ou égal à 0." },
  commission_invalide: { cause: "Les pourcentages de commission ne sont pas valides.", fix: "Respectez les limites affichées sur la page des commissions." },
  utilisateur_introuvable: { cause: "Aucun compte ne correspond à cet e-mail.", fix: "Vérifiez l'adresse (le compte doit déjà être inscrit sur le site)." },
  abonnement_inconnu: { cause: "Cet abonnement n'existe pas.", fix: "Recommencez depuis la page « Abonnement Pro »." },
  boost_inconnu: { cause: "Cette offre de promotion n'existe pas.", fix: "Choisissez une offre dans la liste." },
  alerte_introuvable: { cause: "Cette alerte n'existe plus.", fix: "Actualisez la page." },
  litige_introuvable: { cause: "Ce litige n'existe pas ou ne vous concerne pas.", fix: "Actualisez la page." },
  photo_invalide: { cause: "La photo envoyée n'est pas rattachée à ce litige.", fix: "Envoyez à nouveau la photo depuis la page du litige." },
  transaction_inconnue: { cause: "Cette transaction est introuvable.", fix: "Actualisez la page ou contactez le support." },
  portefeuille_incoherent: { cause: "Le portefeuille n'a pas pu être mis à jour de façon cohérente : l'opération a été annulée par sécurité.", fix: "Aucun argent n'a bougé. Contactez le support avec la référence de la commande." },
  repartition_invalide: { cause: "La répartition de la vente n'est pas cohérente : l'opération a été annulée par sécurité.", fix: "Aucun argent n'a bougé. Contactez le support." },
  annonce_invalide: { cause: "L'annonce n'est pas valide : titre de 3 à 80 caractères, message de 3 à 500 caractères, durée de 1 à 365 jours.", fix: "Corrigez les champs puis renvoyez l'annonce." },
  annonce_lien_invalide: { cause: "Le lien de l'annonce n'est pas accepté : il doit commencer par / (page du site) ou par https://.", fix: "Exemple : /dashboard/wallet ou https://exemple.com. Laissez vide pour une annonce sans lien." },
  trop_d_annonces: { cause: "Vous avez déjà envoyé 10 annonces en moins d'une heure.", fix: "Attendez un peu avant d'en envoyer une autre : chaque annonce arrive dans la cloche de tous les utilisateurs concernés." },
  limite_produits_gratuit: { cause: "Vous avez atteint le nombre maximum de produits publiés du plan gratuit.", fix: "Dépubliez un produit que vous ne vendez plus, enregistrez ce produit en brouillon, ou passez à l'abonnement Pro (menu Abonnement Pro) pour publier sans limite." },
  valeur_invalide: { cause: "Une des valeurs saisies n'est pas dans les limites autorisées.", fix: "Corrigez les champs en respectant les limites affichées." },
  transaction_deja_traitee: { cause: "Cette transaction a déjà été traitée.", fix: "Actualisez la page." },
  solde_non_vide: { cause: "Votre portefeuille contient encore de l'argent (en attente ou disponible).", fix: "Retirez d'abord tout votre solde (menu Portefeuille), attendez que le retrait soit traité, puis supprimez votre compte." },
  commission_due: { cause: "Une commission sur des ventes en cash reste à régler à KDDF Market.", fix: "Elle est déduite de votre prochain retrait : faites un retrait, ou contactez le support pour la régler." },
  retrait_en_cours: { cause: "Un retrait est encore en attente de traitement.", fix: "Attendez qu'il soit traité (paiement ou refus) puis recommencez." },
  litige_en_cours: { cause: "Un litige est en cours sur une de vos commandes.", fix: "Attendez la décision de l'équipe KDDF Market, puis recommencez." },
  commandes_en_cours: { cause: "Vous avez des commandes physiques payées qui ne sont pas encore terminées.", fix: "Attendez leur livraison et leur clôture, puis recommencez." },
  admin_non_supprimable: { cause: "Le compte administrateur ne peut pas être supprimé depuis le site.", fix: "Retirez d'abord le rôle administrateur dans Supabase si vous le souhaitez vraiment." },
  trop_de_demandes: { cause: "Trop d'actions en peu de temps.", fix: "Attendez une minute puis réessayez." },
  compte_requis_digital: { cause: "Pour les produits digitaux, crée un compte gratuit en 30 secondes pour recevoir ton fichier.", fix: "Clique sur « Créer mon compte gratuit », puis reviens acheter." },
  nom_invalide: { cause: "Le nom complet est manquant ou trop court.", fix: "Écrivez votre nom et prénom (au moins 2 lettres)." },
  ville_invalide: { cause: "La ville est manquante.", fix: "Indiquez votre ville (ex. Douala, Yaoundé, Bafoussam, Garoua)." },
  quartier_invalide: { cause: "Le quartier est manquant.", fix: "Indiquez votre quartier (ex. Akwa, Bonamoussadi, Mvan)." },
  trop_de_commandes_numero: { cause: "Trop de commandes en 1 heure avec ce numéro de téléphone (maximum 5).", fix: "Patientez une heure puis recommencez, ou contactez le support si vous êtes un vrai client." },
  commande_introuvable: { cause: "Aucune commande ne correspond à ce numéro et à ce code.", fix: "Vérifiez le numéro utilisé à la commande et le code KDDF-XXXX reçu (ex. KDDF-8421)." },
  litige_ouvert: { cause: "Un litige est déjà ouvert sur cette commande : l'équipe KDDF Market doit trancher d'abord.", fix: "Patientez, nous revenons vers vous." },
  litige_deja_ouvert: { cause: "Un litige est déjà ouvert sur cette commande.", fix: "Patientez, nous revenons vers vous." },
  trop_de_photos: { cause: "Vous avez joint trop de photos (3 maximum).", fix: "Gardez les 3 photos les plus utiles." },
  identite_requise: { cause: "Votre identité n'est pas encore vérifiée : pour la sécurité des acheteurs, on ne peut publier un produit qu'après validation de votre carte d'identité.", fix: "Ouvrez « Vérification d'identité » dans votre espace créateur, envoyez votre carte (recto, verso) et votre selfie ou courte vidéo : l'administrateur répond sous 24 à 48 h. En attendant, vous pouvez préparer vos produits en brouillon." },
  identite_deja_verifiee: { cause: "Votre identité est déjà vérifiée.", fix: "Rien à faire : vous pouvez publier vos produits." },
  identite_en_attente: { cause: "Vos documents d'identité ont déjà été envoyés et sont en cours de vérification.", fix: "Patientez : vous serez prévenu dans la cloche dès la décision." },
  identite_documents_invalides: { cause: "Un des documents d'identité est manquant ou n'a pas pu être enregistré.", fix: "Ajoutez les 3 éléments (recto, verso, selfie ou vidéo) et réessayez. Photos : 10 Mo maximum ; vidéo : 25 Mo maximum (10 secondes suffisent)." },
  motif_requis: { cause: "Un refus doit être expliqué au vendeur.", fix: "Écrivez le motif du refus (3 caractères minimum) puis validez." },
  demande_introuvable: { cause: "Cette demande a déjà été traitée ou n'existe plus.", fix: "Actualisez la page." },
  telephone_non_verifie: { cause: "Votre numéro de téléphone n'est pas encore confirmé par SMS : l'administrateur l'exige avant de publier.", fix: "Ouvrez « Sécurité du compte », saisissez votre numéro puis le code reçu par SMS." },
  verification_2fa_requise: { cause: "La protection 2FA est activée sur votre compte et cette session ne l'a pas validée.", fix: "Déconnectez-vous, reconnectez-vous et saisissez le code à 6 chiffres de votre application d'authentification." },
  decision_invalide: { cause: "La décision envoyée n'est pas valide.", fix: "Actualisez la page et recommencez." },
};

/** Erreurs techniques (Supabase, stockage, réseau), reconnues par leur texte. */
const PATTERNS: { id: string; test: RegExp; e: Explained }[] = [
  { id: "schema", test: /schema cache|could not find the table|relation .* does not exist|could not find the function/i, e: { cause: "La base de données n'est pas (ou pas entièrement) installée dans votre projet Supabase.", fix: "Dans Supabase > SQL Editor, collez TOUT le fichier supabase/schema.sql et cliquez Run, puis réessayez." } },
  { id: "bucket", test: /bucket not found/i, e: { cause: "Le dossier de stockage des images n'existe pas dans Supabase.", fix: "Dans Supabase > Storage, créez un bucket « covers » (public) et un bucket « deliverables » (privé), ou relancez schema.sql." } },
  { id: "invalid_creds", test: /invalid login credentials/i, e: { cause: "L'email ou le mot de passe ne correspond à aucun compte de ce site.", fix: "Vérifiez l'orthographe de l'email, ou cliquez sur « Créer une boutique » si vous n'avez pas encore de compte." } },
  { id: "email_unconfirmed", test: /email not confirmed/i, e: { cause: "Votre adresse email n'a pas encore été confirmée.", fix: "Ouvrez le mail de confirmation (vérifiez les spams) et cliquez sur le lien, puis reconnectez-vous." } },
  { id: "already_registered", test: /already registered|user already exists/i, e: { cause: "Un compte existe déjà avec cet email.", fix: "Cliquez sur « J'ai déjà un compte » et connectez-vous." } },
  { id: "duplicate", test: /duplicate key|already exists|unique constraint/i, e: { cause: "Cette valeur est déjà utilisée (adresse de boutique, nom de produit ou autre élément unique).", fix: "Choisissez une valeur différente." } },
  { id: "weak_password", test: /password should be at least|weak password|password is too short/i, e: { cause: "Le mot de passe est trop court ou trop simple.", fix: "Utilisez au moins 8 caractères, avec des lettres et des chiffres." } },
  { id: "same_password", test: /different from the old password/i, e: { cause: "Le nouveau mot de passe est identique à l'ancien.", fix: "Choisissez un mot de passe différent." } },
  { id: "rate_limit", test: /rate limit|too many requests|over_email_send_rate_limit|security purposes/i, e: { cause: "Trop de tentatives en peu de temps.", fix: "Attendez une minute puis réessayez." } },
  { id: "api_key", test: /invalid api key|no api key|apikey/i, e: { cause: "La clé Supabase configurée sur le site est incorrecte ou absente.", fix: "Sur Vercel > Settings > Environment Variables, vérifiez NEXT_PUBLIC_SUPABASE_ANON_KEY (clé « anon public »), puis Redeploy." } },
  { id: "mfa_code", test: /invalid totp|mfa verification|totp code|challenge.*expired|invalid.*mfa/i, e: { cause: "Le code à 6 chiffres est incorrect ou expiré (il change toutes les 30 secondes).", fix: "Attendez le prochain code dans votre application d'authentification et saisissez-le sans tarder. Si cela échoue encore, vérifiez que l'heure de votre téléphone est réglée sur « automatique »." } },
  { id: "sms_provider", test: /sms.*(provider|send)|phone.*provider|unsupported phone|phone_provider|twilio|messagebird|vonage|textlocal/i, e: { cause: "Le service d'envoi de SMS n'est pas activé sur ce site (ou refuse ce numéro).", fix: "Si vous êtes l'administrateur : Supabase > Authentication > Providers > Phone, activez-le et renseignez un fournisseur SMS (voir SECURITE-COMPTES.md). Sinon, utilisez la validation de votre carte d'identité en attendant." } },
  { id: "otp_expired", test: /token has expired|otp has expired|otp.*invalid|token.*invalid/i, e: { cause: "Le code est faux ou a expiré.", fix: "Demandez un nouveau code et saisissez-le dans la minute qui suit." } },
  { id: "session", test: /jwt expired|invalid jwt|auth session missing|not authenticated|refresh token/i, e: { cause: "Votre session a expiré.", fix: "Reconnectez-vous puis recommencez." } },
  { id: "rls", test: /row-level security|violates row|permission denied|not allowed|insufficient privilege/i, e: { cause: "Votre compte n'a pas l'autorisation d'effectuer cette action (session expirée, compte bloqué ou donnée qui ne vous appartient pas).", fix: "Reconnectez-vous. Si l'erreur continue, contactez le support." } },
  { id: "too_large", test: /too large|maximum allowed size|exceeded|payload|file size/i, e: { cause: "Le fichier est trop lourd.", fix: "Les images doivent faire 5 Mo maximum : réduisez-la (capture d'écran, compression) puis réessayez." } },
  { id: "mime", test: /mime type|not supported|unsupported|invalid file/i, e: { cause: "Le format du fichier n'est pas accepté.", fix: "Utilisez une image JPG, PNG ou WebP." } },
  { id: "invalid_data", test: /check constraint|invalid input syntax|value too long|null value|not-null/i, e: { cause: "Une des valeurs saisies n'est pas acceptée (trop longue, vide ou mal formatée).", fix: "Vérifiez chaque champ : les prix sont des nombres entiers en FCFA, les textes ne sont pas trop longs." } },
  { id: "network", test: /failed to fetch|fetch failed|networkerror|network request|load failed|timeout|timed out|aborted|econn|enotfound/i, e: { cause: "Impossible de joindre le serveur : connexion internet instable, ou Supabase injoignable (projet en pause ou adresse incorrecte).", fix: "Vérifiez votre connexion et réessayez. Sinon : Vercel > NEXT_PUBLIC_SUPABASE_URL et état du projet Supabase." } },
];

const GENERIC: Explained = {
  cause: "Une erreur inattendue s'est produite sur le serveur.",
  fix: "Réessayez dans un instant. Si le problème continue, envoyez une capture de ce message au support.",
};

function render(e: Explained, detail?: string): string {
  const tail = detail ? ` (détail technique : ${detail.replace(/\s+/g, " ").slice(0, 160)})` : "";
  return `Cause : ${e.cause}${tail}\nSolution : ${e.fix}`;
}

/** Code court d'une erreur (clé métier ou identifiant de motif) ; "inconnue" sinon. */
export function errorCode(raw: string | undefined): string {
  if (!raw) return "inconnue";
  const key = Object.keys(DB).find((k) => raw.includes(k));
  if (key) return key;
  return PATTERNS.find((p) => p.test.test(raw))?.id ?? "inconnue";
}

/** Message complet pour un code connu (sans texte libre : sûr à afficher depuis une URL). */
export function explainCode(code: string): string {
  const e = DB[code] ?? PATTERNS.find((p) => p.id === code)?.e ?? GENERIC;
  return render(e);
}

/** Message complet « Cause + Solution » pour une erreur brute. */
export function explainError(raw: string | undefined): string {
  const code = errorCode(raw);
  if (code === "inconnue") return render(GENERIC, raw);
  return explainCode(code);
}

/** Erreur lors de l'ouverture du paiement Fapshi (Orange Money / MTN MoMo) : cause précise + solution. */
export function explainPaymentError(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e);
  const status = typeof e === "object" && e !== null && "status" in e && typeof (e as { status: unknown }).status === "number" ? (e as { status: number }).status : 0;
  if (/FLW_SECRET_KEY|NOWPAYMENTS_API_KEY/i.test(raw)) {
    return render({ cause: "Ce moyen de paiement n'est pas configuré sur le site.", fix: "Choisissez un autre moyen de paiement (Mobile Money Cameroun). Le propriétaire doit ajouter les clés dans Vercel puis Redeploy." });
  }
  if (e instanceof Error && (e.name === "FlutterwaveError" || e.name === "NowPaymentsError")) {
    if (status === 401 || status === 403) return render({ cause: "Le service de paiement a refusé les clés du site.", fix: "Le propriétaire doit vérifier les clés (FLW_SECRET_KEY ou NOWPAYMENTS_API_KEY) sur Vercel, puis Redeploy. Choisissez un autre moyen en attendant." });
    if (status >= 500 || /fetch|network|timeout|econn|enotfound/i.test(raw)) return render({ cause: "Le service de paiement choisi ne répond pas pour le moment.", fix: "Aucun argent n'a été débité. Réessayez dans quelques minutes ou choisissez un autre moyen de paiement." });
    return render({ cause: "Le service de paiement a refusé la demande (montant, devise ou email non accepté).", fix: "Vérifiez votre email, réessayez, ou choisissez un autre moyen de paiement. Aucun argent n'a été débité." });
  }
  if (/FAPSHI_API_USER|FAPSHI_API_KEY|manquant/i.test(raw)) {
    return render({ cause: "Les clés Fapshi ne sont pas configurées sur le site.", fix: "Le propriétaire doit ajouter FAPSHI_API_USER et FAPSHI_API_KEY dans Vercel > Settings > Environment Variables, puis Redeploy. En attendant, achetez en cash si le produit est physique." });
  }
  if (/montant invalide/i.test(raw)) {
    return render({ cause: "Le montant est inférieur au minimum accepté par Fapshi (100 FCFA).", fix: "Choisissez un produit ou une quantité dont le total est d'au moins 100 FCFA." });
  }
  if (status === 401 || status === 403) {
    return render({ cause: "Fapshi a refusé les clés du site (clés fausses, ou mode test/réel qui ne correspond pas).", fix: "Le propriétaire doit vérifier FAPSHI_API_USER, FAPSHI_API_KEY et FAPSHI_ENV (sandbox ou live) sur Vercel, puis Redeploy." });
  }
  if (status === 400 || status === 422) {
    return render({ cause: "Fapshi a refusé la demande : email ou montant non accepté.", fix: "Vérifiez votre adresse email et réessayez avec un autre email si besoin." });
  }
  if (status >= 500 || /fetch|network|timeout|econn|enotfound/i.test(raw)) {
    return render({ cause: "Le service de paiement Fapshi ne répond pas pour le moment.", fix: "Aucun argent n'a été débité. Réessayez dans quelques minutes." });
  }
  return render({ cause: "Le paiement Mobile Money n'a pas pu être lancé.", fix: "Aucun argent n'a été débité. Réessayez ; si cela se répète, contactez le support avec une capture de ce message." });
}

/** Message « Cause + Solution » construit à la main pour les routes API. */
export function explain(cause: string, fix: string): string {
  return render({ cause, fix });
}

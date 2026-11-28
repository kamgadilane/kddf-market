# KDDF Market (V4.0 : projet final)

Marketplace Next.js 14 (App Router, TypeScript strict) + Tailwind + Supabase, hébergée sur Vercel. Paiement Mobile Money via Fapshi (MTN MoMo, Orange Money), cartes et Mobile Money élargi via Flutterwave, crypto via NOWPayments, PayPal (EUR/USD/GBP/CAD) avec conversion de devises en temps réel. Produits **digitaux** et **physiques**, affiliation, portefeuilles, grossistes, litiges, anti-fraude, PWA installable.

**Mise à jour d'un site déjà en ligne : `MISE-A-JOUR-V4-0.md` (depuis la V3.9). Nouvelle installation : `README-DEPLOIEMENT.md` (5 étapes).** Revenus et frais : `REVENUS-ET-FRAIS.md`. Sécurité des comptes (identité, 2FA, téléphone) : `SECURITE-COMPTES.md`. Alertes de bugs : `ALERTES-ET-ERREURS.md`. Affiches : `AFFICHES-PUBLICITAIRES.md`. Sauvegardes, domaine : `SAUVEGARDE-ET-SECURITE.md`. Tests à la main : `TEST-REEL.md`. Contrôles : `CHECKLIST-14-MODULES-PLUS-AUDIT.md`, `AUDIT-SECURITE.md`, `VERCEL-ENV-ET-WEBHOOKS.md`, `TEST-VENTE.md`.

## Déployer sur Vercel pas à pas (nouvelle installation)
1. **GitHub** : créez un dépôt privé vide, puis envoyez-y le **contenu** du projet (dossiers `src`, `supabase`, `public`, `scripts` et les fichiers à la racine). Ne mettez jamais `.env.local` ni `node_modules`.
2. **Supabase** : nouveau projet > SQL Editor > collez tout `supabase/schema.sql` > Run (« Success »). Collez ensuite `supabase/verifier-installation.sql` > Run : toutes les lignes doivent afficher « OK ». Authentication > URL Configuration : *Site URL* = l'adresse de votre site, *Redirect URL* = `https://VOTRE-SITE/auth/callback`.
3. **Vercel** : Add New > Project > importez le dépôt (Next.js détecté). Avant de cliquer sur Deploy, ajoutez les variables de `.env.example` (au minimum `NEXT_PUBLIC_APP_URL`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `FAPSHI_ENV`, `FAPSHI_API_USER`, `FAPSHI_API_KEY`, `FAPSHI_WEBHOOK_SECRET`, `CRON_SECRET`). Puis **Deploy**.
4. **Webhooks** : chez Fapshi, saisissez `https://VOTRE-SITE/api/webhooks/fapshi` (autres passerelles : `VERCEL-ENV-ET-WEBHOOKS.md`).
5. **Devenir admin** : créez votre compte sur le site, puis dans Supabase : `update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'VOTRE_EMAIL');`
6. **Tester** : `TEST-REEL.md` en mode `FAPSHI_ENV=sandbox`, puis passez à `live`.
Détail complet : `README-DEPLOIEMENT.md`. Si le build Vercel échoue, copiez la ligne d'erreur exacte du journal de build.

## Répartition automatique d'une vente (FCFA entiers, calculée dans la base, jamais dans le navigateur)

- **Commission plateforme** (réglée dans `/admin/commissions`) : **0 % pendant les 30 jours de lancement**, puis **8 %** automatiquement (les frais Fapshi de 3 % sont payés par la plateforme : à 3 % de commission on ne gagne rien) ; vendeurs Pro **5 %**. L'admin peut tout changer à tout moment (maximum 10 %).
- **Commission affilié** : 1 % à 50 % choisie par le vendeur avec un curseur (**20 % par défaut**).
- Le vendeur reçoit le reste. Arrondi vers le bas, le reste va au vendeur. Livraison : 100 % au vendeur.
- Exemple sur 10 000 FCFA avec affilié 20 % pendant le lancement : **plateforme 0 · affilié 2 000 · vendeur 8 000**.
- Grossistes (module 7) : « Commander et payer en sécurité » (V4.0) : prix de gros par palier calculé par la base, paiement en ligne obligatoire, argent gardé comme tout produit physique ; 3 % plateforme (0 % en lancement ou compte exempté) / 5 % affilié (si affilié) / reste au grossiste.
- Fonctions : `compute_split_for` et `effective_platform_percent` (SQL), miroir `src/lib/calculateCommission.ts` (`calculateSplit`).

**Délais de libération des fonds (dernière décision)** : produit digital = **24 h** après le paiement ; produit physique = à la confirmation de réception par l'acheteur, ou automatiquement **7 jours** après « Livrée » s'il n'y a pas de litige, mais **jamais avant 7 jours après le paiement** (protection anti-fraude, réglable dans Admin > Anti-fraude). Le solde reste « en attente » jusque-là. Les retraits sont validés à la main dans `/admin/payouts`.

## Vérifier

`npm install && npm run typecheck && npm run build`. Tests SQL (16 suites, 802 vérifications, 0 échec) : `supabase/tests/` (voir `supabase/tests/00_supabase_stubs.sql` : fausse couche Supabase pour tester sur un Postgres ordinaire).

## Nouveautés (partage, boost, boutique)

- **Base déjà créée ?** Relancez simplement tout `supabase/schema.sql` dans le SQL Editor (il est rejouable) : il ajoute les nouvelles colonnes, tables `product_boosts` et `product_shares`, les vues d'activité et les nouveaux droits.
- **Contact vendeur** : le numéro WhatsApp / appel / email n'est jamais envoyé avant paiement (colonnes `products.whatsapp_seller`, `booking_url`, `delivery_notes` et profil non lisibles par le public). Il apparaît après paiement d'un produit **physique** uniquement. Aucun numéro pour le digital.
- **Boost** : 3 jours = 1 000 FCFA (badge « À la une »), 7 jours = 2 500 FCFA (badge « Populaire »), payés via Fapshi (même webhook). Prix modifiables dans `src/lib/boost.ts`.
- **Alertes d'inactivité** : bandeau orange dans le dashboard + email (tâche planifiée quotidienne, 1 email max par produit tous les 7 jours).
- **Boutique** : `/boutique/<adresse>` ; personnalisation dans « Ma boutique » ; profil dans « Mon profil ».

## Version 3 : confiance, recherche, paiement à la livraison, admin

**Important : ré-exécutez `supabase/schema.sql` en entier dans le SQL Editor de Supabase** (il est idempotent). Tous vos produits existants restent visibles (ils sont marqués « approuvés » à la migration). Ensuite, donnez-vous le rôle admin si ce n'est pas déjà fait :
`update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'votre@email');`

- **Avis** : après « J'ai reçu mon produit », l'acheteur note de 1 à 5 étoiles + commentaire (page « Mes achats »). Moyenne et nombre d'avis sur chaque produit et chaque boutique.
- **Vendeur Vérifié** (coche bleue) : activé/désactivé par l'admin dans `/admin/sellers`.
- **« Vendeur peu fiable »** : moyenne < 2 étoiles avec au moins 3 avis (réglable dans `src/lib/trust.ts`).
- **Recherche & filtres** (accueil) : nom, catégorie, ville, prix min/max, type, tri (plus récent, prix croissant, prix décroissant, mieux notés), combinables. Aucun filtre actif = section « À la une » affichée.
- **Paiement** : Orange Money et MTN MoMo via Fapshi. **Fapshi ne gère que le Mobile Money (pas les cartes bancaires)** ; pour des cartes il faudrait ajouter une autre passerelle.
- **Paiement à la livraison** (produits physiques uniquement, refusé par la base pour le digital) : statut « En attente de livraison - Paiement cash ». Le vendeur clique « Cash encaissé » ; la commission KDDF en vigueur est enregistrée (`wallets.commission_due`) et déduite de son prochain retrait. Pas d'affiliation sur ces commandes ; le stock est réservé à la commande (le vendeur peut annuler).
- **Livraison** : « Je viens récupérer » (gratuit), « Livraison à domicile à Douala », « Envoi par bus / expédition ». Les deux prix se règlent dans Mon profil et s'appliquent à tous les produits physiques du vendeur. Total = prix + livraison.
- **Admin** (`/admin`, 404 pour les autres) : tableau de bord, `/admin/sellers` (voir, vérifier, bloquer), `/admin/orders` (commandes, litiges, remboursements), `/admin/withdrawals` (Approuver / Refuser, montant net après commission cash), `/admin/products` (modération : tout nouveau produit attend l'approbation).

## Dépannage : « Could not find the table 'public.products' » / « Bucket not found »

Ces deux messages signifient que `supabase/schema.sql` n'a pas été exécuté en entier dans VOTRE projet Supabase (le SQL Editor annule tout si une seule ligne échoue).
1. Supabase > SQL Editor > New query > collez TOUT `supabase/schema.sql` > Run. S'il affiche une erreur rouge, copiez-la : rien n'a été créé tant qu'elle n'est pas corrigée.
2. Collez ensuite `supabase/verifier-installation.sql` > Run : toutes les lignes doivent afficher « OK ».
3. Vérifiez que `NEXT_PUBLIC_SUPABASE_URL` sur Vercel est bien l'URL du projet où vous avez exécuté le script (puis Redeploy).
4. Si seul le bucket manque : Supabase > Storage > New bucket : « covers » (Public) et « deliverables » (Privé).

## Messages d'erreur « Cause + Solution »
Toutes les erreurs affichées à l'utilisateur disent la cause exacte puis une solution. Elles sont centralisées dans `src/lib/errors.ts` (ajoutez un cas dans `DB` ou `PATTERNS` pour en expliquer une nouvelle). Les boutons admin/vendeur qui échouent renvoient vers la page avec `?erreur=<code>` (bandeau `FlashError`), et `src/app/error.tsx` couvre les pages qui plantent.


## Paiement universel (cartes, Mobile Money élargi, crypto) et retraits

**Encaisser (acheteurs)** — l'acheteur choisit son moyen au paiement. Fapshi (MTN/Orange Cameroun) reste toujours actif ; les autres n'apparaissent que si leurs clés sont dans Vercel > Environment Variables (puis Redeploy) :

| Option | Variables | Webhook à configurer chez le fournisseur |
|---|---|---|
| Flutterwave (Visa, Mastercard, Amex, Wave, Moov, M-Pesa, Orange, MTN…) | `FLW_SECRET_KEY`, `FLW_SECRET_HASH` | `https://VOTRE-SITE/api/webhook/flutterwave` (Secret hash = `FLW_SECRET_HASH`) |
| Crypto via NOWPayments (USDT, BTC, ETH…) | `NOWPAYMENTS_API_KEY`, `NOWPAYMENTS_IPN_SECRET`, `NOWPAYMENTS_ENV` | IPN secret dans le dashboard ; l'URL `/api/webhook/crypto` est envoyée à chaque facture |

Notes : les prix restent en FCFA. Pour la crypto, le montant est converti en EUR avec la parité fixe 1 EUR = 655,957 FCFA, puis NOWPayments le convertit en crypto. La crypto est confirmée uniquement par l'IPN signé (pas de rattrapage automatique). PayPal est inclus (voir plus bas). Apple Pay et Google Pay ne sont pas inclus (Stripe n'accepte pas les marchands camerounais).

**Retirer (vendeurs)** — MTN MoMo, Orange Money, Wave, Moov Money, M-Pesa, virement bancaire, PayPal, crypto USDT/BTC. L'administrateur paie manuellement depuis /admin/withdrawals puis marque « payé ». Relancez `supabase/schema.sql` dans le SQL Editor pour activer les nouveaux moyens.


## Aide & contact (support)
Un bouton « 💬 Aide » est visible sur tout le site : il mène à `/support` (message + jusqu'à 3 captures d'écran, même sans compte). La page d'erreur « Oups » propose aussi « Signaler ce problème » avec la référence de l'erreur. Les messages arrivent dans **/admin/support** (captures visibles, bouton « Marquer comme traité »). Variables facultatives : `SUPPORT_EMAIL` (alerte par email, nécessite Resend), `NEXT_PUBLIC_SUPPORT_WHATSAPP` (ex 237690000000) et `NEXT_PUBLIC_SUPPORT_EMAIL` (affichés sur /support). Côté base : section 23 de `supabase/schema.sql` (table `support_messages` + bucket privé `support`).


## Commissions flexibles (admin) — ACTIVÉES PAR DÉFAUT
Page **/admin/commissions** : à l'installation, le mode lancement est actif (0 % pendant 30 jours), puis 8 % automatiquement. Vous pouvez à tout moment choisir 0 % (relance un lancement de 30 jours), 5 %, 8 %, 10 % ou un taux libre (maximum 10 %). Dans la même page, la section « Tarifs Pro et frais de retrait » règle la commission Pro (5 % au départ), le prix de l'abonnement Pro (3 000 FCFA), les frais de retrait (1,5 %) et leur minimum (200 FCFA). Le changement s'applique aux NOUVELLES ventes, sans redéployer, et chaque changement est tracé dans `commission_history`. Les vendeurs choisissent la commission d'affilié (curseur 1–50 %, 20 % par défaut). Garde-fous dans la base : plateforme ≤ 10 %, affilié ≤ 50 %. L'ancien calcul 5 % / 8 % / 10 % a été supprimé. Base : section 24 de `supabase/schema.sql`.

## Anti-fraude affiliation
Fichier SQL : `supabase/schema.sql`, section 25. Page admin : **/admin/fraude**.
- Règle 1 : affilié = acheteur (même compte, **même email — même avec les astuces Gmail —, même téléphone**) → commission 0, vente normale, journal score 100.
- Règle 2 : vendeur = affilié (même compte, WhatsApp/téléphone) → commission 0.
- Règle 3 : comptes multiples (même téléphone > 2 : +40 · même IP > 3 comptes en 24 h : +30 · > 5 commandes même acheteur/vendeur en 24 h : +30). Score ≥ 70 → vente livrée, commission « en attente manuelle ».
- Règle 4 : vélocité (> 10 ventes/h, > 30 ventes/24 h avec 80 % de comptes neufs, vendeur de 0 à 50 ventes avec le même affilié) → commissions retenues + alerte admin.
- Règle 5 : fonds des produits **physiques** retenus 7 jours minimum (les produits **digitaux** : 24 h) ; remboursement/litige dans ce délai = commission annulée ; 3 alertes en 30 jours = retraits suspendus (« en cours de vérification ») jusqu'au déblocage par l'admin.
- Interrupteur : bouton Activer/Désactiver sur /admin/fraude. Désactivé = aucune retenue supplémentaire (digital : 24 h ; physique : à la confirmation de réception).
- En cas de panne de l'anti-fraude, la vente passe toujours. Le code serveur peut aussi appeler `checkFraud()` (`src/lib/antiFraud.ts`).
- Limites : Fapshi ne donne pas le numéro MoMo du payeur ; l'IP d'un compte est enregistrée quand il ouvre sa page « Mes gains ».

## Grossistes, international, litiges, panier
Voir `CHECKLIST-14-MODULES-PLUS-AUDIT.md` (état de chaque module et fichiers). SQL : `supabase/schema.sql`, section 26.

## Correctifs de l'audit de sécurité (sections 27 à 29 de schema.sql ; détail dans `AUDIT-SECURITE.md`)
- **Critique** : les vues publiques (`public_profiles`, `seller_public_stats`…) n'acceptent plus aucune écriture (un visiteur pouvait supprimer des profils) ; `TRUNCATE`/`REFERENCES`/`TRIGGER` retirés ; nouvelles tables fermées par défaut ; fonctions internes anti-fraude non appelables depuis le navigateur ; un vendeur ne peut référencer que SES fichiers de stockage.
- **Anti-abus** : limitation de débit atomique en base (`rate_limits`) sur le paiement, le support, les statistiques, le partage, les clics d'affiliation et les téléchargements ; compteur de téléchargements par achat (200 maximum).
- **Emails** : un seul expéditeur (`src/lib/mailer.ts`), modèles dans `src/lib/emailTemplates.ts`, file d'attente avec réessais automatiques (`email_outbox`, rejouée par la tâche planifiée).
- **Paiements** : « Mes achats » rattrape les paiements dont le webhook est manquant ; les webhooks refusent les corps trop gros et ne journalisent plus de données personnelles.
- **Comptes** : pages « Mot de passe oublié » (`/mot-de-passe-oublie`, `/reset-password`), liens d'email expirés gérés proprement.
- **Anti-fraude** : l'IP du compte est enregistrée par le SERVEUR (`/api/antifraud/ip`), et non plus fournie par le navigateur.
- **Mobile/PWA** : champs 16 px (pas de zoom iPhone), zones tactiles 44 px, encoche (safe-area), mouvement réduit, service worker v3, manifeste complété, en-têtes de sécurité HTTP.
- **Build** : `next ~14.2.25` (correctif CVE-2025-29927), `server-only` sur tout le code serveur, ESLint non requis au build.
- Tests : `supabase/tests/60_securite.sql` (50 vérifications).

## Version 3.1 : achat sans compte (Guest Checkout)

- **Produits physiques** : achat SANS compte. Formulaire : Nom complet + Numéro WhatsApp/MoMo + Ville + Quartier. Pas d'email, pas de mot de passe. Un « compte invité » invisible (table `guest_accounts`, clé = 9 derniers chiffres du numéro) est créé en arrière-plan ; ce n'est PAS un utilisateur Supabase Auth.
- **Produits digitaux** : compte obligatoire (« Pour les produits digitaux, crée un compte gratuit en 30 secondes pour recevoir ton fichier »).
- **Code `KDDF-XXXX`** par commande physique (`transactions.order_code`, unique, 4 chiffres ; 5 ou 6 seulement si les 4 chiffres sont épuisés).
- **`/suivre-commande`** (public) : Numéro + Code → En attente → En livraison → Livré → Terminé ; « J'ai bien reçu » ; « Ouvrir un litige » avec jusqu'à 3 photos. Limité à 10 essais / 10 min par numéro et 20 / 10 min par IP (anti-devinette).
- **Litiges** : `/admin/litiges` affiche Nom + Numéro + Code + preuve de paiement Mobile Money (numéro déclaré, montant, ID Fapshi, moyen, date).
- **Anti-fraude par téléphone** : numéro acheteur = numéro de l'affilié → commission 0 ; plus de 5 commandes en 1 h avec le même numéro → bloqué ; si l'anti-fraude plante → la vente est autorisée.
- **Affilié** : l'acheteur sans compte qui arrive par un lien d'affilié (cookie 30 jours) donne la commission ; l'affilié a besoin d'un compte pour la voir.
- Adresse email technique `invite-XXXXXXXXX@example.com` donnée aux passerelles de paiement qui exigent un email ; jamais utilisée pour écrire au client (le mailer l'ignore).

## Version 3.2 : PayPal et devises en temps réel

- **PayPal** (Orders v2) : bouton « Payer X avec PayPal » dans le paiement ; n'apparaît que si `PAYPAL_CLIENT_ID` et `PAYPAL_CLIENT_SECRET` sont définis. PayPal n'accepte pas le FCFA : le client paie en **EUR, USD, GBP ou CAD** (choix dans le paiement).
- **Conversion** : le prix reste en FCFA entiers dans la base (comptabilité, commissions, portefeuilles inchangés). Au clic, le montant en devise est calculé au taux du moment, **verrouillé** dans `transactions` (`pay_currency`, `pay_amount`, `fx_rate`, `fx_source`, `fx_locked_at`) et affiché avant validation. Le FCFA est arrimé à l'euro (1 € = 655,957 FCFA) ; les autres devises viennent d'open.er-api.com, puis frankfurter.dev (BCE), puis d'une copie en base (48 h maximum) ; sans taux frais, PayPal est suspendu (jamais de montant deviné).
- **Sécurité** : le montant, la devise et la référence de commande reçus de PayPal doivent correspondre **exactement** à ce qui a été verrouillé, sinon la vente passe « à vérifier » sans aucun crédit. Webhook `/api/webhooks/paypal` à signature vérifiée auprès de PayPal ; la page de téléchargement et la tâche planifiée valident aussi le paiement (filets de sécurité).
- **Fichiers** : `src/lib/{fxCore,fx,paypalCore,paypal}.ts`, `src/lib/useFx.ts`, `src/components/FxPanel.tsx`, `src/app/api/fx/route.ts`, `src/app/api/webhook/paypal/route.ts`, `supabase/schema.sql` §31, tests `supabase/tests/90_paypal_fx.sql` (25 vérifications).
- Les taux gratuits sont actualisés environ une fois par jour à la source (cache 30 min chez nous) : ce n'est pas du « à la seconde ».
- **Mise à jour depuis V3.1** : remplacez les fichiers du dépôt par ceux de ce ZIP, rejouez `supabase/schema.sql` dans Supabase (sans risque : rejouable), ajoutez les variables PayPal (voir `VERCEL-ENV-ET-WEBHOOKS.md`), créez le webhook PayPal, puis *Redeploy*.


## V3.3 à V3.7 : revenus, tarifs modifiables, villes, retrait express, loupe et cloche
Frais de retrait, retrait express, abonnement Pro, compte exempté, boosts 14/30 jours, bannières sponsorisées, services payants, 8 % / 5 % modifiables, liste de villes, quantité jusqu'à 1000, candidature grossiste réparée, loupe de recherche (Ctrl+K) et cloche d'annonces : voir `REVENUS-ET-FRAIS.md` et `RECHERCHE-ET-CLOCHE.md`. Les anciennes migrations SQL sont rangées dans `supabase/historique/` (déjà incluses dans `schema.sql`).

## V3.8 : projet final
Frais de service payés par l'acheteur selon le moyen de paiement ; limite de produits du plan gratuit (10) ; notifications personnelles dans la cloche ; journal des erreurs (Admin > Erreurs) ; suppression de compte et export des données ; exports CSV ; pages légales (`/conditions`, `/confidentialite`, `/remboursement`, `/mentions-legales`, informations d'éditeur réglables par variables Vercel) ; `robots.txt`, `sitemap.xml`, pages 404 et erreur globale ; contrôle d'installation étendu. Installation : `MISE-A-JOUR-V3-8.md`.

## V3.9 : confiance et protection
- **Vérification d'identité des vendeurs** : carte (recto + verso) et vidéo/photo avec la carte, contrôlées par vous dans Admin > Identités ; sans validation, un vendeur ne peut pas publier (brouillons possibles).
- **Protection 2FA facultative** (`/securite`) : code à 6 chiffres à la connexion ; retraits et actions admin protégés jusque dans la base.
- **Téléphone confirmé par SMS** (facultatif, fournisseur SMS à configurer).
- **Alertes de bugs** : cloche + email avec notice « que faire » (Admin > Erreurs).
- **Guide de bienvenue** : 8 affiches affichées au premier passage (site, puis application installée), bouton Quitter toujours visible.
- **16 affiches publicitaires** prêtes à publier (zip séparé `kddf-affiches-publicitaires.zip`).
Installation : `MISE-A-JOUR-V3-9.md`.

## V4.0 : paiement des ventes en gros
Commande de gros payée sur le site (compte acheteur obligatoire, 10 à 1 000 pièces, paiement en ligne, argent gardé, litige possible), commission 3 % / 5 %, badge GROS côté vendeur. Installation : `MISE-A-JOUR-V4-0.md`.

## Ce qui n'est volontairement PAS dans le projet (et pourquoi)
- **Apple Pay / Google Pay** : non implémentés. Ils exigent un fournisseur qui les active pour votre pays (ou un compte Stripe), ce que vos passerelles actuelles ne proposent pas. Rien n'est affiché à l'acheteur, donc aucune fausse promesse.
- **Stripe / FedaPay** (stack du tout premier cahier des charges) : remplacés par Fapshi + Flutterwave + NOWPayments + PayPal, mieux adaptés au Cameroun.
- **Retraits automatiques** : déconseillés au démarrage (fraude) ; vous validez à la main.
- **Codes promo** : volontairement reportés. Ils modifient le calcul du prix, c'est-à-dire le cœur du paiement ; sans pouvoir tester un vrai paiement complet ici, le risque d'erreur d'argent dépasse le gain. À ajouter après vos premières ventes réelles.
- **NextAuth** : inutile, l'authentification est assurée par Supabase Auth.
- **Reconnaissance faciale automatique de la carte d'identité** : service payant et complexe ; la V3.9 repose sur votre contrôle humain (comparaison vidéo / carte). À ajouter plus tard si le volume de vendeurs le justifie.
- **SMS obligatoires** : désactivés par défaut, car ils coûtent de l'argent et demandent un fournisseur SMS.

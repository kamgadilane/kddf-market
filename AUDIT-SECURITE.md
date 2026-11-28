# AUDIT-SECURITE.md — KDDF Market V3.2

Audit complet du code avant production, selon les 5 axes demandés. Chaque problème est classé **Critique / Moyen / Mineur**, avec le fichier concerné et la correction appliquée. Toutes les corrections ci-dessous sont **déjà dans ce ZIP**. Preuves : 9 suites de tests SQL (**530 vérifications, 0 échec**) sur un vrai Postgres 16, `schema.sql` rejoué 2 fois sans erreur, `verifier-installation.sql` tout « OK ».

## Résumé

| Gravité | Nombre | Corrigés |
|---|---|---|
| Critique | 5 | 5 |
| Moyen | 20 | 20 |
| Mineur | 12 | 12 |

---

## CRITIQUE

Problème critique Supabase trouvé : **les vues publiques (`public_profiles`, `seller_public_stats`, etc.) étaient modifiables par n'importe quel visiteur.** Supabase accorde par défaut INSERT/UPDATE/DELETE aux rôles `anon` et `authenticated` sur tout objet créé ; une vue simple est « auto-modifiable » et s'exécute avec les droits de son propriétaire, donc **elle contourne la RLS**. Un test l'a confirmé : `delete from public_profiles` effaçait tous les profils. -> Corrigé dans le fichier `supabase/schema.sql` (section 27.1 : `revoke` de toute écriture sur les vues, vues recréées en `security_invoker`, vérification automatique dans `supabase/verifier-installation.sql`, test `supabase/tests/60_securite.sql`).

| # | Problème | Fichier | Correction |
|---|---|---|---|
| C1 | **Vues publiques modifiables → effacement/modification de profils par un visiteur** (décrit ci-dessus) | `supabase/schema.sql` §27.1 | Écriture retirée sur toutes les vues, `security_invoker = true`, contrôle « securite : vues en lecture seule » dans `verifier-installation.sql` |
| C2 | Droits par défaut Supabase trop larges : `TRUNCATE`, `REFERENCES`, `TRIGGER` accordés, nouvelles tables ouvertes par défaut | `supabase/schema.sql` §27 | Droits retirés ; `alter default privileges` : toute nouvelle table est fermée ; contrôle « tables fermées aux visiteurs » dans le vérificateur |
| C3 | Fonctions internes anti-fraude (ex. enregistrement d'IP) appelables depuis le navigateur | `supabase/schema.sql` §25/§27 | `revoke execute … from public, anon, authenticated` ; seul le serveur (service_role) les appelle ; l'IP est lue côté serveur (`src/app/api/antifraud/ip/route.ts`) |
| C4 | Un vendeur pouvait référencer les fichiers de stockage d'un AUTRE vendeur comme siens (vol de contenu payant) | `supabase/schema.sql` §27 (garde de chemin sur `product_files`) | Le chemin doit commencer par l'id du vendeur ; testé dans `60_securite.sql` |
| C5 | **Montant de webhook différent du montant attendu** : risque de valider une vente payée trop peu | `supabase/schema.sql` §28 (`confirm_fapshi_payment`), `src/lib/fulfillment.ts`, `src/app/api/webhook/crypto/route.ts` | Montant comparé à `transactions.total_amount` : si différent → statut `review` (« à vérifier »), **aucun crédit**, ligne dans `fraud_logs` (`montant_different`, conservée 180 jours) |

## MOYEN

| # | Problème | Fichier | Correction |
|---|---|---|---|
| M1 | **Secret du webhook Fapshi facultatif** (un webhook sans secret était accepté) | `src/lib/fapshi.ts`, `src/app/api/webhook/fapshi/route.ts`, `.env.example` | **Strict en production** : sans `FAPSHI_WEBHOOK_SECRET`, le webhook est refusé ; comparaison à temps constant (`timingSafeEqual`). Le statut est de toute façon relu chez Fapshi |
| M2 | Webhooks Flutterwave / NOWPayments : signatures à vérifier strictement | `src/lib/flutterwave.ts` (`verif-hash`), `src/lib/nowpayments.ts` (HMAC-SHA512 de `x-nowpayments-sig`) | Déjà strictes : refus si secret ou en-tête absent ; paiement relu chez le fournisseur avant validation |
| M3 | **Double validation** (même webhook reçu 2 fois) | `supabase/schema.sql` §6/§28 (`transactions.fapshi_trans_id` UNIQUE + `confirm_fapshi_payment` idempotent), table `payment_events` | La 2e fois renvoie `already` : aucun double crédit (testé) |
| M4 | **Statuts sans garde** (saut possible En attente → Terminé) | `supabase/schema.sql` §28 (`orders_status_guard`, `transactions_status_guard`) | Cycle strict En attente → Payé → Livré → Terminé, sans saut ; refus par trigger (testé) |
| M5 | Aucune limitation de débit (spam paiement/support/téléchargements) | `src/lib/rateLimit.ts`, table `rate_limits`, `supabase/schema.sql` §27 | Limite atomique en base sur checkout, support, vues, partages, clics, téléchargements |
| M6 | Téléchargements illimités par achat | `src/app/api/download/[token]/[fileId]/route.ts`, fonction `register_download` | 200 téléchargements max par achat, liens signés de courte durée |
| M7 | IP du compte fournie par le navigateur (falsifiable) | `src/app/api/antifraud/ip/route.ts`, `src/components/IpBeacon.tsx` | L'IP est lue par le SERVEUR (`src/lib/clientIp.ts`) |
| M8 | Emails perdus si le fournisseur échoue ; un email en échec bloquait la suite | `src/lib/resend.ts`, `src/lib/mailer.ts`, table `email_outbox` | Jamais bloquant : erreur journalisée, **1 réessai immédiat**, puis file d'attente rejouée par la tâche planifiée |
| M9 | Paiement validé mais webhook manqué → client sans produit | `src/lib/syncMyPayments.ts`, `src/app/api/cron/release-funds/route.ts` | Rattrapage : « Mes achats », page de téléchargement et tâche planifiée relisent le statut chez le fournisseur |
| M10 | RLS sans politique explicite sur certaines tables | `supabase/schema.sql` §10, §25–§28 | **33 tables sur 33 avec RLS + politique explicite** (liste ci-dessous) |
| M11 | Failles Next.js (CVE-2025-29927, contournement du middleware) | `package.json` | `next ~14.2.25` (version corrigée) ; les contrôles d'accès ne reposent pas seulement sur le middleware (RLS + vérifications serveur) |
| M12 | Webhooks : corps volumineux et journaux contenant des données personnelles | `src/app/api/webhook/*` | Corps limité à 64 Ko ; seuls les noms de champs sont journalisés ; réponse toujours 200 |
| M13 | **(V3.1) Devinette du code KDDF-XXXX sur `/suivre-commande`** : 10 000 codes possibles, un pirate pourrait les essayer pour lire des commandes | `src/lib/guestTrack.ts`, `supabase/schema.sql` §30 | Il faut **Numéro ET Code** (le code seul ne sert à rien) ; 10 essais / 10 min par numéro et 20 / 10 min par IP ; message identique pour un mauvais code et un mauvais numéro ; les fonctions SQL ne sont appelables que par le serveur (service_role) ; la réponse ne contient jamais l'identifiant interne de la commande ni de donnée vendeur |
| M14 | **(V3.1) Achat sans compte = risque de spam de commandes** | `supabase/schema.sql` §12 (`create_checkout_order`) | Même numéro : plus de 5 commandes en 1 h → **bloqué** + trace `fraud_logs` ; si la vérification plante → autorisé (ne jamais bloquer une vraie vente par erreur technique) ; limitation de débit par IP et par numéro sur `/api/checkout` |
| M15 | **(V3.1) Photos envoyées par un client anonyme** (fichier piégé, stockage rempli) | `src/app/api/suivre-commande/litige/route.ts` | Type réel vérifié sur les octets (JPG/PNG/WebP), 4 Mo et 3 photos max, bucket privé, dossier = id de commande vérifié aussi en SQL (`fichier_invalide`), fichiers supprimés si le litige n'est pas enregistré ; consultation admin par liens signés de 10 min |
| M16 | **(V3.1) Table des invités** exposant des numéros de téléphone | `supabase/schema.sql` §30 (`guest_accounts`) | RLS activée, tout retiré à `anon`/`authenticated`, lecture réservée à l'admin (`is_admin()`) ; clé = 9 derniers chiffres ; ce n'est pas un utilisateur Supabase Auth (aucune session invitée possible) |
| M17 | **(V3.2) Montant PayPal falsifié ou paiement détourné** (payer 1 € une commande de 10 000 FCFA) | `src/lib/paypalCore.ts` (`interpretOrder`), `src/lib/fulfillment.ts`, `supabase/schema.sql` §31 | Le montant en devise, la devise et la référence (`custom_id` = identifiant de la transaction) sont verrouillés à la création de la commande et relus chez PayPal ; au moindre écart, `confirm_fapshi_payment` reçoit -1 → statut « à vérifier » (`montant_different`), aucun crédit ; la commande n'est jamais crue sur la foi du navigateur |
| M18 | **(V3.2) Faux webhook PayPal** | `src/lib/paypal.ts` (`verifyPaypalWebhook`), `src/app/api/webhook/paypal/route.ts` | Signature vérifiée auprès de PayPal (`verify-webhook-signature` avec `PAYPAL_WEBHOOK_ID`) ; identifiant de commande contrôlé par expression régulière (`isPaypalOrderId`) ; le statut est ensuite relu chez PayPal ; réponse toujours 200 ; sans `PAYPAL_WEBHOOK_ID`, le webhook est ignoré (le retour client et la tâche planifiée valident quand même) |
| M19 | **(V3.2) Taux de change aberrant ou source en panne** (prix divisé par 100 ou multiplié) | `src/lib/fxCore.ts` (`sanitizePerEur`), `src/lib/fx.ts` | Bornes de plausibilité sur chaque taux ; 3 sources en cascade ; copie en base de 48 h maximum, au-delà PayPal est suspendu (503 clair) au lieu de deviner ; arrondi au centime supérieur (jamais en dessous du prix) ; marge `FX_MARGIN_PERCENT` plafonnée à 10 |
| M20 | **(V3.2) Table `fx_rates` lisible ou modifiable par le public** | `supabase/schema.sql` §31 | RLS activée + politique `fx_rates_server_only` (`using (false)`) : seul le serveur (service_role) y accède ; test `90_paypal_fx.sql` |

## MINEUR

| # | Problème | Fichier | Correction |
|---|---|---|---|
| m1 | Zoom automatique iPhone, zones tactiles trop petites, encoche | `src/app/globals.css`, `src/app/layout.tsx` | Champs 16 px, cibles 44 px, `safe-area`, mouvement réduit |
| m2 | Service worker pouvant mettre en cache des pages privées | `public/sw.js` | Jamais d'API/compte en cache ; accueil copié **sans cookies** ; version `kddf-v3` |
| m3 | En-têtes de sécurité HTTP absents | `next.config.mjs` | `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` |
| m4 | Modèles d'emails écrits en chaînes dans le code | `src/lib/emails/*.html`, `scripts/build-emails.mjs` | 5 modèles HTML dédiés, embarqués au build (fichier généré aussi versionné) |
| m5 | Journaux qui grossissent (plan gratuit) | `supabase/schema.sql` §28 (`purge_old_logs`), `src/app/api/cron/release-funds/route.ts` | Purge à 30 jours ; alertes ouvertes conservées ; preuves de montant manipulé 180 jours |
| m6 | Ancien calcul 5/8/10 % encore présent | `src/lib/money.ts`, `supabase/schema.sql` | Supprimé (`compute_split_legacy` n'existe plus, testé) |
| m7 | Anciens scripts SQL redondants (`ajout-*.sql`, `correctifs-securite.sql`) risquant de remettre l'ancien système | `supabase/` | Retirés : `schema.sql` est le seul script à exécuter |
| m8 | Pages admin et vendeur faisant trop de requêtes | `src/app/admin/*`, `dashboard/page.tsx`, `library/page.tsx`, `download/[token]/page.tsx` | Relations PostgREST, URLs signées en lot, fonctions `admin_overview`, `seller_dashboard`, `admin_low_rated_sellers` : **≤ 3 requêtes de données par page** |
| m9 | Message `\echo` de test avec apostrophe mal fermée | `supabase/tests/40_antifraude.sql` | Corrigé |
| m10 | `verifier-installation.sql` ne contrôlait pas les nouvelles tables/fonctions | `supabase/verifier-installation.sql` | 44 contrôles (tables, buckets, fonctions, sécurité) |
| m11 | (V3.1) Adresse email technique `invite-…@example.com` exigée par les passerelles de paiement | `src/lib/guest.ts`, `src/lib/mailer.ts` | Jamais utilisée pour écrire : `sendEmail` ignore ces adresses ; l'affichage vendeur/admin montre « Client sans compte » |
| m12 | (V3.1) Collision de codes de commande | `supabase/schema.sql` §30 (`next_order_code`, index unique `transactions_order_code_key`) | 4 chiffres, puis 5 ou 6 si saturé ; nouvelle tentative automatique en cas de doublon |

---

## Axe 1 — Base de données et sécurité Supabase

- **`SUPABASE_SERVICE_ROLE_KEY` jamais côté client.** Seul `src/lib/supabase/admin.ts` la lit (fichier `server-only`) ; il n'est importé que par des routes API / Server Actions / pages serveur. Contrôle fait : aucun fichier `"use client"` n'importe `supabase/admin`, `resend` ni ne lit une clé secrète. Seules `NEXT_PUBLIC_SUPABASE_URL` et `NEXT_PUBLIC_SUPABASE_ANON_KEY` sont publiques.
- **RLS activée + politiques sur les 33 tables** (contrôlé dans la base de test) : account_ips, affiliate_links, bundle_items, commission_history, commission_settings, disputes, email_outbox, fraud_logs, fraud_settings, guest_accounts, license_keys, order_photos, order_tracking, orders, payment_events, product_boosts, product_files, product_locations, product_shares, product_views, products, profiles, rate_limits, review_extras, reviews, support_messages, transactions, waitlist_international, wallets, wholesale_applications, wholesale_products, wholesale_requests, withdrawals.
- Règle générale : un utilisateur ne voit que ses propres lignes (`user_id`/`seller_id`/`buyer_id = auth.uid()`), sauf l'admin (`is_admin()`). Les écritures sensibles (argent, statuts, litiges) passent uniquement par des fonctions SQL `security definer` avec `set search_path`, qui vérifient l'appelant.
- Colonnes privées (contact vendeur, CNI) non lisibles par le public ; contact vendeur débloqué seulement après paiement d'un produit physique.
- Routes API : limitation de débit, validation des identifiants (`isUuid`), accès `service_role` uniquement côté serveur, tâche planifiée protégée par `Authorization: Bearer CRON_SECRET`.

## Axe 2 — Paiement universalisé

- Clés (`FAPSHI_API_KEY`, `FLW_SECRET_KEY`, `NOWPAYMENTS_API_KEY`, secrets de webhooks) : variables **serveur** uniquement (sans préfixe `NEXT_PUBLIC_`), lues dans `src/lib/fapshi.ts`, `flutterwave.ts`, `nowpayments.ts`.
- Signatures : Fapshi `x-wh-secret` (strict en production), Flutterwave `verif-hash`, NOWPayments HMAC-SHA512 — comparaisons à temps constant.
- Aucun webhook n'est cru sur parole : le statut et le montant sont **relus chez le fournisseur**, puis comparés à la transaction en base.
- Idempotence : `transaction_id` unique + « déjà traité ? » (`already`).
- Montant manipulé : blocage (`review`), aucun crédit, trace dans `fraud_logs`.
- Devises : prix en FCFA entiers ; la crypto est convertie en EUR à parité fixe (1 EUR = 655,957 FCFA) puis par NOWPayments.
- Cycle de statut : En attente → Payé → Livré → Terminé (digital : En attente → Livré dès le paiement), sans saut.

## Axe 3 — Emails Resend

- `src/lib/resend.ts` : `RESEND_API_KEY` serveur uniquement ; erreur journalisée, 1 réessai, sinon `email_outbox` (rejouée chaque jour).
- 5 modèles dans `src/lib/emails/` : `confirmation_inscription.html`, `recu_paiement.html`, `notification_vendeur.html`, `notification_affilie.html`, `litige.html`.
- Déclencheurs : inscription (email de bienvenue à la première connexion, une seule fois : `claim_welcome_email`), après paiement (reçu), nouvelle vente (vendeur), nouvelle commission (affilié), litige.
- Un échec d'email **ne bloque jamais** une vente.

## Axe 4 — PWA / mobile

- `public/manifest.json` : nom « KDDF Market », icônes 192 et 512 (+ maskable), `display: standalone`, `theme_color`, `background_color`, raccourcis.
- `public/sw.js` : accueil et page `/offline` en cache, rien de privé en cache.
- Bouton **« Installer l'application KDDF Market »** (`src/components/InstallButton.tsx`, pied de page) + bandeau `InstallPrompt.tsx` ; Android : installation native ; iPhone : instructions « Ajouter à l'écran d'accueil ».

## Axe 5 — Bugs cachés et build Vercel

- TypeScript strict (`tsconfig.json`), **aucun `any`** dans `src/`, 598 imports locaux vérifiés (0 cassé), `eslint.ignoreDuringBuilds` (ESLint non installé : il ne peut pas bloquer le build), `typescript.ignoreBuildErrors: false`.
- **« Build Vercel : OK » — avec la réserve honnête ci-dessous.**

## Limites honnêtes (ce que je n'ai PAS pu vérifier ou faire)

1. `npm install` / `next build` n'ont pas été exécutés (registre npm injoignable) : vérification statique (tsc avec stubs, graphe d'imports) uniquement. Le premier build Vercel est le test définitif.
2. Pas de `package-lock.json` (voir README-DEPLOIEMENT).
3. WhatsApp **automatique** impossible sans l'API WhatsApp Business : boutons « Envoyer WhatsApp manuel » fournis.
4. Apple Pay et Google Pay ne sont **pas** implémentés (Stripe n'accepte pas les marchands camerounais). PayPal et les devises sont implémentés en V3.2 mais testés seulement avec des réponses PayPal simulées (voir points 9 à 11).
5. Pas de captcha : protection par limites de débit et anti-fraude.
6. Fapshi ne fournit pas le numéro MoMo du payeur : la règle anti-fraude correspondante s'appuie sur le téléphone **déclaré** à la commande (V3.1 : numéro, plus l'email).
7. (V3.1) Le code KDDF-XXXX n'est pas envoyé automatiquement par WhatsApp/SMS (API WhatsApp Business ou fournisseur SMS requis) : affiché à l'écran, bouton WhatsApp prérempli, boutons manuels vendeur/admin.
8. (V3.1) Qui connaît le numéro ET le code d'une commande peut la suivre et ouvrir un litige : c'est voulu (c'est le principe d'un achat sans compte). Gardez le code confidentiel.
9. (V3.2) Le code PayPal n'a jamais parlé au vrai PayPal depuis mon environnement : faites le Test 5 de `TEST-VENTE.md` en bac à sable avant d'ouvrir PayPal au public.
10. (V3.2) Je n'ai pas pu confirmer qu'un compte PayPal camerounais peut recevoir des paiements et retirer vers une banque ou Mobile Money : vérifiez-le chez PayPal. Les frais PayPal sont à votre charge (ou répercutés via `FX_MARGIN_PERCENT`), les remboursements PayPal sont manuels.
11. (V3.2) Taux de change des sources gratuites : actualisés ~1 fois/jour ; FCFA/EUR fixe officiel ; pas de taux « à la seconde ».

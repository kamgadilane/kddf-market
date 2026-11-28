# VERCEL-ENV-ET-WEBHOOKS.md — KDDF Market V3.2

Domaine utilisé dans les exemples : `https://kddf-market-v3-1.vercel.app` (remplacez-le par votre domaine réel si vous en ajoutez un). Après chaque ajout/modification de variable : **Redeploy**.

## 1. Variables d'environnement (Vercel → Settings → Environment Variables)

Cochez *Production*, *Preview* et *Development*. Les variables `NEXT_PUBLIC_*` sont **publiques** (visibles dans le navigateur) ; toutes les autres sont **secrètes, côté serveur uniquement**.

### Obligatoires

| Variable | Public ? | Valeur / où la trouver |
|---|---|---|
| `NEXT_PUBLIC_APP_URL` (toujours en https://) | oui | `https://kddf-market-v3-1.vercel.app` (https, sans « / » final) |
| `NEXT_PUBLIC_APP_NAME` | oui | `KDDF Market` |
| `NEXT_PUBLIC_SUPABASE_URL` | oui | Supabase → Project Settings → API → Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | oui | Supabase → API → clé `anon` `public` |
| `SUPABASE_SERVICE_ROLE_KEY` | **NON (secret)** | Supabase → API → clé `service_role`. Ne jamais la copier ailleurs |
| `FAPSHI_ENV` | non | `sandbox` (tests) puis `live` |
| `FAPSHI_API_USER` | non | dashboard Fapshi |
| `FAPSHI_API_KEY` | **secret** | dashboard Fapshi |
| `FAPSHI_WEBHOOK_SECRET` | **secret, obligatoire** | chaîne aléatoire 32+ caractères (`openssl rand -hex 32`) ; la même dans Fapshi. Sans elle, les webhooks sont refusés en production |
| `CRON_SECRET` | **secret** | chaîne aléatoire 32+ caractères ; Vercel l'envoie à la tâche planifiée (`Authorization: Bearer …`) |

### Emails (recommandé)

| Variable | Valeur |
|---|---|
| `RESEND_API_KEY` | **secret** — resend.com → API Keys. Sans clé : aucun email, les ventes passent quand même |
| `EMAIL_FROM` | `KDDF Market <no-reply@votre-domaine.com>` (domaine **vérifié** dans Resend) |

### Passerelles facultatives (n'apparaissent au paiement que si leurs clés existent)

| Variable | Valeur |
|---|---|
| `FLW_SECRET_KEY` | **secret** — Flutterwave → Settings → API (cartes Visa/Mastercard/Amex + Wave, Moov, M-Pesa, Orange, MTN) |
| `FLW_SECRET_HASH` | **secret** — texte de votre choix, à saisir aussi dans Flutterwave → Webhooks |
| `NOWPAYMENTS_API_KEY` | **secret** — NOWPayments (USDT, BTC, ETH) |
| `NOWPAYMENTS_IPN_SECRET` | **secret** — NOWPayments → Store Settings → IPN secret (les DEUX clés sont requises) |
| `NOWPAYMENTS_ENV` | `sandbox` pour tester, vide ou `live` en réel |

### PayPal et devises en temps réel (V3.2, facultatif)

PayPal n'apparaît au paiement que si `PAYPAL_CLIENT_ID` et `PAYPAL_CLIENT_SECRET` existent. Les conversions de devises, elles, ne demandent aucune clé.

| Variable | Valeur |
|---|---|
| `PAYPAL_ENV` | `sandbox` pour tester, vide ou `live` en réel |
| `PAYPAL_CLIENT_ID` | **secret** — developer.paypal.com → Apps & Credentials → votre app → Client ID |
| `PAYPAL_CLIENT_SECRET` | **secret** — même écran → Secret |
| `PAYPAL_WEBHOOK_ID` | **secret** — l'identifiant du webhook créé chez PayPal (voir §2). Sans lui, les webhooks PayPal sont ignorés ; le paiement est quand même validé au retour du client et par la tâche planifiée |
| `FX_MARGIN_PERCENT` | facultatif, défaut `0`, maximum `10`. Marge ajoutée au prix converti pour couvrir les frais PayPal (ex. `4`) |

### Support (facultatif)

| Variable | Valeur |
|---|---|
| `SUPPORT_EMAIL` | email qui reçoit les alertes de messages (nécessite Resend) |
| `NEXT_PUBLIC_SUPPORT_WHATSAPP` | numéro avec indicatif, ex. `237690000000` |
| `NEXT_PUBLIC_SUPPORT_EMAIL` | email affiché sur `/support` |

### À propos de `NEXTAUTH_SECRET`
KDDF Market n'utilise **pas** NextAuth : l'authentification est Supabase Auth (cookies gérés par `@supabase/ssr`). La variable est mentionnée (commentée) dans `.env.example` uniquement si vous voulez la définir ; elle n'est lue par aucun fichier.

## 2. URLs de webhooks à saisir chez les fournisseurs

| Fournisseur | Où | URL exacte | Sécurité |
|---|---|---|---|
| **Fapshi** | Dashboard → Webhook | `https://kddf-market-v3-1.vercel.app/api/webhooks/fapshi` | secret = `FAPSHI_WEBHOOK_SECRET` (en-tête `x-wh-secret`), statut relu chez Fapshi |
| **Flutterwave** | Settings → Webhooks | `https://kddf-market-v3-1.vercel.app/api/webhooks/flutterwave` | *Secret hash* = `FLW_SECRET_HASH` (en-tête `verif-hash`), paiement relu |
| **NOWPayments** | automatique | `https://kddf-market-v3-1.vercel.app/api/webhooks/crypto` (alias : `/api/webhooks/nowpayments`) | HMAC-SHA512 `x-nowpayments-sig` avec `NOWPAYMENTS_IPN_SECRET` ; l'URL est envoyée avec chaque facture |
| **PayPal** (V3.2) | developer.paypal.com → votre app → Webhooks → Add webhook | `https://kddf-market-v3-1.vercel.app/api/webhooks/paypal` — événements : `CHECKOUT.ORDER.APPROVED` et `PAYMENT.CAPTURE.COMPLETED` | signature vérifiée auprès de PayPal (`/v1/notification/verify-webhook-signature`) avec `PAYPAL_WEBHOOK_ID` ; la commande est relue chez PayPal, jamais crue sur parole |
| **Supabase Auth** | Authentication → URL Configuration | Site URL `https://kddf-market-v3-1.vercel.app` ; Redirect `https://kddf-market-v3-1.vercel.app/auth/callback` | — |
| **Tâche planifiée Vercel** | `vercel.json` (déjà configurée) | `/api/cron/release-funds`, tous les jours à 03:00 UTC | `Bearer CRON_SECRET` |

Les adresses au singulier (`/api/webhook/fapshi`, `/flutterwave`, `/crypto`, `/paypal`) fonctionnent aussi : ce sont les routes réelles ; les adresses au pluriel sont des alias (`next.config.mjs`, `rewrites`). Tous les webhooks répondent toujours **200** (le fournisseur ne rejoue pas en boucle) et ignorent silencieusement tout appel mal signé.

## 3. Arborescence complète des fichiers

```text
kddf-market-v3-1/
├── public
│   ├── icons
│   │   ├── apple-touch-icon.png
│   │   ├── icon-192.png
│   │   ├── icon-32.png
│   │   ├── icon-512.png
│   │   └── maskable-512.png
│   ├── favicon.ico
│   ├── logo.png
│   ├── manifest.json
│   ├── og.png
│   └── sw.js
├── scripts
│   └── build-emails.mjs
├── src
│   ├── app
│   │   ├── admin
│   │   │   ├── commissions
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── fraude
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── litiges
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── orders
│   │   │   │   └── page.tsx
│   │   │   ├── payouts
│   │   │   │   └── page.tsx
│   │   │   ├── products
│   │   │   │   └── page.tsx
│   │   │   ├── sellers
│   │   │   │   └── page.tsx
│   │   │   ├── support
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── validation
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── withdrawals
│   │   │   │   └── page.tsx
│   │   │   ├── actions.ts
│   │   │   ├── layout.tsx
│   │   │   └── page.tsx
│   │   ├── api
│   │   │   ├── affiliate
│   │   │   │   └── click
│   │   │   │       └── route.ts
│   │   │   ├── antifraud
│   │   │   │   └── ip
│   │   │   │       └── route.ts
│   │   │   ├── boost
│   │   │   │   └── route.ts
│   │   │   ├── checkout
│   │   │   │   └── route.ts
│   │   │   ├── cron
│   │   │   │   └── release-funds
│   │   │   │       └── route.ts
│   │   │   ├── fx
│   │   │   │   └── route.ts
│   │   │   ├── download
│   │   │   │   └── [token]
│   │   │   │       └── [fileId]
│   │   │   │           └── route.ts
│   │   │   ├── share
│   │   │   │   └── route.ts
│   │   │   ├── suivre-commande
│   │   │   │   ├── confirmer
│   │   │   │   │   └── route.ts
│   │   │   │   ├── litige
│   │   │   │   │   └── route.ts
│   │   │   │   └── route.ts
│   │   │   ├── support
│   │   │   │   └── route.ts
│   │   │   ├── views
│   │   │   │   └── route.ts
│   │   │   ├── webhook
│   │   │   │   ├── crypto
│   │   │   │   │   └── route.ts
│   │   │   │   ├── fapshi
│   │   │   │   │   └── route.ts
│   │   │   │   ├── flutterwave
│   │   │   │   │   └── route.ts
│   │   │   │   └── paypal
│   │   │   │       └── route.ts
│   │   │   └── welcome
│   │   │       └── route.ts
│   │   ├── auth
│   │   │   ├── callback
│   │   │   │   └── route.ts
│   │   │   └── signout
│   │   │       └── route.ts
│   │   ├── boutique
│   │   │   └── [slug]
│   │   │       └── page.tsx
│   │   ├── checkout
│   │   │   └── cancelled
│   │   │       └── page.tsx
│   │   ├── dashboard
│   │   │   ├── affiliates
│   │   │   │   └── page.tsx
│   │   │   ├── orders
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── products
│   │   │   │   ├── new
│   │   │   │   │   └── page.tsx
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── promote
│   │   │   │   └── page.tsx
│   │   │   ├── settings
│   │   │   │   └── page.tsx
│   │   │   ├── shop
│   │   │   │   └── page.tsx
│   │   │   ├── wallet
│   │   │   │   ├── actions.ts
│   │   │   │   └── page.tsx
│   │   │   ├── layout.tsx
│   │   │   └── page.tsx
│   │   ├── download
│   │   │   └── [token]
│   │   │       └── page.tsx
│   │   ├── grossistes
│   │   │   ├── actions.ts
│   │   │   └── page.tsx
│   │   ├── international
│   │   │   └── page.tsx
│   │   ├── library
│   │   │   ├── actions.ts
│   │   │   └── page.tsx
│   │   ├── litige
│   │   │   └── [orderId]
│   │   │       └── page.tsx
│   │   ├── login
│   │   │   └── page.tsx
│   │   ├── mot-de-passe-oublie
│   │   │   └── page.tsx
│   │   ├── offline
│   │   │   └── page.tsx
│   │   ├── p
│   │   │   └── [id]
│   │   │       └── page.tsx
│   │   ├── panier
│   │   │   └── page.tsx
│   │   ├── reset-password
│   │   │   └── page.tsx
│   │   ├── suivre-commande
│   │   │   └── page.tsx
│   │   ├── support
│   │   │   └── page.tsx
│   │   ├── error.tsx
│   │   ├── globals.css
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   └── template.tsx
│   ├── components
│   │   ├── AddToCartButton.tsx
│   │   ├── AdminAffiliateCount.tsx
│   │   ├── AffiliateSlider.tsx
│   │   ├── AutoRefresh.tsx
│   │   ├── BoostButtons.tsx
│   │   ├── BuyerOrderActions.tsx
│   │   ├── CartLink.tsx
│   │   ├── CheckoutForm.tsx
│   │   ├── CommissionBanner.tsx
│   │   ├── CopyButton.tsx
│   │   ├── CountrySelector.tsx
│   │   ├── DisputePhotoForm.tsx
│   │   ├── FlashError.tsx
│   │   ├── FxPanel.tsx
│   │   ├── GuaranteeBadge.tsx
│   │   ├── InactivityAlerts.tsx
│   │   ├── InstallButton.tsx
│   │   ├── InstallPrompt.tsx
│   │   ├── IpBeacon.tsx
│   │   ├── Navbar.tsx
│   │   ├── OrderLifecycle.tsx
│   │   ├── OrderTracking.tsx
│   │   ├── ProductCard.tsx
│   │   ├── ProductForm.tsx
│   │   ├── ProductGallery.tsx
│   │   ├── ProductReviewForm.tsx
│   │   ├── ProductReviews.tsx
│   │   ├── productReviewsActions.ts
│   │   ├── ProfileForm.tsx
│   │   ├── PwaRegister.tsx
│   │   ├── RefTracker.tsx
│   │   ├── ReviewForm.tsx
│   │   ├── SellerContact.tsx
│   │   ├── SellerStatsLine.tsx
│   │   ├── SellerTrustLine.tsx
│   │   ├── ShareButtons.tsx
│   │   ├── ShopForm.tsx
│   │   ├── Stars.tsx
│   │   ├── StatCard.tsx
│   │   ├── StoryImageButton.tsx
│   │   ├── SupportForm.tsx
│   │   ├── SupportLink.tsx
│   │   ├── ThemeToggle.tsx
│   │   ├── trackingActions.ts
│   │   ├── TrackingButton.tsx
│   │   ├── TrackOrder.tsx
│   │   ├── VerifiedBadge.tsx
│   │   ├── ViewTracker.tsx
│   │   ├── WaitlistForm.tsx
│   │   ├── WalletFraudGuard.tsx
│   │   ├── WholesaleApplyForm.tsx
│   │   ├── WholesaleQuoteButton.tsx
│   │   └── WithdrawForm.tsx
│   ├── lib
│   │   ├── emails
│   │   │   ├── confirmation_inscription.html
│   │   │   ├── litige.html
│   │   │   ├── notification_affilie.html
│   │   │   ├── notification_vendeur.html
│   │   │   ├── recu_paiement.html
│   │   │   ├── render.ts
│   │   │   └── templates.generated.ts
│   │   ├── supabase
│   │   │   ├── admin.ts
│   │   │   ├── client.ts
│   │   │   └── server.ts
│   │   ├── activity.ts
│   │   ├── antiFraud.ts
│   │   ├── auth.ts
│   │   ├── boost.ts
│   │   ├── calculateCommission.ts
│   │   ├── cart.ts
│   │   ├── catalog.ts
│   │   ├── clientIp.ts
│   │   ├── commissionNotify.ts
│   │   ├── contact.ts
│   │   ├── currency.ts
│   │   ├── db.ts
│   │   ├── disputeNotify.ts
│   │   ├── email.ts
│   │   ├── emailTemplates.ts
│   │   ├── env.ts
│   │   ├── errors.ts
│   │   ├── fapshi.ts
│   │   ├── flash.ts
│   │   ├── flutterwave.ts
│   │   ├── fx.ts
│   │   ├── fxCore.ts
│   │   ├── format.ts
│   │   ├── fulfillment.ts
│   │   ├── guest.ts
│   │   ├── guestTrack.ts
│   │   ├── imageCompress.ts
│   │   ├── imageKind.ts
│   │   ├── installPrompt.ts
│   │   ├── labels.ts
│   │   ├── mailer.ts
│   │   ├── money.ts
│   │   ├── nowpayments.ts
│   │   ├── payments.ts
│   │   ├── paypal.ts
│   │   ├── paypalCore.ts
│   │   ├── phone.ts
│   │   ├── rateLimit.ts
│   │   ├── realUrl.ts
│   │   ├── resend.ts
│   │   ├── saleNotifications.ts
│   │   ├── share.ts
│   │   ├── shop.ts
│   │   ├── supportEmail.ts
│   │   ├── syncMyPayments.ts
│   │   ├── translations.ts
│   │   ├── trust.ts
│   │   ├── useFx.ts
│   │   ├── types.ts
│   │   ├── validate.ts
│   │   ├── welcome.ts
│   │   └── wholesale.ts
│   ├── types
│   │   └── server-only.d.ts
│   └── middleware.ts
├── supabase
│   ├── email-templates
│   │   ├── change-email.html
│   │   ├── confirm-signup.html
│   │   ├── LISEZ-MOI.md
│   │   ├── magic-link.html
│   │   └── reset-password.html
│   ├── tests
│   │   ├── 00_supabase_stubs.sql
│   │   ├── 10_scenarios.sql
│   │   ├── 20_avis_suivi.sql
│   │   ├── 30_commissions.sql
│   │   ├── 40_antifraude.sql
│   │   ├── 50_final.sql
│   │   ├── 60_securite.sql
│   │   ├── 70_v3.sql
│   │   ├── 80_guest.sql
│   │   └── 90_paypal_fx.sql
│   ├── schema.sql
│   └── verifier-installation.sql
├── .env.example
├── .gitignore
├── AUDIT-SECURITE.md
├── CHECKLIST-14-MODULES-PLUS-AUDIT.md
├── next.config.mjs
├── package.json
├── postcss.config.js
├── README-DEPLOIEMENT.md
├── README.md
├── tailwind.config.ts
├── TEST-VENTE.md
├── tsconfig.json
├── VERCEL-ENV-ET-WEBHOOKS.md
└── vercel.json
```

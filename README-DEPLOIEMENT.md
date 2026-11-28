# KDDF Market V4.0 — Déploiement en 5 étapes (NOUVEAU dépôt)

Ce ZIP est un projet **neuf** (pas de `.git`, pas de `node_modules`). Vous le déployez comme un **nouveau dépôt GitHub** `kddf-market-v3-1`, avec un **nouveau projet Supabase** (ou une base vide). Durée : environ 30 minutes.

> À lire avant : je n'ai pas pu lancer `npm install` ni `next build` dans mon environnement (le registre npm n'y est pas joignable). Le code a été vérifié autrement (TypeScript strict avec types de substitution, contrôle de tous les imports, 802 tests SQL sur un vrai Postgres). Le **premier déploiement Vercel est donc le vrai test de build** : si une erreur apparaît, ouvrez le journal de build et envoyez-moi la ligne exacte. Il n'y a pas de `package-lock.json` : Vercel installe les versions autorisées par `package.json` ; après le 1er build réussi, lancez `npm install` en local et ajoutez le `package-lock.json` créé au dépôt.

---

## Étape 1 — Créer le nouveau dépôt `kddf-market-v3-1` et y mettre le code

1. GitHub → **New repository** → nom `kddf-market-v3-1` → *Private* → ne cochez ni README ni .gitignore → **Create**.
2. Sur votre ordinateur : **dézippez** `kddf-market-v4-0-final.zip`. Vous obtenez un dossier avec `src/`, `supabase/`, `public/`, `package.json`, etc.
3. Dans ce dossier (terminal) :
   ```bash
   git init
   git add .
   git commit -m "KDDF Market V4.0"
   git branch -M main
   git remote add origin https://github.com/VOTRE-COMPTE/kddf-market-v3-1.git
   git push -u origin main
   ```
   Sans terminal : sur la page du dépôt vide, **uploading an existing file** puis glissez le **contenu** du dossier (pas le dossier lui-même ni le .zip). Le fichier `.gitignore` est inclus (il évite d'envoyer `.env.local` et `node_modules`).

## Étape 2 — Exécuter le SQL dans Supabase

1. Supabase → **New project** (région proche, ex. Paris/Francfort) → notez le mot de passe base.
2. **SQL Editor → New query** → ouvrez `supabase/schema.sql`, copiez **tout** le contenu, collez, **Run**. Résultat attendu : *Success. No rows returned*. Le script est **rejouable** sans erreur (testé deux fois d'affilée).
3. Nouvelle requête → collez `supabase/verifier-installation.sql` → **Run** : toutes les lignes doivent afficher **OK** (tables, buckets, fonctions, vues en lecture seule, RLS partout, fonctions « invité » réservées au serveur, colonne `transactions.order_code`).
4. **Storage** : les buckets `covers` (public) et `deliverables`, `support`, `wholesale`, `disputes` (privés) sont créés par le script. S'il en manque un, créez-le à la main avec ce nom exact.
5. **Authentication → URL Configuration** : *Site URL* = `https://kddf-market-v3-1.vercel.app` ; *Redirect URLs* = `https://kddf-market-v3-1.vercel.app/auth/callback`. Puis **Authentication → Emails** : collez les 4 modèles de `supabase/email-templates/` (voir `LISEZ-MOI.md`).
6. **Project Settings → API** : copiez l'URL, la clé `anon` et la clé `service_role` (**secrète**).
7. Après votre première inscription sur le site, devenez administrateur (SQL Editor) :
   ```sql
   update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'VOTRE_EMAIL');
   ```

## Étape 3 — Créer le projet Vercel

Vercel → **Add New → Project** → importez `kddf-market-v3-1` → *Framework : Next.js* (détecté) → **ne cliquez pas encore sur Deploy** : passez d'abord à l'étape 4.

## Étape 4 — Mettre les variables dans Vercel

Vercel → *Settings → Environment Variables* → ajoutez les variables de `VERCEL-ENV-ET-WEBHOOKS.md` (liste exacte, copiée de `.env.example`). Minimum pour vendre :

| Variable | Valeur |
|---|---|
| `NEXT_PUBLIC_APP_URL` | `https://kddf-market-v3-1.vercel.app` (sans « / » final) |
| `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` | étape 2.6 |
| `SUPABASE_SERVICE_ROLE_KEY` | étape 2.6 — **jamais** dans le navigateur |
| `FAPSHI_ENV` (`sandbox` puis `live`), `FAPSHI_API_USER`, `FAPSHI_API_KEY` | dashboard Fapshi |
| `FAPSHI_WEBHOOK_SECRET` | **obligatoire** : une chaîne aléatoire de 32+ caractères, la même dans Fapshi |
| `CRON_SECRET` | chaîne aléatoire de 32+ caractères |
| `RESEND_API_KEY`, `EMAIL_FROM` | Resend (domaine vérifié) — sans clé, aucun email n'est envoyé mais les ventes passent |

Puis **Deploy**. Ensuite chez Fapshi (et les autres passerelles que vous activez), saisissez les URLs de webhook :
`https://kddf-market-v3-1.vercel.app/api/webhooks/fapshi` (voir toutes les URLs dans `VERCEL-ENV-ET-WEBHOOKS.md`).

## Étape 5 — Tester

Suivez `TEST-VENTE.md` (4 tests). Le principal : vente **physique de 10 000 FCFA SANS compte**, avec un affilié à 20 % pendant les 30 jours de lancement :

| Part | Montant |
|---|---|
| Plateforme KDDF | **0 FCFA** (0 % lancement) |
| Affilié | **2 000 FCFA** |
| Vendeur | **8 000 FCFA** |

Le client reçoit son code **KDDF-XXXX** sur l'écran de confirmation, et peut suivre sa commande sur `/suivre-commande` avec son numéro + ce code. Vérifiez aussi `/admin` (transaction), `/admin/litiges`, `/admin/fraude`, `/dashboard/wallet`. Passez ensuite `FAPSHI_ENV` à `live` quand les tests `sandbox` sont bons.

> Achat sans compte (V3.1) : produit **physique** = Nom + Numéro WhatsApp/MoMo + Ville + Quartier, sans email ni mot de passe ; produit **digital** = compte gratuit obligatoire. Le code n'est pas envoyé automatiquement par WhatsApp/SMS (il faudrait l'API WhatsApp Business ou un fournisseur SMS) : il s'affiche à l'écran avec un bouton WhatsApp prérempli, et vendeur/admin ont un bouton « WhatsApp manuel ».

## Après le déploiement (10 minutes)
1. `https://kddf-market-v3-1.vercel.app/api/cron/release-funds` ouvert dans le navigateur → **401** (normal : il exige `CRON_SECRET`).
2. Vercel → Logs : `[fapshi-webhook] … résultat : paid` après un paiement test.
3. Sur Android (Chrome) : bouton **« Installer l'application KDDF Market »** en bas du site, ou menu ⋮ → *Ajouter à l'écran d'accueil*.
4. Vérifiez que la tâche planifiée apparaît dans Vercel → *Settings → Cron Jobs* (tous les jours à 03:00 UTC ; limite du plan gratuit : 1 exécution par jour, c'est ce qui est configuré).

## Mise à jour d'un site déjà en ligne (vers la V4.0)
Depuis la V3.9 : suivez `MISE-A-JOUR-V4-0.md` (1 seul fichier SQL : `supabase/mise-a-jour-gros.sql`, puis le code). Depuis une version plus ancienne :
Suivez `MISE-A-JOUR-V3-9.md` : 1) Supabase : lancer `supabase/mise-a-jour-finale.sql` (si jamais fait) puis `supabase/mise-a-jour-identite.sql` ; 2) `supabase/verifier-installation.sql` (tout « OK ») ; 3) remplacer les fichiers sur GitHub (Vercel redéploie) ; 4) variables facultatives « Éditeur du site » dans Vercel (liste dans `.env.example`) ; 5) tests de `TEST-REEL.md`.
PayPal (facultatif) : variables `PAYPAL_ENV`, `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_WEBHOOK_ID` ; webhook `https://VOTRE-DOMAINE/api/webhooks/paypal` (événements `CHECKOUT.ORDER.APPROVED` et `PAYMENT.CAPTURE.COMPLETED`).

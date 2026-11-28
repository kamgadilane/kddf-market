# Sauvegarde et sécurité : ce que VOUS devez faire (30 minutes, une fois)

Le code est protégé par la base (règles RLS, fonctions sécurisées, limitation de débit, signatures des webhooks). Mais certaines protections dépendent de vos comptes, pas du code.

## 1. Sauvegardes de la base (le plus important)
- Supabase > Project Settings > Database > **Backups**. Le plan gratuit ne conserve pas de sauvegarde téléchargeable fiable : dès les premières ventes réelles, passez le projet en **Pro (environ 25 USD/mois)** pour avoir les sauvegardes quotidiennes, ou faites une sauvegarde manuelle chaque semaine :
  Supabase > Database > Backups, ou depuis votre ordinateur : `supabase db dump` (outil Supabase CLI).
- Gardez une copie du dossier du projet (le zip) et de `supabase/schema.sql` : ils recréent toute la structure.
- Les fichiers (couvertures, livrables) sont dans Storage : exportez-les de temps en temps ou vérifiez que vos fichiers sources existent ailleurs.

## 2. Comptes à protéger (authentification en deux étapes, 2FA)
Activez la 2FA sur : **GitHub** (Settings > Password and authentication), **Vercel** (Account Settings > Authentication), **Supabase** (Account > Security), **Fapshi**, **Flutterwave**, **PayPal**, **NOWPayments**, **Resend** et **votre e-mail**. Quelqu'un qui prend votre GitHub ou Vercel prend le site et l'argent.

## 3. Clés secrètes
- `SUPABASE_SERVICE_ROLE_KEY`, `FAPSHI_API_KEY`, `FLW_SECRET_KEY`, `PAYPAL_CLIENT_SECRET`, `NOWPAYMENTS_*`, `CRON_SECRET`, `RESEND_API_KEY` : seulement dans Vercel, jamais dans GitHub, jamais envoyées par message.
- Si une clé a été exposée : régénérez-la chez le fournisseur, changez-la dans Vercel, Redeploy.
- Le dépôt GitHub peut être **privé** : Vercel fonctionne aussi avec un dépôt privé.

## 4. Nom de domaine et e-mails
- Un nom de domaine (par exemple `kddfmarket.com`, environ 10 000 à 15 000 FCFA par an) rend le site plus crédible : Vercel > Settings > Domains. Mettez ensuite `NEXT_PUBLIC_APP_URL` à la nouvelle adresse et refaites les webhooks (adresses dans `VERCEL-ENV-ET-WEBHOOKS.md`).
- Resend : vérifiez votre domaine (Domains) puis réglez `EMAIL_FROM` avec cette adresse, sinon les e-mails de confirmation ne partent pas ou arrivent en spam.

## 5. Surveillance régulière
- **Admin > Erreurs** : pages qui ont planté chez des visiteurs. Regardez-la une fois par semaine.
- **Admin > Fraude, Litiges, Retraits** : traiter chaque jour au début.
- Vercel > Logs : erreurs serveur ; Supabase > Logs.
- Les paiements reçus mais non livrables (stock épuisé, montant différent) apparaissent « à vérifier » dans Admin > Commandes : remboursez à la main.

## 6. Retraits (paiement des vendeurs)
Les retraits sont payés **à la main** par vous (Admin > Retraits). Ce choix est volontaire : un paiement automatique sans contrôle est le premier outil des fraudeurs. Contrôlez le numéro, le montant « à payer » et marquez « payé » seulement après l'envoi.

## 7. Légal
Les pages légales sont des modèles raisonnables adaptés à votre situation, **pas un avis juridique**. Dès que le chiffre d'affaires devient important, faites-les relire par un juriste camerounais, et vérifiez vos obligations fiscales et déclaratives (statut d'entreprise, impôts).

## 8. Données personnelles
Chaque utilisateur peut télécharger ses données et supprimer son compte (Mon profil). La suppression anonymise le profil et conserve seulement ce qui doit l'être (ventes, retraits) pour votre comptabilité. Elle est refusée tant que le portefeuille n'est pas vide ou qu'un retrait, un litige ou une commande est en cours.

# KDDF Market V3.8 : projet final — comment l'installer

## Cas 1 — Votre site est déjà en ligne (cas normal)
Dans CET ordre (le SQL d'abord, le code ensuite) :

1. **Supabase** > SQL Editor > New query > ouvrir `supabase/mise-a-jour-finale.sql`, tout copier, coller, **Run**. Résultat attendu : « Success ». Sans danger si vous le lancez deux fois.
2. **Contrôle** : coller `supabase/verifier-installation.sql` > Run. Toutes les lignes doivent afficher « OK ».
3. **GitHub** : envoyer le contenu du zip du projet (dossiers `src`, `supabase`, `public`, `scripts` + les fichiers à la racine) en remplaçant les anciens. Vercel redéploie tout seul (2 à 3 minutes).
4. **Vercel** > Settings > Environment Variables : ajouter, si vous voulez changer une information, les variables « Éditeur du site » (liste dans `.env.example`, voir aussi plus bas). Sans variable, les valeurs par défaut s'affichent. Après toute modification : Deployments > Redeploy.
5. **Admin > Commissions** : vérifier les 3 réglages ajoutés : « Frais de service payés par l'acheteur », « Plan gratuit : nombre de produits publiés » (10), et les tarifs existants.
6. Faire les tests de `TEST-REEL.md` (30 minutes, en mode test Fapshi).

Si Supabase affiche une erreur rouge à l'étape 1 : copiez-la, rien n'a été modifié tant que la requête n'a pas réussi.

## Cas 2 — Nouvelle installation (base vide)
1. Supabase > SQL Editor > coller TOUT `supabase/schema.sql` > Run (il contient déjà le bloc final). 2. `verifier-installation.sql`. 3. Suivre `README-DEPLOIEMENT.md` (Vercel, variables, webhooks). Ne lancez PAS `mise-a-jour-finale.sql` en plus : il est déjà inclus.

## Les variables « Éditeur du site » (pages légales et pied de page)
Toutes facultatives (une valeur par défaut est dans le code, avec vos informations). Noms exacts, à copier tels quels dans Vercel :

| Variable | Valeur par défaut |
|---|---|
| `NEXT_PUBLIC_SITE_OWNER_STATUS` | Particulier |
| `NEXT_PUBLIC_SITE_OWNER_NAME` | KAMGA DJOMGANG DILANE FAREL |
| `NEXT_PUBLIC_SITE_OWNER_ADDRESS` | Makepe Bm, Douala, Cameroun |
| `NEXT_PUBLIC_SITE_OWNER_EMAIL` | kamgadjomgangd@gmail.com |
| `NEXT_PUBLIC_SITE_OWNER_PHONE` | +237689644382 |
| `NEXT_PUBLIC_SITE_PUBLICATION_DIRECTOR` | KAMGA DJOMGANG DILANE FAREL |
| `NEXT_PUBLIC_SITE_HOST` | Vercel Inc., 440 N Barranca Ave #4133, Covina, CA 91723, États-Unis |

Pas de guillemets autour de la valeur dans Vercel. Elles commencent par `NEXT_PUBLIC_` : ce sont des informations publiques (elles apparaissent sur le site).

## Ce que contient la V3.8 (en plus de tout ce qui existait)
| Fonction | Où |
|---|---|
| Frais de service payés par l'acheteur selon le moyen de paiement | Admin > Commissions ; affichés au paiement et sur la page produit |
| Plan gratuit : limite de produits publiés (10, réglable, 0 = illimité) | Admin > Commissions ; message clair au vendeur |
| Notifications personnelles dans la cloche (vente, retrait, grossiste, litige, produit validé, Pro) | Cloche 🔔 |
| Journal des erreurs de l'application | Admin > Erreurs |
| Suppression de compte + téléchargement de mes données | Espace créateur > Mon profil |
| Exports Excel (CSV) : mes ventes (vendeur) ; ventes et retraits (admin) | Tableau de bord ; Admin > Tableau de bord |
| Pages légales (Conditions, Confidentialité, Remboursement, Mentions légales) | Pied de page |
| robots.txt, plan du site (sitemap), page 404, page d'erreur globale | Automatique |
| Écrans de chargement (squelettes) : site, fiche produit, espace créateur, admin | Automatique |
| Contrôle d'installation étendu | `supabase/verifier-installation.sql` |

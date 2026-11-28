# KDDF Market V3.9 : identité des vendeurs, 2FA, téléphone, alertes, affiches

## Cas 1 : votre site est déjà en ligne
Dans CET ordre (le SQL d'abord, le code ensuite) :

1. **Supabase > SQL Editor** : si vous n'avez **jamais** lancé `supabase/mise-a-jour-finale.sql` (V3.8), lancez-le d'abord (copier, coller, Run). Puis ouvrez `supabase/mise-a-jour-identite.sql`, tout copier, coller, **Run** : « Success ». Sans danger si lancé deux fois.
2. **Contrôle** : `supabase/verifier-installation.sql` > Run. Toutes les lignes doivent afficher « OK ».
3. **GitHub** : envoyer le contenu du zip (dossiers `src`, `supabase`, `public`, `scripts` + fichiers à la racine ; le dossier `marketing` n'est pas nécessaire au site) en remplaçant les anciens. Vercel redéploie (2 à 3 minutes).
4. **Vercel > Environment Variables** (facultatif) : `ADMIN_ALERT_EMAIL` pour recevoir les alertes de bugs par email (voir `ALERTES-ET-ERREURS.md`). Puis Redeploy.
5. **Admin > Identités** : vérifier les 2 règles (identité obligatoire : cochée ; téléphone : non cochée). **Activez la 2FA sur votre compte** (`/securite`).
6. Faire les tests de `TEST-REEL.md` (section E).

**Effet immédiat à connaître** : dès l'étape 1, un NOUVEAU vendeur ne peut publier qu'après votre validation d'identité. Les vendeurs déjà actifs sont reconnus automatiquement. Pour désactiver temporairement la règle : Admin > Identités > décocher puis Enregistrer.

## Cas 2 : nouvelle installation
Supabase : tout `supabase/schema.sql` (contient déjà tout) > Run, puis `verifier-installation.sql`. Ensuite `README-DEPLOIEMENT.md`. Ne lancez PAS `mise-a-jour-*.sql`.

## Ce que contient la V3.9
| Fonction | Où | Détail |
|---|---|---|
| Vérification d'identité des vendeurs | `/dashboard/verification` · Admin > Identités | `SECURITE-COMPTES.md` |
| Garde de publication (identité requise) | Automatique | Brouillons toujours possibles |
| Téléphone confirmé par SMS (facultatif) | `/securite` | Fournisseur SMS à configurer |
| Protection 2FA facultative | `/securite`, `/login/2fa` | Retraits et actions admin protégés dans la base |
| Alertes de bugs (cloche + email) + notice « que faire » | Admin > Erreurs | `ALERTES-ET-ERREURS.md` |
| Guide de bienvenue (8 affiches) pour les nouveaux utilisateurs | Automatique + pied de page | `AFFICHES-PUBLICITAIRES.md` |
| 16 affiches publicitaires (feed + story) | Zip `kddf-affiches-publicitaires.zip` (à garder sur votre téléphone/PC, pas dans GitHub) | `AFFICHES-PUBLICITAIRES.md` |
| Écrans de chargement, 404, pages légales, SEO (V3.8) | Automatique | `MISE-A-JOUR-V3-8.md` |

# Affiches publicitaires

Deux sortes d'affiches : celles qui sont **dans le site** (pour chaque nouvel utilisateur) et celles que **vous publiez** (réseaux sociaux).

## 1. Affiches dans le site : le guide de bienvenue
- **Quand** : à la toute première visite du site (navigateur), puis **une seconde fois à la première ouverture de l'application installée** sur téléphone ou PC. Ensuite plus jamais, sauf si l'utilisateur clique « Revoir le guide » dans le pied de page.
- **8 affiches** plein écran : Bienvenue · Acheter en 3 étapes · Vendre · Vos avantages · Affiliation · Sécurité · Installer l'application · **Service client** (WhatsApp, email, page Aide).
- **Navigation** : on fait glisser de côté (téléphone), ou flèches du clavier, ou boutons « Précédent / Suivant », ou les petits points. Le bouton **Quitter ✕** est toujours visible en haut à droite (Échap marche aussi). Chaque affiche peut avoir un bouton d'action (« Ouvrir ma boutique », « Contacter le service client »…).
- **Pages exclues** : l'administration, les retours de connexion et la vérification 2FA (on n'interrompt jamais un travail en cours).
- **Modifier les textes** : `src/lib/posters.ts` (titres, textes, puces, couleurs). Le numéro WhatsApp et l'email du service client viennent de `NEXT_PUBLIC_SUPPORT_WHATSAPP` / `NEXT_PUBLIC_SUPPORT_EMAIL`, sinon des informations de l'éditeur (`NEXT_PUBLIC_SITE_OWNER_PHONE` / `_EMAIL`).
- **Tester à nouveau comme un nouveau visiteur** : navigateur privé, ou effacer les données du site (les clés sont `kddf_welcome_web_v1` et `kddf_welcome_app_v1`).
- Remarque : sur iPhone, l'application installée a son propre stockage, donc le guide s'y affiche aussi une fois.

## 2. Affiches à publier vous-même : zip `kddf-affiches-publicitaires.zip`
Les images (28 Mo) sont livrées dans un zip séparé pour ne pas alourdir GitHub/Vercel : gardez-les sur votre téléphone ou ordinateur. Dans le projet, seul le générateur `marketing/generer-affiches.mjs` est conservé.
- `feed/` : 8 images **1080 × 1350** (publications Facebook, Instagram, LinkedIn, groupes WhatsApp).
- `story/` : les mêmes 8 en **1080 × 1920** (statuts WhatsApp, stories Facebook/Instagram, TikTok).
- Sujets : lancement · vendeurs · acheteurs · moyens de paiement · affiliation · confiance · installation de l'application · service client.
- **L'adresse du site** écrite en bas est `kddf-market.vercel.app`. Si votre adresse est différente (nouveau projet Vercel, nom de domaine), régénérez : `SITE_URL="votre-adresse" WHATSAPP="+237…" node marketing/generer-affiches.mjs` (demande Node 18+ et Playwright), ou envoyez-moi la nouvelle adresse et je les refais.
- Conseil de diffusion : une affiche par jour pendant 8 jours, avec le lien en légende ; épinglez celle des vendeurs et celle de l'installation.

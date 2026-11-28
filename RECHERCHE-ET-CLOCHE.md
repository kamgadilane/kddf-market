# Loupe de recherche et cloche de notification

## La loupe 🔍 (en-tête, partout sur le site)
- Un clic sur la loupe (ou Ctrl+K, ou la touche « / ») ouvre une fenêtre « Aller à… ».
- On tape un mot (retrait, produit, commande, boost, abonnement…) et les pages correspondantes s'affichent. Entrée ou un clic ouvre la page.
- Les pages de l'endroit où l'on se trouve passent en premier : dans l'espace créateur, les pages du créateur ; dans l'admin, les pages d'administration ; sur le site, les pages publiques.
- Dernière ligne : « Chercher « mot » dans les produits » lance la recherche du catalogue.
- Le visiteur voit les pages publiques ; le vendeur connecté voit en plus son espace créateur ; l'administrateur voit en plus l'administration.
- Pour ajouter une page à la recherche : une ligne dans `src/lib/siteMap.ts` (titre, description, mots-clés).

## La cloche 🔔 (en-tête, personnes connectées)
- Un point rouge avec un nombre indique les messages non lus. Un clic ouvre la liste ; ouvrir la cloche marque tout comme lu.
- L'administrateur écrit les messages dans **Admin > Annonces** : titre, message (500 caractères), destinataires (tous / vendeurs / abonnés Pro), lien facultatif (/page du site ou https://…), durée facultative.
- Une annonce reste visible 30 jours au plus. Elle peut être supprimée à tout moment (elle disparaît chez tout le monde).
- Limite de sécurité : 10 annonces par heure. Les liens javascript: ou http:// sont refusés.
- Le compteur se met à jour au chargement, toutes les 2 minutes et quand on revient sur l'onglet.

## Installation (dans cet ordre)
1. Supabase > SQL Editor : coller `supabase/historique/mise-a-jour-recherche-cloche.sql` (déjà inclus dans `mise-a-jour-finale.sql` si vous la lancez) > Run (peut être relancé sans danger).
2. GitHub : envoyer le contenu du zip (dossiers `src` et `supabase`).
3. Vercel redéploie ; ensuite : Admin > Annonces > envoyer une première annonce de test.

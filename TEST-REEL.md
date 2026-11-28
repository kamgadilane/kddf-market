# TEST-REEL : 12 vérifications à faire à la main après la mise à jour V3.8

Faites-les avec `FAPSHI_ENV=sandbox` (argent fictif). Comptes : Vendeur (V), Client (C), Admin (vous). Cochez au fur et à mesure.

## A. Frais de service
- [ ] Admin > Commissions : la section « Frais de service payés par l'acheteur » affiche Fapshi 0 %, Cartes 3 %, Crypto 1 %, PayPal 5 % + 300 FCFA.
- [ ] Page d'un produit à 10 000 FCFA : en choisissant PayPal, le total annoncé est 10 800 FCFA ; avec Mobile Money 10 000 FCFA.
- [ ] Payer en Mobile Money (sandbox) : la vente est « payée » ; V voit son gain calculé sur 10 000 (commission 8 % ou 0 % pendant le lancement), jamais sur 10 800.
- [ ] Admin > Tableau de bord : la carte « Frais de service acheteurs » monte seulement pour les paiements PayPal / cartes / crypto.

## B. Plan gratuit
- [ ] Un vendeur de test publie 10 produits ; la tentative d'en publier un 11e affiche un message « limite atteinte » avec la solution (Pro ou dépublier).
- [ ] Admin > Commissions : passer la limite à 0 → le 11e produit se publie.

## C. Cloche et annonces
- [ ] Après une vente de test, V voit « Nouvelle vente » dans la cloche (point rouge).
- [ ] Admin > Annonces : envoyer un message à « tous » → il apparaît dans la cloche de C.

## D. Pages et compte
- [ ] Pied de page : les 4 pages légales s'ouvrent et affichent vos informations d'éditeur ; `/robots.txt` et `/sitemap.xml` répondent ; une adresse inventée affiche la page 404 de KDDF Market.
- [ ] Mon profil : « Télécharger mes données » donne un fichier ; pour un compte vide de test, « Supprimer mon compte » (mot SUPPRIMER) fonctionne ; pour un compte avec un retrait en attente il est refusé avec une explication.
- [ ] Espace créateur > Tableau de bord : « Exporter mes ventes (Excel) » télécharge un fichier lisible dans Excel ; Admin > Tableau de bord : « Exporter les ventes » et « Exporter les retraits ».
- [ ] Admin > Erreurs : la page s'ouvre (vide au début est normal).

## E. Identité, 2FA, téléphone, alertes, affiches (V3.9)
- [ ] Nouveau compte vendeur de test : bandeau « Vérifiez votre identité » ; créer un produit en brouillon fonctionne ; tenter de le **publier** affiche « identité non vérifiée » avec la solution.
- [ ] Ce compte : `/dashboard/verification` > envoyer recto, verso, vidéo (ou photo) > message « Documents envoyés ». Votre cloche d'admin affiche « Vérification d'identité à traiter ».
- [ ] Admin > Identités : vous voyez les 3 fichiers ; **Refuser** sans motif est impossible ; refuser avec motif prévient le vendeur (cloche) ; il renvoie ; vous **validez** ; il reçoit le badge et peut publier.
- [ ] Un ancien vendeur (avec produits déjà publiés) publie toujours sans rien envoyer.
- [ ] `/securite` : activer la **2FA** avec une application d'authentification ; se déconnecter, se reconnecter : le code à 6 chiffres est demandé ; un faux code affiche « Cause + Solution » ; sans 2FA tout fonctionne comme avant.
- [ ] Compte avec 2FA : désactiver demande un code valide.
- [ ] Téléphone (seulement si un fournisseur SMS est configuré) : le code arrive par SMS et le numéro passe à « confirmé » ; sans fournisseur, un message clair explique la cause.
- [ ] Navigateur privé : à la première visite les **affiches de bienvenue** s'ouvrent ; glisser / Suivant / points fonctionnent ; **Quitter** ferme ; au rechargement elles ne reviennent pas ; le pied de page « Revoir le guide » les rouvre. Application installée : elles s'affichent une fois à la première ouverture.
- [ ] Alertes : `ADMIN_ALERT_EMAIL` est renseignée dans Vercel ; Admin > Erreurs s'ouvre ; une erreur listée affiche « que faire ? » avec des étapes (un vrai bug de test n'est pas nécessaire).

## F. Commande de gros (V4.0)
Préparation : un compte vendeur avec identité validée et badge « Grossiste Vérifié », un produit physique proposé en gros (prix dès 10 et dès 50 pièces, stock gros). Un second compte acheteur (autre email).
- [ ] `/grossistes` : la fiche affiche **Commander et payer en sécurité** ; le texte vendeur explique 3 % / 5 % / le reste.
- [ ] Sans compte : la page de commande affiche « Créez un compte gratuit » (pas de paiement possible) ; le paiement à la livraison n'est pas proposé.
- [ ] Acheteur connecté, **9 pièces** : refus clair (minimum 10). **10 pièces** : le prix unitaire de gros et le total s'affichent ; **50 pièces** : le prix du palier 50 s'applique.
- [ ] Plus que le stock gros : refus avec la quantité disponible.
- [ ] Payer (petit montant, Mobile Money) : l'argent est « en attente » chez le vendeur (jamais libérable avant 7 jours) ; le stock gros diminue après le paiement confirmé ; l'acheteur reçoit son code KDDF-XXXX.
- [ ] Vendeur : `/dashboard/orders` montre la commande avec le badge **GROS**. Portefeuille : montant = prix des marchandises − 3 % (0 % en lancement) − 5 % si affilié, + livraison.
- [ ] Le vendeur ne peut pas commander son propre produit en gros (message clair).

## Si un test échoue
Notez le message exact (et la capture) : Admin > Erreurs et Vercel > Logs donnent la cause. Le contrôle `supabase/verifier-installation.sql` doit afficher « OK » partout.

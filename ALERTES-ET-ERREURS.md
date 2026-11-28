# Alertes de bugs : comment vous êtes prévenu et quoi faire

## Ce qui se passe quand une page plante chez un visiteur
1. Le visiteur voit une page d'erreur claire (« Oups… réessayer ») ; le site envoie en silence un rapport (message + page + référence, **sans aucune donnée personnelle**).
2. L'erreur est notée dans **Admin > Erreurs** (100 dernières, gardées 30 jours, avec le nombre de répétitions).
3. **Vous êtes alerté** : une alerte apparaît dans votre **cloche 🔔** d'administrateur, et un **email** arrive avec : le problème en français simple, la cause probable, **les étapes numérotées pour le corriger** et un bouton vers Admin > Erreurs.
4. **Pas de déluge** : au plus une alerte (cloche + email) toutes les **30 minutes**, même si 1 000 visiteurs rencontrent le bug. Les erreurs sans gravité (fichier périmé après une mise à jour, session expirée) sont notées mais ne déclenchent pas d'alerte.

## À configurer (2 minutes)
- `ADMIN_ALERT_EMAIL` dans Vercel : l'adresse qui reçoit l'email d'alerte. Vide = `SUPPORT_EMAIL`, sinon l'email de l'éditeur (`kamgadjomgangd@gmail.com`).
- L'email demande `RESEND_API_KEY` (voir `.env.example`). **Sans Resend, l'alerte dans la cloche fonctionne quand même.**
- Après modification d'une variable : Vercel > Deployments > Redeploy.

## La notice « que faire » (Admin > Erreurs)
Chaque erreur a un bouton déroulant « que faire ? » avec le titre, le niveau d'urgence, la cause probable et les étapes. Cas couverts : base non à jour (SQL manquant), clé Supabase incorrecte, stockage absent, paiement, e-mail, session, réseau, droits d'accès… Pour une erreur inconnue, la notice donne la méthode générale :
1. Copier la « Référence » de l'erreur.
2. Vercel > votre projet > **Logs** : rechercher cette référence pour voir le détail technique.
3. Envoyer le message exact (et la référence) à votre développeur ou à Claude pour correction.

## Si le bug vient de votre mise à jour
Vercel > Deployments > choisir le déploiement précédent > « Promote to Production » : le site revient à la version d'avant en 1 minute, le temps de corriger.

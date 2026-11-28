# Sécurité des comptes : identité des vendeurs, téléphone, 2FA

Objectif : empêcher les vendeurs malhonnêtes de s'installer sur KDDF Market, et protéger les comptes de ceux qui vendent.

| Protection | Pour qui | Obligatoire ? | Où |
|---|---|---|---|
| Vérification d'identité (carte recto + verso + vidéo/photo avec la carte) | Vendeurs | **Oui** pour publier un produit (réglable) | `/dashboard/verification` (vendeur), `/admin/identite` (vous) |
| Téléphone confirmé par SMS | Tous | Non (réglable : « obligatoire pour publier ») | `/securite` |
| Double protection 2FA (code à 6 chiffres) | Tous | **Non, facultative** | `/securite` |

## 1. Vérification d'identité (ce que voit le vendeur)
1. Il crée son compte et prépare ses produits en **brouillon** (il peut le faire tout de suite).
2. Un bandeau « Vérifiez votre identité » apparaît dans son espace créateur. Il envoie : le **recto** de sa carte, le **verso**, et une **vidéo de 10 secondes** (ou une photo) de lui **tenant sa carte** à côté de son visage. Sur téléphone, les boutons ouvrent directement la caméra.
3. Vous recevez une alerte dans la cloche 🔔 d'administrateur. Tant que vous n'avez pas validé, **il ne peut pas publier** (message clair avec la solution).
4. Après votre décision, il est prévenu dans sa cloche : « Identité validée » (et reçoit le badge « Vendeur vérifié »), ou « Identité refusée » avec votre motif, et peut renvoyer ses documents.

## 2. Votre travail d'administrateur (Admin > 🪪 Identités)
Pour chaque demande, vous voyez le recto, le verso et la vidéo (liens temporaires de 10 minutes, jamais publics).
- **Comparez** le visage de la vidéo avec la photo de la carte ; le nom de la carte avec le nom du compte ; vérifiez que la carte est lisible, complète et **non expirée**.
- **Valider** si tout est cohérent. **Refuser** sinon, avec un motif précis (« photo floue », « carte expirée », « visage différent »). Le motif est obligatoire.
- Les chiffres en haut : demandes en attente, validées, refusées, téléphones confirmés, comptes avec 2FA.
- Règles réglables sur la même page : « Identité obligatoire pour publier » (recommandé, activé) et « Téléphone confirmé obligatoire pour publier » (désactivé par défaut).

**Anciens vendeurs** : ceux qui avaient déjà un produit publié, une vente ou le badge avant cette mise à jour sont reconnus automatiquement (« legacy ») pour ne pas bloquer le site en ligne. Vous pouvez leur demander de se faire vérifier : l'état est visible dans le bilan de la page.

**Confidentialité** : les cartes sont dans un espace de stockage **privé** (`identity`), visible uniquement par le propriétaire et par l'administrateur. Elles ne s'affichent jamais sur le site. Le contrôle `verifier-installation.sql` vérifie que cet espace n'est jamais public. Conservez-les le temps nécessaire et supprimez-les si un vendeur le demande (Supabase > Storage > identity).

**Limite honnête** : c'est un contrôle humain. Il arrête la grande majorité des fraudeurs paresseux, mais il ne détecte pas à coup sûr une fausse carte très bien faite. Un service de reconnaissance faciale automatique (payant) pourrait venir plus tard.

## 3. Téléphone confirmé par SMS (facultatif, SMS payants)
Le code est envoyé par SMS grâce à Supabase Auth. **Il faut d'abord configurer un fournisseur de SMS** :
1. Supabase > Authentication > Providers (ou Sign In / Providers) > **Phone** > activer.
2. Choisir un fournisseur (Twilio, MessageBird, Vonage…), créer un compte chez lui et saisir ses identifiants. Les SMS vers le Cameroun sont **payants** (quelques dizaines de FCFA l'unité) : prévoyez un petit crédit.
3. Tant que ce n'est pas fait, le bouton « Recevoir le code par SMS » affiche une erreur claire (« le service d'envoi de SMS n'est pas activé »). **Ne cochez pas** « Téléphone confirmé obligatoire » avant que cela fonctionne, sinon aucun vendeur ne pourrait publier.
4. Alternative gratuite : ne pas activer les SMS ; le numéro du vendeur est de toute façon visible dans votre page Identités, et vous le contrôlez avec sa carte.

## 4. Double protection 2FA (facultative pour tous)
- L'utilisateur ouvre `/securite` (icône 🔐 du menu) > « Activer la protection 2FA » > scanne le QR code avec **Google Authenticator, Microsoft Authenticator ou Authy** > saisit le code à 6 chiffres.
- Ensuite, à chaque connexion : mot de passe, puis code à 6 chiffres (page `/login/2fa`).
- **Désactiver** demande aussi un code valide.
- Protection côté base de données : dès qu'un compte a la 2FA, **les actions d'administrateur et les demandes de retrait sont refusées** si la session n'a pas validé le code. Un voleur de mot de passe ne peut donc ni administrer le site ni retirer l'argent.
- **Recommandation forte : activez-la sur votre compte administrateur.**
- Prérequis Supabase : l'authentification multifacteur TOTP est activée par défaut dans les nouveaux projets (Authentication > Sign In / Providers > Multi-Factor : « TOTP » doit être Enabled). Aucun coût.

### Un utilisateur a perdu son téléphone
Après avoir vérifié son identité (message au service client, carte, vidéo), retirez sa protection : Supabase > SQL Editor :
```sql
delete from auth.mfa_factors where user_id = (select id from auth.users where email = 'EMAIL_DE_L_UTILISATEUR');
```
Il peut alors se connecter avec son mot de passe et réactiver la 2FA.

## 5. Messages d'erreur
Tous les blocages affichent « Cause + Solution » : `identite_requise`, `telephone_non_verifie`, `verification_2fa_requise`, code 2FA faux, SMS non configuré…

# TEST-VENTE.md — 6 tests à faire après le déploiement (V3.2)

Prérequis : `schema.sql` exécuté, variables Vercel en place, `FAPSHI_ENV=sandbox`, 30 jours de lancement actifs (`/admin/commissions` affiche « Mode lancement : 0 % »). Comptes : **Vendeur** (V), **Affilié** (A, avec compte), **Client** (C : aucun compte, numéro différent de celui de A).

Ces scénarios sont déjà testés automatiquement (`supabase/tests/` : 802 vérifications, 0 échec, dont `80_guest.sql` et `90_paypal_fx.sql`) ; ce document sert à les refaire à la main sur le vrai site.

---

## Test 1 — Vente PHYSIQUE de 10 000 FCFA SANS compte (plateforme 0 %, affilié 20 %)

1. V publie un **produit physique à 10 000 FCFA** (livraison à domicile Douala à 0 pour simplifier, ou retrait), commission d'affilié **20 %** ; l'admin l'approuve dans `/admin/products`.
2. A copie son lien affilié (`?ref=CODE`) depuis `/dashboard/affiliates`.
3. C (déconnecté, navigation privée) ouvre le lien de A, clique « Commander ». Il voit **Nom complet + Numéro WhatsApp / MoMo + Ville + Quartier** (pas d'email, pas de mot de passe), remplit, paie en Mobile Money (numéro de test Fapshi sandbox).
4. **Résultat attendu** (`/admin`, ligne de la transaction) :

| Plateforme | Affilié | Vendeur |
|---|---|---|
| **0 FCFA** | **2 000 FCFA** | **8 000 FCFA** |

5. **Code généré** : la page de confirmation affiche **KDDF-XXXX** (ex. KDDF-8421) et le message « Merci [Nom] ! Ta commande KDDF-XXXX est confirmée. » avec un bouton WhatsApp prérempli. Le code est aussi visible dans `/dashboard/orders` (V) et `/admin/orders`. En base : `select order_code from transactions order by created_at desc limit 1;`.
6. Contrôles : V voit « Client sans compte » (jamais d'adresse `invite-…@example.com`) ; l'affilié reçoit sa commission malgré l'absence de compte chez C (cookie 30 jours) ; A voit 2 000 FCFA dans `/dashboard/wallet` (en attente) ; fonds physiques libérés après réception confirmée, au plus tôt 7 jours après paiement.

## Test 2 — Suivi avec Numéro + Code sur /suivre-commande

1. Sans être connecté, ouvrir `/suivre-commande` (ou le lien « Suivre ma commande » du pied de page).
2. Saisir le **numéro** utilisé au Test 1 (n'importe quel format : `677…`, `+237 677…`) et le **code KDDF-XXXX**.
3. **Résultat attendu** : la frise **En attente → En livraison → Livré → Terminé** s'affiche avec l'étape **« En attente »** active (V n'a pas encore expédié) ; le bouton **« Ouvrir un litige »** (avec photos, jusqu'à 3) est proposé.
4. Contrôles : un mauvais code ou un mauvais numéro donne le même message « Commande introuvable » ; V passe la commande à « Expédiée » puis « Livrée » → la frise avance (« En livraison », « Livré ») ; le bouton « J'ai bien reçu ma commande » termine la commande (« Terminé »).
5. Litige : « Ouvrir un litige » + motif + photos → `/admin/litiges` affiche **Nom + Numéro + Code KDDF-XXXX + preuve de paiement MoMo** (numéro déclaré, montant, ID Fapshi, moyen, date) + photos du client ; les fonds du vendeur restent bloqués.

## Test 3 — Affilié qui s'achète lui-même avec son propre numéro

1. A (qui a un compte affilié avec son numéro de téléphone dans son profil) achète le produit de V **sans compte** (navigation privée), avec son lien affilié et **son propre numéro** (même avec un autre format : `+237 6…` ou `6…`).
2. **Résultat attendu** : la vente **aboutit** (C reçoit son code), mais la **commission d'affilié = 0** (vendeur : 10 000 FCFA pendant le lancement).
3. `/admin/fraude` : ligne « Affilié = Acheteur », action **bloquée** (commission annulée), score **100**.
4. Variante anti-spam : 6 commandes avec le même numéro en moins d'1 h → la 6ᵉ est **refusée** (« Trop de commandes avec ce numéro… ») et tracée dans `/admin/fraude`.

## Test 4 — Produit DIGITAL de 5 000 FCFA SANS compte

1. V publie un **produit digital à 5 000 FCFA** (PDF/ePub).
2. Un visiteur **sans compte** ouvre la page produit et clique pour acheter.
3. **Résultat attendu** : il voit « **Pour les produits digitaux, crée un compte gratuit en 30 secondes pour recevoir ton fichier** » avec les boutons « Créer mon compte gratuit » / « J'ai déjà un compte » ; **aucun paiement ne peut être lancé** (même en appelant `/api/checkout` directement : erreur 401, aucune commande créée).
4. Après création du compte (retour automatique sur le produit), l'achat est possible : pendant le lancement Plateforme **0**, Vendeur **5 000** ; après le lancement (8 %) : Plateforme **400**, Vendeur **4 600**. Portail `/download/<jeton>` : fichier téléchargeable (lien signé 60 s), email de reçu envoyé à l'adresse du compte ; fonds en attente **24 h**.

## Test 5 — Paiement PayPal en bac à sable (V3.2)

1. Vercel : `PAYPAL_ENV=sandbox` avec les clés *Sandbox* (developer.paypal.com → Apps & Credentials → Sandbox) ; webhook sandbox sur `/api/webhooks/paypal`.
2. Ouvrir un produit de **10 000 FCFA**, aller au paiement : le panneau de conversion affiche environ **15,25 €** (ou le montant en USD / GBP / CAD choisi) avec le taux et sa source ; le bouton « Payer … avec PayPal » apparaît.
3. Payer avec un compte *Personal* Sandbox. Retour automatique sur `/download/<jeton>` : la commande passe **payée** (portail de téléchargement ou code KDDF pour un produit physique).
4. **Résultat attendu** : `/admin` montre la transaction en **10 000 FCFA** (pas en euros), `fapshi_trans_id` commençant par `pp:`, `pay_currency`/`pay_amount`/`fx_rate` renseignés ; répartition inchangée (pendant le lancement : plateforme 0, vendeur 10 000).
5. Contrôles : fermer l'onglet PayPal avant de payer → la commande reste « en attente », aucun crédit ; en production, `PAYPAL_ENV` vide (ou `live`) avec les clés *Live*.

## Test 6 — Devises en temps réel

1. Ouvrir `/api/fx` : JSON avec les taux, la source (`open.er-api.com`, `frankfurter` ou `base`) et l'heure.
2. Dans le paiement, changer la devise (EUR → USD → GBP → CAD) : le montant se met à jour tout de suite ; le montant affiché est celui réellement envoyé à PayPal.
3. Pour un produit de 10 000 FCFA en EUR, vous devez voir **15,25 €** (10 000 / 655,957 arrondi au centime supérieur).
4. Si vous avez défini `FX_MARGIN_PERCENT=4`, le montant est majoré de 4 % et le panneau l'indique.

## Si un résultat diffère
Notez l'écart exact (montant affiché, page), puis regardez Vercel → Logs (`[fapshi-webhook]`) et `/admin/fraude`. Une vente dont le montant reçu diffère du montant attendu est mise **« à vérifier »** (aucun crédit) et tracée dans `fraud_logs`.

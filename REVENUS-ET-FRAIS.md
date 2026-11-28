# Revenus et frais de KDDF Market (V3.8)

Tout se règle dans **Admin > Commissions**, effet immédiat sur les NOUVELLES opérations, sans redéployer.

## Ce que paie l'acheteur
Prix + livraison + **frais de service** (selon le moyen de paiement choisi). Les frais restent à la plateforme : ils couvrent les frais de la passerelle. Le vendeur ne les paie jamais et ne les voit pas retirés de son prix.

| Moyen de paiement | Frais de service au départ | Pourquoi |
|---|---|---|
| Mobile Money (Fapshi) | 0 % | La plateforme absorbe déjà les 3 % de Fapshi (couverts par la commission) |
| Cartes et Mobile Money élargi (Flutterwave) | 3 % | Cartes : environ 1,5 à 3,15 % + 0,25 € selon la carte |
| Crypto (NOWPayments) | 1 % | Frais de réseau variables |
| PayPal | 5 % + 300 FCFA | PayPal : environ 2,29 à 3,49 % + frais fixe 0,35 à 0,49 €, + 1,5 % international + marge de change 3 à 4 % |

Ces valeurs sont des **estimations d'après les frais publics des passerelles** (votre capture). Comparez-les avec vos relevés réels après les premières ventes et ajustez. Exemple : produit 10 000 FCFA payé par PayPal → l'acheteur paie 10 000 + 500 + 300 = 10 800 FCFA ; le vendeur est calculé sur 10 000.
Formule : `frais = arrondi supérieur(prix_total × % / 100) + montant fixe`. Le calcul est fait par la base (`apply_service_fee`), jamais par le navigateur ; l'écran n'affiche qu'un aperçu identique.

## Ce que gagne la plateforme
| Source | Règle (réglable) |
|---|---|
| Commission sur les ventes | 0 % pendant les 30 jours de lancement, puis **8 %** ; vendeur Pro **5 %** ; maximum 10 % ; compte exempté 0 % |
| Frais de service acheteur | voir tableau ci-dessus |
| Frais de retrait | 1,5 %, minimum 200 FCFA |
| Retrait express | + 2 % |
| Abonnement Pro | 3 000 FCFA pour 30 jours |
| Boosts | 3 j 1 000 · 7 j 2 500 · 14 j 4 500 · 30 j 8 000 FCFA (−20 % pour les Pro) |
| Bannières sponsorisées, produit de la semaine | Admin > Pub & bannières |
| Services payants | `/services` |

Pourquoi 8 % / 5 % : Fapshi prend 3 % de chaque encaissement et c'est la plateforme qui paie ; ne descendez jamais sous 3 %.

## Plan gratuit
Un vendeur gratuit peut avoir **10 produits publiés** en même temps (réglable ; 0 = illimité). Les brouillons ne comptent pas. Les produits déjà publiés ne sont jamais dépubliés par ce réglage. Pro, comptes exemptés et admin : illimité.

## Où voir l'argent
- Admin > Tableau de bord : volume, commissions, frais de service encaissés, abonnements Pro, frais de retrait.
- Export CSV admin : toutes les ventes et tous les retraits (comptabilité).
- Garantie dans la base : `total payé = frais de service + commission + affilié + vendeur` (contrainte `paid_split_is_exact`, une vente qui ne tombe pas juste est refusée).

## Limites honnêtes
- Les frais de service sont une estimation : si la passerelle prélève plus, la plateforme garde la différence en moins.
- Fapshi à 0 % de frais de service : choix de départ, car Mobile Money est le moyen principal de vos acheteurs ; vous pouvez le changer dans l'admin.
- Les paiements en devise étrangère (PayPal) subissent en plus la marge de change réglée par `FX_MARGIN_PERCENT`.

## Ventes en gros (V4.0)
Une commande « Commander et payer en sécurité » (10 à 1 000 pièces) rapporte à la plateforme **3 % au maximum** des marchandises (0 % pendant le lancement ou pour un compte exempté, jamais plus que le taux normal du vendeur) ; l'affilié reçoit 5 % fixes seulement s'il a amené la vente ; le reste et la livraison vont au grossiste. Attention : Fapshi prélève environ 3 % que la plateforme absorbe sur le Mobile Money, donc sur le gros payé en Mobile Money votre marge nette est proche de zéro (négative pendant le lancement). Détails : `MISE-A-JOUR-V4-0.md`.

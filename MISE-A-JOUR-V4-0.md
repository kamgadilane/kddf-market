# KDDF Market V4.0 : paiement des ventes en gros

## Ce qui change
Avant la V4.0, un acheteur « gros » contactait le grossiste sur WhatsApp et concluait hors du site : **aucune commission, aucune protection**. Maintenant, chaque fiche grossiste a un bouton **« Commander et payer en sécurité »** : c'est une vraie commande, payée sur KDDF Market.

| Point | Règle |
|---|---|
| Prix | Calculé par la base de données selon la quantité (dès 10 pièces, dès 50 pièces). Le navigateur ne peut pas le modifier. Jamais au-dessus du prix détail actuel. |
| Quantité | 10 à 1 000 pièces, dans la limite du « stock gros » du grossiste. Au-delà : devis WhatsApp. |
| Paiement | **En ligne uniquement** (pas de paiement à la livraison). Compte acheteur gratuit obligatoire. |
| Argent | Gardé par KDDF Market comme tout produit physique : jamais libéré avant 7 jours après le paiement, confirmation de réception par l'acheteur, litige possible avec photos. |
| Commission plateforme | **3 %** au maximum (0 % pendant le lancement ou pour un compte exempté ; jamais plus que le taux normal du vendeur). Calculée sur le prix des marchandises. |
| Affilié | 5 % fixes, seulement si un affilié a amené la vente. |
| Grossiste | Le reste (92 % avec un affilié, 97 % sans). La livraison lui revient entièrement. |
| Stock gros | Diminué quand le paiement est **réellement confirmé** (pas pendant une revue). |
| Vendeur | Doit avoir l'identité validée (V3.9) ET le badge « Grossiste Vérifié ». |
| Suivi | Badge **GROS** dans « Mes commandes » du vendeur ; code KDDF-XXXX pour l'acheteur. |

Le devis WhatsApp reste disponible pour négocier ou pour plus de 1 000 pièces. Un accord conclu uniquement par WhatsApp, hors du site, n'est ni protégé ni commissionné.

## Cas 1 : votre site est déjà en ligne (V3.9 installée)
Dans CET ordre (SQL d'abord, code ensuite) :
1. **Supabase > SQL Editor** : ouvrir `supabase/mise-a-jour-gros.sql`, tout copier, coller, **Run** : « Success ». Sans danger si lancé deux fois.
2. **Contrôle** : `supabase/verifier-installation.sql` > Run : toutes les lignes « OK ».
3. **GitHub** : remplacer les fichiers par ceux du zip (src, supabase, public, scripts + fichiers à la racine). Vercel redéploie (2 à 3 minutes).
4. **Test** : voir `TEST-REEL.md`, section F (commande de gros).

## Cas 2 : nouvelle installation
`supabase/schema.sql` en entier (contient déjà tout) > Run, puis `verifier-installation.sql`, puis `README-DEPLOIEMENT.md`. Ne lancez PAS `mise-a-jour-*.sql`.

## Limites à connaître
- Frais de livraison : c'est l'option de livraison de la fiche produit (montant par commande, pas par quantité). Pour un très gros colis, négociez par devis.
- Au-delà de 1 000 pièces : devis WhatsApp uniquement.
- Aucun `next build` n'a pu être lancé dans l'atelier de développement (pas d'accès au registre npm) : le premier build réel est celui de Vercel. La base de données, elle, est testée (852 vérifications, 0 échec).

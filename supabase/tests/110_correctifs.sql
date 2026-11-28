-- Tests V3.4 : quantité de commande jusqu'à 1000 (limitée par le stock) et candidature grossiste (administrateur sans attente de 24 h).
-- À lancer APRÈS 10 à 100.
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = false;
update public.profiles set fraud_review = false, is_blocked = false;
update public.products set stock = 500 where id = 'bbbbbbbb-0000-0000-0000-0000000000c1';

\echo ===== Quantité =====
select tests.as_service();
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', null, null, 'Client Gros', 60, 'pickup_douala', null, '+237 655 110 001', null, 'online', 'Douala', 'Bonapriso', '10.9.9.1')->>'order_id' as o60 \gset
select tests.as_db();
select tests.eq('Commande de 60 pièces acceptée (avant : refusée au-delà de 50)', (select quantity::text from public.orders where id = :'o60'::uuid), '60');
select tests.eq('Total = 60 x 10 000 = 600 000 (livraison gratuite)', (select total_price::text from public.orders where id = :'o60'::uuid), '600000');
select tests.as_service();
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', null, null, 'Client Gros', 250, 'pickup_douala', null, '+237 655 110 002', null, 'online', 'Douala', 'Bonapriso', '10.9.9.2')->>'order_id' as o250 \gset
select tests.as_db();
select tests.eq('Commande de 250 pièces acceptée si le stock le permet', (select quantity::text from public.orders where id = :'o250'::uuid), '250');
select tests.as_service();
select tests.raises('Plus que le stock (501 pour 500) : refusé', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', null, null, 'Client Gros', 501, 'pickup_douala', null, '+237 655 110 003', null, 'online', 'Douala', 'Bonapriso', '10.9.9.3')$$, 'stock_insuffisant');
select tests.raises('Quantité 1001 refusée (plafond technique)', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', null, null, 'Client Gros', 1001, 'pickup_douala', null, '+237 655 110 004', null, 'online', 'Douala', 'Bonapriso', '10.9.9.4')$$, 'quantite_invalide');
select tests.raises('Quantité 0 refusée', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', null, null, 'Client Gros', 0, 'pickup_douala', null, '+237 655 110 005', null, 'online', 'Douala', 'Bonapriso', '10.9.9.5')$$, 'quantite_invalide');

\echo ===== Candidature grossiste =====
select tests.as_db();
update public.profiles set created_at = now() where id in ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444');
delete from public.wholesale_applications;
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Compte ordinaire de moins de 24 h : refusé', $$select public.wholesale_apply('33333333-3333-3333-3333-333333333333/cni.jpg', '33333333-3333-3333-3333-333333333333/shop.jpg', '689644382')$$, 'compte_trop_recent');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.wholesale_apply('44444444-4444-4444-4444-444444444444/cni.jpg', '44444444-4444-4444-4444-444444444444/shop.jpg', '689644382');
select tests.as_db();
select tests.eq('Administrateur récent : candidature enregistrée (en attente)', (select status || '/' || whatsapp from public.wholesale_applications where user_id = '44444444-4444-4444-4444-444444444444'), 'pending/689644382');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Fichier d''un autre compte refusé', $$select public.wholesale_apply('33333333-3333-3333-3333-333333333333/cni.jpg', '44444444-4444-4444-4444-444444444444/shop.jpg', '689644382')$$, 'fichier_invalide');
select tests.raises('Numéro invalide refusé', $$select public.wholesale_apply('44444444-4444-4444-4444-444444444444/cni.jpg', '44444444-4444-4444-4444-444444444444/shop.jpg', '12')$$, 'telephone_invalide');
select tests.as_db();
update public.profiles set created_at = now() - interval '3 days' where id in ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select public.wholesale_apply('33333333-3333-3333-3333-333333333333/cni.jpg', '33333333-3333-3333-3333-333333333333/shop.jpg', '+237 689 644 382');
select tests.as_db();
select tests.eq('Compte de plus de 24 h : candidature acceptée', (select status from public.wholesale_applications where user_id = '33333333-3333-3333-3333-333333333333'), 'pending');

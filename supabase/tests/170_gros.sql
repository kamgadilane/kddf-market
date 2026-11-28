-- Tests V4.0 : paiement des ventes en gros (prix par palier, commande, commission 3 %, affilié 5 %, stock, droits).
-- À lancer APRÈS 10 à 160 (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = false;
update public.commission_settings set identity_required = false;
-- Régime : lancement terminé, commission normale 8 % (pour distinguer le 3 % du gros)
update public.commission_settings set launch_start_date = current_date - 40, launch_end_date = current_date - 10, is_launch_mode = true,
       after_launch_percent = 8, platform_fee_percent = 8;
update public.profiles set is_blocked = false, commission_exempt = false, wholesale_verified = true where id = '11111111-1111-1111-1111-111111111111';
delete from public.wholesale_products where product_id in ('dddddddd-0000-0000-0000-000000000001');
delete from public.products where id in ('dddddddd-0000-0000-0000-000000000001');

\echo ===== G0 : produit grossiste (tee-shirt 5000 : 4000 dès 10, 3000 dès 50, stock gros 80) =====
insert into public.products (id, seller_id, product_type, title, slug, price, is_published, moderation_status, affiliate_percent, stock, images, whatsapp_seller, delivery_options)
values ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'physical', 'Tee-shirt gros', 'tshirt-gros', 5000, true, 'approved', 20, 500,
        array['https://img/tee.jpg'], '699000111', '{"pickup_douala":{"enabled":true,"price":0},"delivery_douala":{"enabled":true,"price":1000},"shipping_cameroon":{"enabled":false,"price":0}}');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.wholesale_save('dddddddd-0000-0000-0000-000000000001', 4000, 3000, 80, 'Douala', true);
select tests.as_db();
select referral_code from public.profiles where id = '22222222-2222-2222-2222-222222222222' \gset g_aff_

\echo ===== G1 : prix par palier =====
select tests.eq('9 pièces : pas de prix de gros', coalesce(public.wholesale_unit_price('dddddddd-0000-0000-0000-000000000001', 9)::text, 'null'), 'null');
select tests.eq('10 pièces : 4000', public.wholesale_unit_price('dddddddd-0000-0000-0000-000000000001', 10)::text, '4000');
select tests.eq('49 pièces : 4000', public.wholesale_unit_price('dddddddd-0000-0000-0000-000000000001', 49)::text, '4000');
select tests.eq('50 pièces : 3000', public.wholesale_unit_price('dddddddd-0000-0000-0000-000000000001', 50)::text, '3000');
select tests.eq('Produit non grossiste : pas de prix de gros', coalesce(public.wholesale_unit_price('aaaaaaaa-0000-0000-0000-000000000005', 20)::text, 'null'), 'null');

\echo ===== G2 : refus de commande =====
select tests.raises('Sans compte : refusé', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', null, '', 'Client', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'compte_requis_gros');
select tests.raises('Paiement à la livraison refusé', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 10, 'pickup_douala', null, '699000222', null, 'cod', 'Douala', 'Akwa')$$, 'cod_interdit_gros');
select tests.raises('9 pièces refusé', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 9, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'quantite_gros_invalide');
select tests.raises('1001 pièces refusé', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 1001, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'quantite_gros_invalide');
select tests.raises('Au-delà du stock gros refusé', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 81, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'stock_gros_insuffisant');
select tests.raises('Produit non grossiste refusé', $$select public.create_wholesale_order('aaaaaaaa-0000-0000-0000-000000000005', '33333333-3333-3333-3333-333333333333', '', 'Client', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'produit_gros_introuvable');
select tests.raises('Le grossiste ne peut pas acheter son propre lot', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '', 'Client', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'achat_propre_produit');
update public.profiles set wholesale_verified = false where id = '11111111-1111-1111-1111-111111111111';
select tests.raises('Grossiste non vérifié : refusé', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'produit_gros_introuvable');
update public.profiles set wholesale_verified = true where id = '11111111-1111-1111-1111-111111111111';
update public.wholesale_products set is_active = false where product_id = 'dddddddd-0000-0000-0000-000000000001';
select tests.raises('Offre désactivée : refusé', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'produit_gros_introuvable');
update public.wholesale_products set is_active = true where product_id = 'dddddddd-0000-0000-0000-000000000001';
select tests.raises('Livraison non proposée refusée (comme au détail)', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 10, 'shipping_cameroon', 'Akwa, Douala', '699000222', null, 'online', 'Douala', 'Akwa')$$, 'livraison_invalide');
select tests.eq('Aucune commande créée par les refus', (select count(*)::text from public.orders where product_id = 'dddddddd-0000-0000-0000-000000000001'), '0');

\echo ===== G3 : commande de 10 pièces, retrait sur place (prix de gros 4000, total 40000) =====
select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client Gros', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa') ->> 'transaction_id' as tx1 \gset g_
select tests.eq('Commande : prix de gros, total, drapeau', (select unit_price || '/' || quantity || '/' || total_price || '/' || is_wholesale::text from public.orders where product_id = 'dddddddd-0000-0000-0000-000000000001' order by created_at desc limit 1), '4000/10/40000/true');
select tests.eq('Transaction : total aligné sur la commande', (select total_amount::text from public.transactions where id = :'g_tx1'), '40000');
select tests.eq('Code de suivi KDDF créé', (select (order_code like 'KDDF-%')::text from public.transactions where id = :'g_tx1'), 'true');
update public.transactions set fapshi_trans_id = 'GROS-1' where id = :'g_tx1';
select tests.eq('Frais de service calculés sur le total de gros (Flutterwave)', public.apply_service_fee(:'g_tx1', 'flutterwave')->>'total', (40000 + ceil(40000 * (select percent from public.service_fee_rules where gateway = 'flutterwave') / 100)::bigint + (select fixed_amount from public.service_fee_rules where gateway = 'flutterwave'))::text);
-- on repart sans frais pour un calcul simple
update public.transactions set service_fee = 0, service_gateway = null, total_amount = 40000 where id = :'g_tx1';
select tests.eq('Paiement confirmé', public.confirm_fapshi_payment('GROS-1', 40000, 'mobile money', 38800)->>'status', 'paid');
select tests.eq('Répartition gros sans affilié : 3 % / 0 / reste', (select goods_amount || '/' || platform_fee || '/' || platform_fee_percent || '/' || affiliate_fee || '/' || seller_amount from public.transactions where id = :'g_tx1'), '40000/1200/3/0/38800');
select tests.eq('Au détail, le même vendeur paierait 8 %', (select platform_fee::text from public.compute_split_for_seller('11111111-1111-1111-1111-111111111111', 40000, false, 0, true)), '3200');
select tests.eq('Argent en attente (physique : pas libéré à l''achat)', (select (release_at is null)::text || '/' || (released_at is null)::text from public.transactions where id = :'g_tx1'), 'true/true');
select tests.eq('Stock gros diminué (80 - 10)', (select stock_wholesale::text from public.wholesale_products where product_id = 'dddddddd-0000-0000-0000-000000000001'), '70');
select tests.eq('Stock du produit diminué (500 - 10)', (select stock::text from public.products where id = 'dddddddd-0000-0000-0000-000000000001'), '490');
select tests.eq('Webhook rejoué : rien ne change', public.confirm_fapshi_payment('GROS-1', 40000, 'mobile money', 38800)->>'status', 'already');
select tests.eq('Stock gros inchangé après le rejeu', (select stock_wholesale::text from public.wholesale_products where product_id = 'dddddddd-0000-0000-0000-000000000001'), '70');

\echo ===== G4 : 50 pièces avec affilié, livraison à domicile (3000 x 50 + 1000 = 151000) =====
select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client Gros', 50, 'delivery_douala', 'Pharmacie', '699000222', :'g_aff_referral_code', 'online', 'Douala', 'Bonamoussadi') ->> 'transaction_id' as tx2 \gset g_
select tests.eq('Prix 3000, affilié figé à 5 %', (select unit_price || '/' || total_price || '/' || affiliate_percent from public.orders where id = (select order_id from public.transactions where id = :'g_tx2')), '3000/151000/5');
update public.transactions set fapshi_trans_id = 'GROS-2' where id = :'g_tx2';
select coalesce((select balance_pending from public.wallets where user_id = '22222222-2222-2222-2222-222222222222'), 0) as aff_before \gset g_
select tests.eq('Paiement confirmé', public.confirm_fapshi_payment('GROS-2', 151000, 'orange money', 140000)->>'status', 'paid');
select tests.eq('Répartition : plateforme 3 % de 150000, affilié 5 %, livraison au grossiste', (select goods_amount || '/' || platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.transactions where id = :'g_tx2'), '150000/4500/7500/139000');
select tests.eq('Compte de l''affilié crédité de 7500', ((select balance_pending from public.wallets where user_id = '22222222-2222-2222-2222-222222222222') - :g_aff_before)::text, '7500');
select tests.eq('Somme plateforme + affilié + vendeur = total', (select (platform_fee + affiliate_fee + seller_amount + coalesce(service_fee, 0))::text from public.transactions where id = :'g_tx2'), '151000');
select tests.eq('Stock gros (70 - 50)', (select stock_wholesale::text from public.wholesale_products where product_id = 'dddddddd-0000-0000-0000-000000000001'), '20');

\echo ===== G5 : montant truqué, stock gros =====
select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client Gros', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa') ->> 'transaction_id' as tx3 \gset g_
update public.transactions set fapshi_trans_id = 'GROS-3' where id = :'g_tx3';
select tests.eq('Montant payé différent : mise en revue', public.confirm_fapshi_payment('GROS-3', 39999, 'mobile money', 0)->>'status', 'review');
select tests.eq('Rien n''est crédité en cas de revue', (select status || '/' || coalesce(platform_fee, 0) || '/' || coalesce(seller_amount, 0) from public.transactions where id = :'g_tx3'), 'review/0/0');
select tests.eq('Le stock gros n''est pas diminué par une commande en revue', (select stock_wholesale::text from public.wholesale_products where product_id = 'dddddddd-0000-0000-0000-000000000001'), '20');
select tests.raises('21 pièces : au-delà du stock gros restant (20)', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 21, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'stock_gros_insuffisant');

\echo ===== G6 : commission « jamais plus que le taux du vendeur » =====
update public.profiles set commission_exempt = true where id = '11111111-1111-1111-1111-111111111111';
select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client Gros', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa') ->> 'transaction_id' as tx4 \gset g_
update public.transactions set fapshi_trans_id = 'GROS-4' where id = :'g_tx4';
select public.confirm_fapshi_payment('GROS-4', 40000, 'mtn', 0);
select tests.eq('Compte exempté : 0 %', (select platform_fee || '/' || seller_amount from public.transactions where id = :'g_tx4'), '0/40000');
update public.profiles set commission_exempt = false where id = '11111111-1111-1111-1111-111111111111';
update public.commission_settings set after_launch_percent = 2, platform_fee_percent = 2;
select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client Gros', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa') ->> 'transaction_id' as tx5 \gset g_
update public.transactions set fapshi_trans_id = 'GROS-5' where id = :'g_tx5';
select public.confirm_fapshi_payment('GROS-5', 40000, 'mtn', 0);
select tests.eq('Taux normal 2 % (< 3 %) : le gros ne dépasse pas 2 %', (select platform_fee_percent || '/' || platform_fee from public.transactions where id = :'g_tx5'), '2/800');
update public.commission_settings set after_launch_percent = 8, platform_fee_percent = 8;

\echo ===== G7 : le détail n'est pas touché =====
select public.create_checkout_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'Client', 10, 'pickup_douala', null, '699000333', null, 'online', 'Douala', 'Akwa') ->> 'order_id' as g_retail \gset
select tests.eq('Achat au détail du même produit : prix détail, pas de drapeau', (select unit_price || '/' || total_price || '/' || is_wholesale::text from public.orders where id = :'g_retail'), '5000/50000/false');
select tests.eq('Détail : commission habituelle 8 % (produit 2000)', (select platform_fee from public.compute_split_for_order('11111111-1111-1111-1111-111111111111', false, 2000, false, 0, true))::text, '160');
select tests.eq('Une seule ligne de répartition pour le gros', (select count(*)::text from public.compute_split_for_order('11111111-1111-1111-1111-111111111111', true, 99999, true, 5, true)), '1');
select tests.eq('Même calcul que wholesale_split pour un vendeur normal en régime normal 8 %', (select platform_fee || '/' || affiliate_fee from public.compute_split_for_order('11111111-1111-1111-1111-111111111111', true, 99999, true, 5, true)), (select platform_fee || '/' || affiliate_fee from public.wholesale_split(99999, true)));
select tests.eq('Toutes les commandes de gros respectent total = prix x quantité + livraison', (select count(*)::text from public.orders where is_wholesale and total_price <> unit_price * quantity + delivery_price), '0');

\echo ===== G8 : droits =====
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Un utilisateur ne peut pas appeler create_wholesale_order', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '', 'C', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'permission');
select tests.raises('Ni wholesale_unit_price', $$select public.wholesale_unit_price('dddddddd-0000-0000-0000-000000000001', 10)$$, 'permission');
select tests.raises('Ni compute_split_for_order', $$select * from public.compute_split_for_order('11111111-1111-1111-1111-111111111111', true, 1000, false, 0, true)$$, 'permission');
select tests.raises('Ni la confirmation de paiement', $$select public.confirm_fapshi_payment('GROS-1', 40000, 'x', 0)$$, 'permission');
select tests.as_anon();
select tests.raises('Un visiteur non plus', $$select public.create_wholesale_order('dddddddd-0000-0000-0000-000000000001', null, '', 'C', 10, 'pickup_douala', null, '699000222', null, 'online', 'Douala', 'Akwa')$$, 'permission');
select tests.as_db();

-- Tests grossistes / international / litiges. À lancer APRÈS 10_scenarios.sql.
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = false;
update public.profiles set wholesale_verified = false;
-- Les comptes de test datent de plus de 24 h (règle « compte trop récent » de wholesale_apply)
update public.profiles set created_at = now() - interval '3 days';

\echo ===== Grossistes =====
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.raises('Non vérifié : pas de produit grossiste', $$select public.wholesale_save('aaaaaaaa-0000-0000-0000-000000000003', 12000, 10000, 5, 'Douala', true)$$, 'grossiste_requis');
select public.wholesale_apply('11111111-1111-1111-1111-111111111111/cni.jpg', '11111111-1111-1111-1111-111111111111/shop.jpg', '+237699000111');
select tests.raises('Fichier d''un autre dossier refusé', $$select public.wholesale_apply('55555555-5555-5555-5555-555555555555/cni.jpg', '11111111-1111-1111-1111-111111111111/shop.jpg', '699000111')$$, 'fichier_invalide');
select tests.raises('Le vendeur ne peut pas s''auto-valider', $$select public.admin_wholesale_decide('11111111-1111-1111-1111-111111111111', true)$$, 'acces_refuse');
select tests.raises('Le vendeur ne peut pas écrire profiles.wholesale_verified', $$update public.profiles set wholesale_verified = true where id = '11111111-1111-1111-1111-111111111111'$$, 'permission');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin voit la candidature', (select count(*)::text from public.wholesale_applications where status = 'pending'), '1');
select public.admin_wholesale_decide('11111111-1111-1111-1111-111111111111', true);
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.raises('Prix gros >= prix détail refusé', $$select public.wholesale_save('aaaaaaaa-0000-0000-0000-000000000003', 15000, 10000, 5, 'Douala', true)$$, 'prix_gros_invalide');
select tests.raises('Produit digital refusé', $$select public.wholesale_save('aaaaaaaa-0000-0000-0000-000000000001', 5000, 4000, 5, 'Douala', true)$$, 'produit_invalide');
select public.wholesale_save('aaaaaaaa-0000-0000-0000-000000000003', 12000, 10000, 200, 'Douala', true);
select tests.as_anon();
select tests.eq('Visiteur voit le produit grossiste du vendeur vérifié', (select count(*)::text from public.wholesale_products), '1');
select tests.raises('Visiteur ne peut pas demander de devis', $$select public.wholesale_request('aaaaaaaa-0000-0000-0000-000000000003', 20)$$, 'permission');
select tests.raises('Visiteur ne lit pas les demandes', $$select * from public.wholesale_requests$$, 'permission');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Quantité < 10 refusée', $$select public.wholesale_request('aaaaaaaa-0000-0000-0000-000000000003', 5)$$, 'quantite_invalide');
select tests.eq('Devis 20 pièces : prix 12000 + WhatsApp du vendeur', (select (r->>'unit_price') || '/' || (r->>'whatsapp') from (select public.wholesale_request('aaaaaaaa-0000-0000-0000-000000000003', 20) r) q), '12000/+237699000111');
select tests.eq('Devis 60 pièces : prix 10000', (public.wholesale_request('aaaaaaaa-0000-0000-0000-000000000003', 60)->>'unit_price'), '10000');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Le vendeur voit ses 2 demandes', (select count(*)::text from public.wholesale_requests), '2');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.eq('Un tiers ne voit aucune demande', (select count(*)::text from public.wholesale_requests), '0');
select tests.as_db();
select tests.eq('Commission grossiste avec affilié : 3 % / 5 % / 92 %', (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.wholesale_split(100000, true)), '3000/5000/92000');
select tests.eq('Commission grossiste sans affilié : 3 % / 0 / 97 %', (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.wholesale_split(100000, false)), '3000/0/97000');
select tests.eq('Entiers : 99999 -> 2999 / 4999 / 92001', (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.wholesale_split(99999, true)), '2999/4999/92001');
update public.profiles set is_blocked = true where id = '11111111-1111-1111-1111-111111111111';
select tests.as_anon();
select tests.eq('Vendeur bloqué : produit grossiste masqué', (select count(*)::text from public.wholesale_products), '0');
select tests.as_db();
update public.profiles set is_blocked = false where id = '11111111-1111-1111-1111-111111111111';

\echo ===== International =====
select tests.as_anon();
select tests.eq('Liste d''attente : 1re inscription = position 1', public.join_waitlist('GA', '+241 06 12 34 56')::text, '1');
select tests.eq('Même numéro deux fois : pas de doublon', public.join_waitlist('GA', '+24106123456')::text, '1');
select tests.eq('2e personne : position 2', public.join_waitlist('GA', '074123456')::text, '2');
select tests.raises('Cameroun n''est pas une liste d''attente', $$select public.join_waitlist('CM', '699000111')$$, 'pays_invalide');
select tests.raises('Téléphone invalide', $$select public.join_waitlist('SN', 'abc')$$, 'telephone_invalide');
select tests.raises('Anonyme ne lit pas la liste', $$select * from public.waitlist_international$$, 'permission');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin lit la liste', (select count(*)::text from public.waitlist_international), '2');
select tests.as_db();
select tests.eq('product_locations : villes recopiées', (select (count(*) > 0)::text from public.product_locations), 'true');

\echo ===== Litiges =====
update public.products set stock = 50 where id = 'aaaaaaaa-0000-0000-0000-000000000003';
select tests.as_service();
select tests.checkout('FL-1', 'aaaaaaaa-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'acheteur@t.cm', 1, 'pickup_douala', null, '699111222', null) \gset
select public.confirm_fapshi_payment('FL-1', 15000, 'mobile money', 14500)->>'status' as st \gset l1_
select tests.eq('Commande physique payée', :'l1_st', 'paid');
select tests.as_db();
select order_id as oid from public.transactions where fapshi_trans_id = 'FL-1' \gset
select tests.as_user('33333333-3333-3333-3333-333333333333');
select public.buyer_open_dispute(:'oid', 'Le sac est abîmé');
select tests.eq('Litige copié dans disputes (en_attente)', (select status || '/' || reason from public.disputes where order_id = :'oid'), 'en_attente/Le sac est abîmé');
select public.dispute_attach_photo(:'oid', :'oid' || '/buyer.jpg');
select tests.raises('Photo d''un autre dossier refusée', format($$select public.dispute_attach_photo(%L, %L)$$, :'oid', '55555555-5555-5555-5555-555555555555/x.jpg'), 'fichier_invalide');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.dispute_attach_photo(:'oid', :'oid' || '/seller.jpg');
select tests.eq('Les 2 photos sont enregistrées', (select (photo_buyer is not null and photo_seller is not null)::text from public.disputes where order_id = :'oid'), 'true');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.raises('Un tiers ne peut pas joindre de photo', format($$select public.dispute_attach_photo(%L, %L)$$, :'oid', :'oid' || '/x.jpg'), 'acces_refuse');
select tests.raises('Un tiers ne peut pas décider', $$select public.admin_dispute_decide(gen_random_uuid(), 'refund')$$, 'acces_refuse');
select tests.as_db();
select id as did from public.disputes where order_id = :'oid' \gset
select balance_pending as sp from public.wallets where user_id = '11111111-1111-1111-1111-111111111111' \gset
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_dispute_decide(:'did', 'refund');
select tests.as_db();
select tests.eq('Remboursé : statut du litige', (select status from public.disputes where id = :'did'), 'remboursé');
select tests.eq('Remboursé : transaction refunded', (select status from public.transactions where fapshi_trans_id = 'FL-1'), 'refunded');
select tests.eq('Remboursé : le vendeur perd la vente en attente', (select (:sp - balance_pending)::text from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), '14550');

-- litige refusé
select tests.as_service();
select tests.checkout('FL-2', 'aaaaaaaa-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'acheteur@t.cm', 1, 'pickup_douala', null, '699111222', null) \gset
select public.confirm_fapshi_payment('FL-2', 15000, 'mobile money', 14500)->>'status' as st \gset l2_
select tests.as_db();
select order_id as oid2 from public.transactions where fapshi_trans_id = 'FL-2' \gset
update public.orders set status = 'confirmed' where id = :'oid2';
update public.orders set status = 'ready_for_pickup' where id = :'oid2';
update public.orders set status = 'delivered', delivered_at = now() where id = :'oid2';
select tests.as_user('33333333-3333-3333-3333-333333333333');
select public.buyer_open_dispute(:'oid2', 'Pas conforme');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_dispute_decide((select id from public.disputes where order_id = :'oid2'), 'reject');
select tests.as_db();
select tests.eq('Refusé : statut', (select status from public.disputes where order_id = :'oid2'), 'refusé');
select tests.eq('Refusé : la commande n''est plus en litige', (select disputed::text from public.orders where id = :'oid2'), 'false');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Décider deux fois impossible', $$select public.admin_dispute_decide((select id from public.disputes where order_id = (select order_id from public.transactions where fapshi_trans_id = 'FL-2')), 'reject')$$, 'litige_introuvable');
select tests.as_user('22222222-2222-2222-2222-222222222222');
select tests.eq('Un tiers ne voit pas les litiges des autres', (select count(*)::text from public.disputes), '0');
select 'FAILS=' || tests.fail_count();
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin : nombre d''affiliés lisible', (select (public.admin_affiliate_count() >= 0)::text), 'true');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin : nombre d''affiliés refusé', $$select public.admin_affiliate_count()$$, 'acces_refuse');
select tests.as_anon();
select tests.eq('Stats publiques vendeur lisibles', (select (count(*) > 0)::text from public.seller_public_stats), 'true');

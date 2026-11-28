-- Tests V3.1 : GUEST CHECKOUT (physique sans compte, digital avec compte, code KDDF-XXXX, suivi, litige, anti-fraude téléphone).
-- À lancer APRÈS 10 à 70 (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = true, hold_days = 7;
update public.commission_settings set is_launch_mode = true, launch_start_date = current_date, launch_end_date = current_date + 30, platform_fee_percent = 0;
insert into public.products (id, seller_id, product_type, title, slug, price, is_published, affiliate_percent, stock, images, whatsapp_seller, delivery_options, moderation_status) values
 ('bbbbbbbb-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111', 'physical', 'Sac guest', 'sac-guest', 10000, true, 20, 100, array['https://img/g.jpg'], '699000111',
  '{"pickup_douala":{"enabled":true,"price":0},"delivery_douala":{"enabled":true,"price":1000},"shipping_cameroon":{"enabled":true,"price":2500}}', 'approved')
 on conflict (id) do nothing;
update public.products set affiliate_enabled = true where id = 'bbbbbbbb-0000-0000-0000-0000000000a1';
update public.profiles set fraud_review = false, is_blocked = false;
update public.profiles set phone = '699000111', whatsapp = '699000111' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set phone = '677888999', whatsapp = '677888999' where id = '22222222-2222-2222-2222-222222222222';
select referral_code from public.profiles where id = '22222222-2222-2222-2222-222222222222' \gset g_aff_
delete from public.orders where phone is not null and created_at > now() - interval '1 hour';

\echo ===== G1 : produit PHYSIQUE sans compte =====
select tests.as_service();
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Awa Ngono', 1, 'pickup_douala', null, '+237 655 123 456', :'g_aff_referral_code', 'online', 'Douala', 'Akwa', '10.0.0.1')::text as g1 \gset
select (:'g1'::jsonb)->>'order_code' as g1_code, (:'g1'::jsonb)->>'transaction_id' as g1_tx, (:'g1'::jsonb)->>'order_id' as g1_order \gset
select tests.eq('Guest : code au format KDDF-XXXX', (:'g1_code' ~ '^KDDF-[0-9]{4}$')::text, 'true');
select tests.eq('Guest : réponse marquée invité', (:'g1'::jsonb)->>'guest', 'true');
select tests.eq('Guest : order_code enregistré dans transactions', (select order_code from public.transactions where id = :'g1_tx'), :'g1_code');
select tests.eq('Guest : aucun compte (buyer_id vide)', (select (buyer_id is null)::text from public.orders where id = :'g1_order'), 'true');
select tests.eq('Guest : compte invité créé en arrière-plan, lié au numéro', (select count(*)::text from public.guest_accounts where phone_key = '655123456'), '1');
select tests.eq('Guest : commande liée au compte invité', (select (guest_id is not null)::text from public.orders where id = :'g1_order'), 'true');
select tests.eq('Guest : adresse = Quartier, Ville', (select delivery_address from public.orders where id = :'g1_order'), 'Akwa, Douala');
select tests.eq('Guest : email technique (pas d''email demandé)', (select (buyer_email like 'invite-%@example.com')::text from public.orders where id = :'g1_order'), 'true');
select tests.eq('Guest : adresse IP mémorisée', (select client_ip from public.orders where id = :'g1_order'), '10.0.0.1');
update public.transactions set fapshi_trans_id = 'G1-PAY', fapshi_link = 'https://pay.test/G1' where id = :'g1_tx';
select public.confirm_fapshi_payment('G1-PAY', 10000, 'mobile money', 9700)->>'status' as st \gset g1_
select tests.eq('Guest : paiement confirmé', :'g1_st', 'paid');
select tests.eq('Guest : répartition 10 000 = plateforme 0 / affilié 2 000 / vendeur 8 000 (cookie affilié, sans compte)',
  (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.transactions where id = :'g1_tx'), '0/2000/8000');
select tests.eq('Guest : statut de la commande En attente après paiement', (select status from public.orders where id = :'g1_order'), 'pending');

\echo ===== G2 : suivi avec Numéro + Code =====
select tests.eq('Suivi : bon numéro + bon code = trouvé', (public.guest_track_order('655123456', :'g1_code')->>'found'), 'true');
select tests.eq('Suivi : formats de numéro différents acceptés', (public.guest_track_order('+237655123456', lower(:'g1_code'))->>'found'), 'true');
select tests.eq('Suivi : statut affiché = pending (En attente)', (public.guest_track_order('655123456', :'g1_code')->>'status'), 'pending');
select tests.eq('Suivi : mauvais numéro = introuvable', (public.guest_track_order('699999999', :'g1_code')->>'found'), 'false');
select tests.eq('Suivi : mauvais code = introuvable', (public.guest_track_order('655123456', 'KDDF-0000')->>'found'), 'false');
select tests.eq('Suivi : code vide = introuvable', (public.guest_track_order('655123456', '')->>'found'), 'false');
select tests.eq('Suivi : ne révèle pas l''email technique ni le vendeur', (public.guest_track_order('655123456', :'g1_code') ? 'buyer_email')::text, 'false');
select tests.eq('Suivi : litige possible (payé, fonds retenus)', (public.guest_track_order('655123456', :'g1_code')->>'can_dispute'), 'true');
select tests.eq('Suivi : « reçu » pas encore possible (non expédié)', (public.guest_track_order('655123456', :'g1_code')->>'can_confirm'), 'false');
select tests.raises('Réception : refusée avant expédition', $$select public.guest_confirm_delivery('655123456', (select order_code from public.transactions where fapshi_trans_id = 'G1-PAY'))$$, 'commande_invalide');
-- le vendeur expédie
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.seller_update_order_status(:'g1_order', 'confirmed');
select public.seller_update_order_status(:'g1_order', 'ready_for_pickup');
select tests.as_service();
select tests.eq('Suivi : prête pour retrait (En livraison)', (public.guest_track_order('655123456', :'g1_code')->>'status'), 'ready_for_pickup');
select tests.eq('Suivi : « reçu » possible une fois expédié', (public.guest_track_order('655123456', :'g1_code')->>'can_confirm'), 'true');
select tests.raises('Réception : mauvais numéro refusé', format($$select public.guest_confirm_delivery('699999999', %L)$$, :'g1_code'), 'commande_introuvable');
select public.guest_confirm_delivery('655123456', :'g1_code');
select tests.eq('Réception sans compte : commande Livrée', (select status from public.orders where id = :'g1_order'), 'delivered');
select tests.eq('Réception sans compte : libération planifiée (délai de garantie de 7 jours respecté)', (select (release_at <> 'infinity' and release_at >= paid_at + interval '7 days' - interval '1 minute')::text from public.transactions where id = :'g1_tx'), 'true');

\echo ===== G3 : litige sans compte (Nom + Numéro + Code + photos) =====
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Paul Ekani', 1, 'delivery_douala', null, '690 111 222', null, 'online', 'Douala', 'Bonamoussadi', '10.0.0.2')::text as g3 \gset
select (:'g3'::jsonb)->>'order_code' as g3_code, (:'g3'::jsonb)->>'transaction_id' as g3_tx, (:'g3'::jsonb)->>'order_id' as g3_order \gset
update public.transactions set fapshi_trans_id = 'G3-PAY' where id = :'g3_tx';
select public.confirm_fapshi_payment('G3-PAY', 11000, 'orange money', 10700)->>'status' as st \gset g3_
select tests.eq('Litige : commande livraison payée (prix + livraison)', :'g3_st', 'paid');
select tests.raises('Litige : motif trop court refusé', format($$select public.guest_open_dispute('690111222', %L, 'x', '{}')$$, :'g3_code'), 'motif_invalide');
select tests.raises('Litige : photo hors du dossier de la commande refusée', format($$select public.guest_open_dispute('690111222', %L, 'Produit non conforme', array['autre/x.jpg'])$$, :'g3_code'), 'fichier_invalide');
select tests.raises('Litige : plus de 3 photos refusé', format($$select public.guest_open_dispute('690111222', %L, 'Produit non conforme', array[%L,%L,%L,%L])$$, :'g3_code', :'g3_order' || '/1.jpg', :'g3_order' || '/2.jpg', :'g3_order' || '/3.jpg', :'g3_order' || '/4.jpg'), 'trop_de_photos');
select tests.raises('Litige : mauvais numéro refusé', format($$select public.guest_open_dispute('699999999', %L, 'Produit non conforme', '{}')$$, :'g3_code'), 'commande_introuvable');
select public.guest_open_dispute('690111222', :'g3_code', 'Produit non conforme à la photo', array[:'g3_order' || '/a.jpg', :'g3_order' || '/b.jpg']) is not null as ok \gset g3_
select tests.eq('Litige : ouvert', (select disputed::text from public.orders where id = :'g3_order'), 'true');
select tests.eq('Litige : fiche créée avec Nom', (select buyer_name from public.disputes where order_id = :'g3_order'), 'Paul Ekani');
select tests.eq('Litige : fiche créée avec Numéro', (select buyer_phone from public.disputes where order_id = :'g3_order'), '690 111 222');
select tests.eq('Litige : fiche créée avec Code KDDF-XXXX', (select order_code from public.disputes where order_id = :'g3_order'), :'g3_code');
select tests.eq('Litige : 2 photos enregistrées', (select cardinality(buyer_photos)::text from public.disputes where order_id = :'g3_order'), '2');
select tests.eq('Litige : fiche liée au compte invité', (select (guest_id is not null)::text from public.disputes where order_id = :'g3_order'), 'true');
select tests.raises('Litige : un 2e litige est refusé', format($$select public.guest_open_dispute('690111222', %L, 'Encore un problème', '{}')$$, :'g3_code'), 'litige_deja_ouvert');
select tests.eq('Suivi : litige visible', (public.guest_track_order('690111222', :'g3_code')->>'dispute_status'), 'en_attente');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin : voit le litige avec Nom + Numéro + Code', (select count(*)::text from public.disputes where order_code = :'g3_code' and buyer_name is not null and buyer_phone is not null), '1');
select tests.eq('Admin : preuve de paiement (montant + ID Fapshi) disponible', (select t.total_amount || '/' || t.fapshi_trans_id from public.disputes d join public.transactions t on t.order_id = d.order_id where d.order_code = :'g3_code'), '11000/G3-PAY');
select tests.eq('Admin : voit le compte invité', (select count(*)::text from public.guest_accounts where phone_key = '690111222'), '1');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.eq('Un utilisateur normal ne voit aucun compte invité (RLS)', (select count(*)::text from public.guest_accounts), '0');
select tests.eq('Un utilisateur normal ne voit pas le litige d''un invité', (select count(*)::text from public.disputes where order_code = :'g3_code'), '0');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Le vendeur voit le litige de sa vente', (select count(*)::text from public.disputes where order_code = :'g3_code'), '1');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_dispute_decide((select id from public.disputes where order_code = :'g3_code'), 'refund');
select tests.as_service();
select tests.eq('Litige invité : remboursement décidé par l''admin', (select status from public.disputes where order_code = :'g3_code'), 'remboursé');

\echo ===== G4 : produit DIGITAL : compte obligatoire =====
select tests.raises('Digital sans compte : refusé', $$select public.create_checkout_order('aaaaaaaa-0000-0000-0000-000000000001', null, 'client@t.cm', 'Client', 1, null, null, null, null)$$, 'compte_requis_digital');
select tests.raises('Digital sans compte et sans email : refusé (compte requis d''abord)', $$select public.create_checkout_order('aaaaaaaa-0000-0000-0000-000000000001', null, null, 'Client', 1, null, null, null, null)$$, 'compte_requis_digital');
select tests.eq('Digital avec compte : accepté', (public.create_checkout_order('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'acheteur@t.cm', 'Acheteur', 1, null, null, null, null)->>'product_type'), 'digital');
select tests.eq('Digital : aucun code KDDF (réservé au physique)', (select count(*)::text from public.transactions t join public.orders o on o.id = t.order_id where o.delivery_method is null and t.order_code is not null), '0');
select tests.eq('Digital : aucun compte invité créé', (select count(*)::text from public.guest_accounts where phone_key is null), '0');

\echo ===== G5 : validations de l'achat sans compte =====
select tests.raises('Guest : nom obligatoire', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, '', 1, 'pickup_douala', null, '655000001', null, 'online', 'Douala', 'Akwa')$$, 'nom_invalide');
select tests.raises('Guest : ville obligatoire', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Awa Ngono', 1, 'pickup_douala', null, '655000001', null, 'online', '', 'Akwa')$$, 'ville_invalide');
select tests.raises('Guest : quartier obligatoire', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Awa Ngono', 1, 'pickup_douala', null, '655000001', null, 'online', 'Douala', '')$$, 'quartier_invalide');
select tests.raises('Guest : téléphone obligatoire', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Awa Ngono', 1, 'pickup_douala', null, '', null, 'online', 'Douala', 'Akwa')$$, 'telephone_invalide');
select tests.raises('Guest : un email fourni mais invalide est refusé', $$select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, 'pas-un-email', 'Awa Ngono', 1, 'pickup_douala', null, '655000001', null, 'online', 'Douala', 'Akwa')$$, 'email_invalide');
select tests.eq('Guest : le même numéro réutilise le MÊME compte invité', (select count(*)::text from public.guest_accounts where phone_key = '655123456'), '1');
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Awa N.', 1, 'pickup_douala', null, '655 123 456', null, 'online', 'Yaoundé', 'Mvan') is not null as ok \gset g5_
select tests.eq('Guest : compte invité mis à jour (2 commandes)', (select orders_count::text from public.guest_accounts where phone_key = '655123456'), '2');
select tests.eq('Guest : cod accepté sans compte', (public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Awa N.', 1, 'pickup_douala', null, '655 000 009', null, 'cod', 'Douala', 'Akwa')->>'order_code' ~ '^KDDF-[0-9]+$')::text, 'true');

\echo ===== G6 : anti-fraude par TÉLÉPHONE =====
-- 6a. numéro acheteur = numéro affilié => commission 0 (même sans compte), journal « bloqué » dans /admin/fraude
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Faux Client', 1, 'pickup_douala', null, '+237 677 888 999', :'g_aff_referral_code', 'online', 'Douala', 'Akwa', '10.0.0.9')::text as g6 \gset
select (:'g6'::jsonb)->>'transaction_id' as g6_tx, (:'g6'::jsonb)->>'order_id' as g6_order \gset
update public.transactions set fapshi_trans_id = 'G6-PAY' where id = :'g6_tx';
select public.confirm_fapshi_payment('G6-PAY', 10000, 'mobile money', 9700)->>'status' as st \gset g6_
select tests.eq('Numéro acheteur = numéro affilié : vente normale', :'g6_st', 'paid');
select tests.eq('Numéro acheteur = numéro affilié : commission = 0', (select affiliate_fee::text from public.transactions where id = :'g6_tx'), '0');
select tests.eq('Numéro acheteur = numéro affilié : le vendeur reçoit tout (plateforme 0 %)', (select seller_amount::text from public.transactions where id = :'g6_tx'), '10000');
select tests.eq('Numéro acheteur = numéro affilié : journal fraud_logs bloqué, score 100', (select action || '/' || risk_score from public.fraud_logs where order_id = :'g6_order' limit 1), 'blocked/100');
select tests.eq('Numéro acheteur = numéro affilié : motif « même téléphone »', (select (reason like '%même téléphone%')::text from public.fraud_logs where order_id = :'g6_order' limit 1), 'true');
-- 6b. plus de 5 commandes en 1 h avec le même numéro => bloqué
delete from public.fraud_logs;
select count(*) as nb from (select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Spam ' || i, 1, 'pickup_douala', null, '650 000 777', null, 'online', 'Douala', 'Akwa') from generate_series(1, 5) i) q \gset
select tests.eq('Même numéro : 5 commandes en 1 h acceptées', (select count(*)::text from public.orders where public.fraud_phone_key(phone) = '650000777'), '5');
select (public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Spam 6', 1, 'pickup_douala', null, '+237650000777', null, 'online', 'Douala', 'Akwa')) ->> 'blocked' as blk \gset g6_
select tests.eq('Même numéro : la 6e commande en 1 h est BLOQUÉE', :'g6_blk', 'true');
select tests.eq('Même numéro : aucune 6e commande créée', (select count(*)::text from public.orders where public.fraud_phone_key(phone) = '650000777'), '5');
select tests.eq('Même numéro : blocage enregistré dans fraud_logs', (select count(*)::text from public.fraud_logs where action = 'blocked' and reason like 'Plus de 5 commandes en 1 h%'), '1');
-- un autre numéro n'est pas affecté
select tests.eq('Autre numéro : non bloqué', (public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Autre', 1, 'pickup_douala', null, '650 000 888', null, 'online', 'Douala', 'Akwa')->>'blocked' is null)::text, 'true');
-- après 1 h, le numéro est de nouveau accepté
update public.orders set created_at = now() - interval '2 hours' where public.fraud_phone_key(phone) = '650000777';
select tests.eq('Même numéro : accepté de nouveau après 1 h', (public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Spam 7', 1, 'pickup_douala', null, '650 000 777', null, 'online', 'Douala', 'Akwa')->>'blocked' is null)::text, 'true');
-- 6c. si l'anti-fraude plante : allowed = true (la commande passe)
select tests.as_db();
create or replace function public.fraud_active() returns boolean language plpgsql stable as $$ begin raise exception 'panne simulée'; end $$;
select tests.as_service();
select tests.eq('Panne anti-fraude : la commande passe quand même (allowed: true)', (public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000a1', null, null, 'Client Panne', 1, 'pickup_douala', null, '655 111 000', null, 'online', 'Douala', 'Akwa')->>'order_code' is not null)::text, 'true');
select tests.as_db();
create or replace function public.fraud_active() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_active from public.fraud_settings where id = 1), false)
$$;
select tests.as_service();

\echo
select 'ÉCHECS: ' || tests.fail_count();

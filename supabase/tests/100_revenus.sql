-- Tests V3.3 : REVENUS (commission par vendeur : normal / Pro / exempté, abonnement Pro, frais de retrait, boosts 14/30 jours, bannières).
-- À lancer APRÈS 10 à 90 (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = false;
update public.profiles set fraud_review = false, is_blocked = false, commission_exempt = false;
delete from public.pro_subscriptions;
-- Lancement terminé : plateforme 3 % ; Pro 1,5 %
update public.commission_settings set is_launch_mode = true, launch_start_date = current_date - 40, launch_end_date = current_date - 10, platform_fee_percent = 3, after_launch_percent = 3, pro_percent = 1.5;
insert into public.products (id, seller_id, product_type, title, slug, price, is_published, affiliate_percent, stock, images, whatsapp_seller, delivery_options, moderation_status) values
 ('bbbbbbbb-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111', 'physical', 'Sac Revenus', 'sac-revenus', 10000, true, 20, 500, array['https://img/p.jpg'], '699000111',
  '{"pickup_douala":{"enabled":true,"price":0}}', 'approved')
 on conflict (id) do nothing;

-- Vend 1 produit (10 000 FCFA) et renvoie « frais plateforme/taux/montant vendeur »
create or replace function tests.sale100(p_trans text, p_phone text) returns text language plpgsql security definer as $$
declare r jsonb; v_tx uuid;
begin
  update public.orders set created_at = created_at - interval '2 hours' where public.fraud_phone_key(phone) = public.fraud_phone_key(p_phone) and created_at > now() - interval '1 hour';
  r := public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', null, null, 'Client Revenus', 1, 'pickup_douala', null, p_phone, null, 'online', 'Douala', 'Bonapriso', '10.2.2.2');
  v_tx := (r->>'transaction_id')::uuid;
  update public.transactions set fapshi_trans_id = p_trans, fapshi_link = 'https://pay.test/' || p_trans where id = v_tx;
  perform public.confirm_fapshi_payment(p_trans, 10000, 'mtn', null);
  return (select platform_fee || '/' || platform_fee_rate || '/' || seller_amount from public.transactions where id = v_tx);
end $$;

\echo ===== R1 : commission par vendeur =====
select tests.as_service();
select tests.eq('Vendeur normal après lancement : 3 % = 300 / 3.00 / 9700', tests.sale100('rev-1', '+237 655 000 101'), '300/3.00/9700');

select tests.as_db();
insert into public.pro_subscriptions (user_id, amount, status, fapshi_trans_id, starts_at, ends_at, paid_at)
values ('11111111-1111-1111-1111-111111111111', 3000, 'paid', 'pro-test-1', now() - interval '1 hour', now() + interval '29 days', now());
select tests.eq('is_pro vrai pour un abonné actif', public.is_pro('11111111-1111-1111-1111-111111111111')::text, 'true');
select tests.as_service();
select tests.eq('Vendeur Pro : 1,5 % = 150 / 1.50 / 9850', tests.sale100('rev-2', '+237 655 000 102'), '150/1.50/9850');

select tests.as_db();
update public.pro_subscriptions set ends_at = now() - interval '1 minute';
select tests.eq('is_pro faux quand l''abonnement est expiré', public.is_pro('11111111-1111-1111-1111-111111111111')::text, 'false');
select tests.as_service();
select tests.eq('Pro expiré : retour à 3 % = 300', tests.sale100('rev-3', '+237 655 000 103'), '300/3.00/9700');

select tests.as_db();
update public.profiles set commission_exempt = true where id = '11111111-1111-1111-1111-111111111111';
select tests.as_service();
select tests.eq('Compte exempté : 0 % = 0 / 0.00 / 10000', tests.sale100('rev-4', '+237 655 000 104'), '0/0.00/10000');

select tests.as_db();
update public.pro_subscriptions set ends_at = now() + interval '5 days';
select tests.as_service();
select tests.eq('Exempté ET Pro : toujours 0 %', tests.sale100('rev-5', '+237 655 000 105'), '0/0.00/10000');

select tests.as_db();
update public.profiles set commission_exempt = false where id = '11111111-1111-1111-1111-111111111111';
update public.commission_settings set launch_start_date = current_date, launch_end_date = current_date + 30;
select tests.as_service();
select tests.eq('Pendant le lancement : Pro = 0 % (jamais plus que le taux en cours)', tests.sale100('rev-6', '+237 655 000 106'), '0/0.00/10000');

select tests.as_db();
update public.commission_settings set launch_start_date = current_date - 40, launch_end_date = current_date - 10, after_launch_percent = 5, platform_fee_percent = 5;
update public.pro_subscriptions set ends_at = now() - interval '1 minute';
select tests.as_service();
select tests.eq('Taux normal 5 % = 500', tests.sale100('rev-7', '+237 655 000 107'), '500/5.00/9500');
select tests.as_db();
update public.pro_subscriptions set ends_at = now() + interval '5 days';
select tests.as_service();
select tests.eq('Pro avec taux normal 5 % : 1,5 % = 150', tests.sale100('rev-8', '+237 655 000 108'), '150/1.50/9850');
select tests.as_db();
update public.commission_settings set after_launch_percent = 1, platform_fee_percent = 1;
select tests.as_service();
select tests.eq('Pro ne paie jamais PLUS que le taux normal (normal 1 % : Pro 1 % = 100)', tests.sale100('rev-9', '+237 655 000 109'), '100/1.00/9900');
select tests.as_db();
update public.commission_settings set after_launch_percent = 3, platform_fee_percent = 3;

\echo ===== R2 : sécurité de l'exemption =====
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.raises('Un vendeur ne peut pas s''exempter lui-même', $$update public.profiles set commission_exempt = true where id = '11111111-1111-1111-1111-111111111111'$$, 'permission');
select tests.raises('Un vendeur ne peut pas appeler admin_set_commission_exempt', $$select public.admin_set_commission_exempt('seller@t.cm', true)$$, 'acces_refuse');
select tests.raises('Un vendeur ne peut pas modifier un taux Pro', $$update public.commission_settings set pro_percent = 0$$, 'permission');
select tests.raises('Un vendeur ne peut pas appeler seller_platform_rate', $$select public.seller_platform_rate('11111111-1111-1111-1111-111111111111')$$, 'permission');
select tests.raises('Un vendeur ne peut pas créer un abonnement Pro', $$insert into public.pro_subscriptions (user_id, amount, status) values ('11111111-1111-1111-1111-111111111111', 3000, 'paid')$$, 'permission');
select tests.as_anon();
select tests.raises('Anonyme ne peut pas appeler confirm_pro_payment', $$select public.confirm_pro_payment('x', 3000)$$, 'permission');
select tests.as_db();
select email as seller_email from auth.users where id = '11111111-1111-1111-1111-111111111111' \gset
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_commission_exempt(:'seller_email', true);
select tests.as_db();
select tests.eq('Admin : exemption enregistrée', (select commission_exempt::text from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'true');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_commission_exempt(upper(:'seller_email'), false);
select tests.as_db();
select tests.eq('Admin : exemption retirée (e-mail insensible à la casse)', (select commission_exempt::text from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'false');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Admin : e-mail inconnu refusé', $$select public.admin_set_commission_exempt('personne@nulle.part', true)$$, 'utilisateur_introuvable');

\echo ===== R3 : paiement de l'abonnement Pro =====
select tests.as_db();
delete from public.pro_subscriptions;
insert into public.pro_subscriptions (user_id, amount, fapshi_trans_id) values
 ('22222222-2222-2222-2222-222222222222', 3000, 'pro-a'),
 ('22222222-2222-2222-2222-222222222222', 3000, 'pro-b'),
 ('33333333-3333-3333-3333-333333333333', 3000, 'pro-c');
select tests.as_service();
select public.confirm_pro_payment('pro-a', 3000)->>'status' as st \gset r3_
select tests.eq('Abonnement : paiement confirmé', :'r3_st', 'paid');
select tests.as_db();
select tests.eq('Abonnement : dure 30 jours', (select (ends_at::date - starts_at::date)::text from public.pro_subscriptions where fapshi_trans_id = 'pro-a'), '30');
select tests.eq('Abonné actif', public.is_pro('22222222-2222-2222-2222-222222222222')::text, 'true');
select tests.as_service();
select public.confirm_pro_payment('pro-a', 3000)->>'status' as st2 \gset r3_
select tests.eq('Abonnement : paiement rejoué = déjà traité', :'r3_st2', 'already');
select public.confirm_pro_payment('pro-b', 3000)->>'status' as st3 \gset r3_
select tests.as_db();
select tests.eq('Renouvellement : s''ajoute à la fin de l''abonnement en cours (60 jours au total)', (select (max(ends_at)::date - current_date)::text from public.pro_subscriptions where user_id = '22222222-2222-2222-2222-222222222222' and status = 'paid'), '60');
select tests.as_service();
select public.confirm_pro_payment('pro-c', 2999)->>'status' as st4 \gset r3_
select tests.eq('Montant différent : à vérifier, abonnement NON activé', :'r3_st4', 'review');
select tests.as_db();
select tests.eq('Montant différent : pas Pro', public.is_pro('33333333-3333-3333-3333-333333333333')::text, 'false');
select tests.as_service();
select tests.raises('Abonnement inconnu refusé', $$select public.confirm_pro_payment('inconnu', 3000)$$, 'abonnement_inconnu');
select tests.as_db();
insert into public.pro_subscriptions (user_id, amount, fapshi_trans_id) values ('33333333-3333-3333-3333-333333333333', 3000, 'pro-d');
select tests.as_service();
select public.mark_pro_failed('pro-d', 'FAILED');
select tests.as_db();
select tests.eq('Paiement échoué : statut failed', (select status from public.pro_subscriptions where fapshi_trans_id = 'pro-d'), 'failed');
select tests.as_user('22222222-2222-2222-2222-222222222222');
select tests.eq('L''abonné voit son abonnement', (select count(*)::text from public.pro_subscriptions), '2');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.eq('Un autre vendeur ne voit pas celui des autres', (select count(*)::text from public.pro_subscriptions where user_id = '22222222-2222-2222-2222-222222222222'), '0');
select tests.as_anon();
select tests.eq('Le public voit seulement les Pro actifs (badge)', (select count(*)::text from public.active_pro), '1');

\echo ===== R4 : frais de retrait =====
select tests.as_db();
update public.wallets set balance_available = 500000, commission_due = 0, total_withdrawn = 0 where user_id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(10000, 'mtn_momo', '699000111') as w1 \gset
select public.request_withdrawal(100000, 'orange_money', '699000111') as w2 \gset
select public.request_withdrawal(1000, 'mtn_momo', '699000111') as w3 \gset
select tests.as_db();
select tests.eq('Retrait 10 000 : 1,5 % = 150 < minimum 200 => frais 200', (select fee::text from public.withdrawals where id = :'w1'), '200');
select tests.eq('Retrait 100 000 : 1,5 % = 1 500', (select fee::text from public.withdrawals where id = :'w2'), '1500');
select tests.eq('Retrait 1 000 : frais minimum 200', (select fee::text from public.withdrawals where id = :'w3'), '200');
select tests.eq('Le solde est débité du montant demandé (frais déduits du paiement, pas du solde)', (select balance_available::text from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), '389000');
update public.wallets set commission_due = 500 where user_id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(1000, 'mtn_momo', '699000111') as w4 \gset
select tests.as_db();
select tests.eq('Commission cash 500 déduite d''abord, puis frais 200 sur le reste', (select commission_deducted || '/' || fee from public.withdrawals where id = :'w4'), '500/200');
update public.wallets set commission_due = 1000 where user_id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(1000, 'mtn_momo', '699000111') as w5 \gset
select tests.as_db();
select tests.eq('Commission cash = tout le montant : aucun frais, jamais de paiement négatif', (select commission_deducted || '/' || fee from public.withdrawals where id = :'w5'), '1000/0');
update public.profiles set commission_exempt = true where id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(20000, 'mtn_momo', '699000111') as w6 \gset
select tests.as_db();
select tests.eq('Compte exempté : aucun frais de retrait', (select fee::text from public.withdrawals where id = :'w6'), '0');
update public.profiles set commission_exempt = false where id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_process_withdrawal(:'w1', 'paid', 'ok');
select public.admin_process_withdrawal(:'w2', 'failed', 'refus');
select tests.as_db();
select tests.eq('Retrait refusé : solde rendu en entier', (select balance_available::text from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), '467000');
select tests.eq('Total retiré = montants payés', (select total_withdrawn::text from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), '10000');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select (select coalesce(sum(fee), 0) from public.withdrawals where status = 'paid')::text as fees_paid \gset
select tests.eq('Admin : frais de retrait encaissés = somme des retraits PAYÉS (le refusé ne compte pas)', (public.admin_overview()->>'withdrawal_fees'), :'fees_paid');
select tests.eq('Les frais comptés incluent bien celui du retrait payé (200) et pas celui du refusé (1 500)', ((public.admin_overview()->>'withdrawal_fees')::bigint >= 200 and not exists (select 1 from public.withdrawals where id = :'w2' and status = 'paid'))::text, 'true');
select tests.eq('Admin : revenus Pro = 6 000 (2 abonnements payés, le 3e est à vérifier)', (public.admin_overview()->>'pro_revenue'), '6000');

\echo ===== R5 : boosts 14 et 30 jours =====
select tests.as_db();
insert into public.product_boosts (product_id, seller_id, plan, amount, fapshi_trans_id) values
 ('bbbbbbbb-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111', '14d', 4500, 'bo-14'),
 ('bbbbbbbb-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111', '30d', 8000, 'bo-30');
select tests.as_service();
select public.confirm_boost_payment('bo-14', 4500)->>'status' as b1 \gset r5_
select public.confirm_boost_payment('bo-30', 8000)->>'status' as b2 \gset r5_
select tests.as_db();
select tests.eq('Boost 14 jours confirmé', :'r5_b1', 'paid');
select tests.eq('Boost 14 jours : durée 14 j', (select (ends_at::date - starts_at::date)::text from public.product_boosts where fapshi_trans_id = 'bo-14'), '14');
select tests.eq('Boost 30 jours : commence à la fin du précédent et dure 30 j', (select (ends_at::date - starts_at::date)::text || '/' || (starts_at::date - current_date)::text from public.product_boosts where fapshi_trans_id = 'bo-30'), '30/14');
select tests.raises('Formule inconnue refusée', $$insert into public.product_boosts (product_id, seller_id, plan, amount) values ('bbbbbbbb-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111', '60d', 9000)$$, 'check');

\echo ===== R6 : bannières sponsorisées =====
select tests.as_user('44444444-4444-4444-4444-444444444444');
insert into public.site_banners (title, body, link_url, label) values ('Promo Orange', 'Offre partenaire', 'https://exemple.com', 'Sponsorisé');
insert into public.site_banners (title, link_url, is_active) values ('Brouillon', '/services', false);
insert into public.site_banners (title, starts_at) values ('Bientôt', now() + interval '2 days');
insert into public.site_banners (title, ends_at) values ('Terminée', now() - interval '1 day');
select tests.eq('Admin voit toutes les bannières', (select count(*)::text from public.site_banners), '4');
select tests.raises('Lien dangereux refusé (javascript:)', $$insert into public.site_banners (title, link_url) values ('Mal', 'javascript:alert(1)')$$, 'check');
select tests.raises('Lien // refusé', $$insert into public.site_banners (title, link_url) values ('Mal2', '//evil.com')$$, 'check');
select tests.raises('Image http (non sécurisée) refusée', $$insert into public.site_banners (title, image_url) values ('Mal3', 'http://x.com/a.png')$$, 'check');
select tests.as_anon();
select tests.eq('Public : seulement la bannière active et dans ses dates', (select string_agg(title, ',') from public.site_banners), 'Promo Orange');
select tests.raises('Public ne peut pas créer de bannière', $$insert into public.site_banners (title) values ('Pirate')$$, 'permission');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.raises('Un vendeur ne peut pas créer de bannière', $$insert into public.site_banners (title) values ('Pirate')$$, 'row-level');

\echo ===== R7 : vente en cash (paiement à la livraison) avec le taux du vendeur =====
select tests.as_db();
delete from public.pro_subscriptions;
insert into public.pro_subscriptions (user_id, amount, status, fapshi_trans_id, starts_at, ends_at, paid_at)
values ('11111111-1111-1111-1111-111111111111', 3000, 'paid', 'pro-cod', now() - interval '1 hour', now() + interval '20 days', now());
update public.profiles set commission_exempt = false where id = '11111111-1111-1111-1111-111111111111';
update public.products set delivery_options = '{"delivery_douala":{"enabled":true,"price":0},"pickup_douala":{"enabled":true,"price":0}}' where id = 'bbbbbbbb-0000-0000-0000-0000000000c1';
select tests.as_service();
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', '33333333-3333-3333-3333-333333333333', 'acheteur@t.cm', 'Acheteur', 1, 'delivery_douala', 'Akwa, Douala', '699777888', null, 'cod')->>'order_id' as cod_pro \gset
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.seller_update_order_status(:'cod_pro'::uuid, 'confirmed');
select public.seller_update_order_status(:'cod_pro'::uuid, 'shipped');
select public.seller_confirm_cash(:'cod_pro'::uuid);
select tests.as_db();
select tests.eq('Cash, vendeur Pro : 1,5 % de 10 000 = 150 / 1.50', (select platform_fee || '/' || platform_fee_rate from public.transactions where order_id = :'cod_pro'::uuid), '150/1.50');
update public.profiles set commission_exempt = true where id = '11111111-1111-1111-1111-111111111111';
select tests.as_service();
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000c1', '33333333-3333-3333-3333-333333333333', 'acheteur@t.cm', 'Acheteur', 1, 'delivery_douala', 'Akwa, Douala', '699777999', null, 'cod')->>'order_id' as cod_ex \gset
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.seller_update_order_status(:'cod_ex'::uuid, 'confirmed');
select public.seller_update_order_status(:'cod_ex'::uuid, 'shipped');
select public.seller_confirm_cash(:'cod_ex'::uuid);
select tests.as_db();
select tests.eq('Cash, compte exempté : 0 / 0.00 (aucune commission cash due)', (select platform_fee || '/' || platform_fee_rate from public.transactions where order_id = :'cod_ex'::uuid), '0/0.00');

\echo ===== R8 : tarifs réglables par l'admin =====
select tests.as_db();
-- Valeurs d'usine d'une installation neuve (colonnes créées avec leur valeur par défaut)
select tests.eq('Défauts : Pro 5 %, prix 3000, retrait 1,5 % / min 200', (select string_agg(column_default, '|' order by column_name) from information_schema.columns where table_schema = 'public' and table_name = 'commission_settings' and column_name in ('pro_percent', 'pro_price', 'withdrawal_fee_percent', 'withdrawal_fee_min')), '5|3000|200|1.5');
select tests.eq('Défaut du taux normal après lancement = 8', (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'commission_settings' and column_name = 'after_launch_percent'), '8');

-- Sécurité : acheteur ordinaire refusé, anonyme refusé
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas régler les tarifs', $$select public.admin_set_revenue_settings(5, 3000, 1.5, 200)$$, 'acces_refuse');
select tests.as_anon();
select tests.raises('Anonyme ne peut pas régler les tarifs', $$select public.admin_set_revenue_settings(5, 3000, 1.5, 200)$$, 'permission');
select tests.raises('Anonyme ne peut pas écrire le prix Pro', $$update public.commission_settings set pro_price = 1$$, 'permission');
select tests.raises('Anonyme ne peut pas écrire les frais de retrait', $$update public.commission_settings set withdrawal_fee_percent = 0$$, 'permission');

-- Validation (admin)
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Pro 11 % refusé', $$select public.admin_set_revenue_settings(11, 3000, 1.5, 200)$$, 'valeur_invalide');
select tests.raises('Pro négatif refusé', $$select public.admin_set_revenue_settings(-1, 3000, 1.5, 200)$$, 'valeur_invalide');
select tests.raises('Prix Pro 100 FCFA refusé (minimum 500)', $$select public.admin_set_revenue_settings(5, 100, 1.5, 200)$$, 'valeur_invalide');
select tests.raises('Prix Pro 300 000 FCFA refusé', $$select public.admin_set_revenue_settings(5, 300000, 1.5, 200)$$, 'valeur_invalide');
select tests.raises('Frais de retrait 12 % refusés', $$select public.admin_set_revenue_settings(5, 3000, 12, 200)$$, 'valeur_invalide');
select tests.raises('Minimum de retrait 9 000 refusé', $$select public.admin_set_revenue_settings(5, 3000, 1.5, 9000)$$, 'valeur_invalide');
select tests.raises('Valeur vide refusée', $$select public.admin_set_revenue_settings(null, 3000, 1.5, 200)$$, 'valeur_invalide');

-- L'admin règle : les ventes, abonnements et retraits suivants suivent AU MOMENT MÊME
select public.admin_set_revenue_settings(4.5, 5000, 2, 300);
select tests.as_db();
select tests.eq('Réglages enregistrés', (select pro_percent || '/' || pro_price || '/' || withdrawal_fee_percent || '/' || withdrawal_fee_min from public.commission_settings where id = 1), '4.50/5000/2.00/300');

-- Taux normal 8 %, Pro réglé à 4,5 %
update public.profiles set commission_exempt = false;
update public.commission_settings set is_launch_mode = true, launch_start_date = current_date - 40, launch_end_date = current_date - 10, platform_fee_percent = 8, after_launch_percent = 8;
delete from public.pro_subscriptions;
insert into public.pro_subscriptions (user_id, amount, status, fapshi_trans_id, starts_at, ends_at, paid_at)
values ('11111111-1111-1111-1111-111111111111', 5000, 'paid', 'pro-r8', now() - interval '1 hour', now() + interval '5 days', now());
select tests.as_service();
select tests.eq('Vendeur Pro (réglé à 4,5 %) = 450 / 4.50 / 9550', tests.sale100('rev-8a', '+237 655 000 801'), '450/4.50/9550');
select tests.as_db();
update public.pro_subscriptions set ends_at = now() - interval '1 minute';
select tests.as_service();
select tests.eq('Vendeur normal à 8 % = 800 / 8.00 / 9200', tests.sale100('rev-8b', '+237 655 000 802'), '800/8.00/9200');

-- Pro réglé plus haut que le taux normal : jamais plus que le taux normal
select tests.as_db();
select public.admin_set_revenue_settings(4.5, 5000, 2, 300) where false;
update public.commission_settings set pro_percent = 9.5;
update public.pro_subscriptions set ends_at = now() + interval '5 days';
select tests.as_service();
select tests.eq('Pro réglé à 9,5 % > normal 8 % : plafonné à 8 %', tests.sale100('rev-8c', '+237 655 000 803'), '800/8.00/9200');
select tests.as_db();
update public.commission_settings set pro_percent = 4.5;

-- Abonnement : le montant attendu est celui enregistré à la création (le prix réglé à ce moment-là)
delete from public.pro_subscriptions;
insert into public.pro_subscriptions (user_id, amount, fapshi_trans_id) values
 ('22222222-2222-2222-2222-222222222222', 5000, 'pro-r8-ok'),
 ('33333333-3333-3333-3333-333333333333', 5000, 'pro-r8-bad');
select tests.as_service();
select public.confirm_pro_payment('pro-r8-ok', 5000)->>'status' as s_ok \gset r8_
select public.confirm_pro_payment('pro-r8-bad', 3000)->>'status' as s_bad \gset r8_
select tests.eq('Nouveau prix Pro 5 000 : payé 5 000 => activé', :'r8_s_ok', 'paid');
select tests.eq('Nouveau prix Pro 5 000 : payé 3 000 => à vérifier, pas activé', :'r8_s_bad', 'review');

-- Frais de retrait réglés à 2 % (minimum 300)
select tests.as_db();
update public.profiles set commission_exempt = false;
update public.wallets set balance_available = 500000, commission_due = 0 where user_id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(10000, 'mtn_momo', '699000111') as wa \gset r8_
select public.request_withdrawal(50000, 'mtn_momo', '699000111') as wb \gset r8_
select tests.as_db();
select tests.eq('Retrait 10 000 à 2 % = 200 < minimum 300 => 300', (select fee::text from public.withdrawals where id = :'r8_wa'), '300');
select tests.eq('Retrait 50 000 à 2 % = 1 000', (select fee::text from public.withdrawals where id = :'r8_wb'), '1000');

-- Frais à 0 % et minimum 0 : aucun frais
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_revenue_settings(4.5, 5000, 0, 0);
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(10000, 'mtn_momo', '699000111') as wc \gset r8_
select tests.as_db();
select tests.eq('Frais réglés à 0 % / minimum 0 : retrait sans frais', (select fee::text from public.withdrawals where id = :'r8_wc'), '0');

-- Les retraits déjà faits ne changent pas quand on modifie les tarifs ensuite
select tests.eq('Retrait ancien inchangé après nouveau réglage', (select fee::text from public.withdrawals where id = :'r8_wb'), '1000');

-- Les tarifs sont lisibles par le public (affichés aux vendeurs), mais pas modifiables
select tests.as_anon();
select tests.eq('Anonyme peut lire le prix Pro (affiché)', (select pro_price::text from public.commission_settings where id = 1), '5000');
select tests.as_db();

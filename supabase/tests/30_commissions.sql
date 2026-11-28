-- Tests du système de commissions flexibles. À lancer APRÈS 10_scenarios.sql (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
-- (le scénario 10 vide les utilisateurs en cascade, ce qui vide aussi cette table : on remet la ligne par défaut, comme à l'installation)
-- état d'installation : on repart de la ligne par défaut (lancement 30 jours à 0 %, puis 3 %)
delete from public.commission_settings;
delete from public.commission_history;
insert into public.commission_settings (id) values (1);
-- V3.9 : ces tests ne portent pas sur l'identité des vendeurs (testée dans 150_identite.sql)
update public.commission_settings set identity_required = false;
select tests.as_service();
-- ===== Régime par défaut V3 : commissions flexibles ACTIVÉES, 0 % pendant 30 jours puis 3 % =====
select tests.eq('Par défaut : lancement 0 %, puis 3 % après',
  (select is_launch_mode::text || '/' || platform_fee_percent || '/' || after_launch_percent from public.commission_settings where id = 1), 'true/0.00/8.00');
select tests.eq('Lancement : 30 jours', (select (launch_end_date - launch_start_date)::text from public.commission_settings where id = 1), '30');
select tests.eq('Ancien interrupteur "is_active" SUPPRIMÉ', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'commission_settings' and column_name = 'is_active'), '0');
select tests.eq('Ancien calcul 5/8/10 % SUPPRIMÉ (compute_split_legacy)', (to_regprocedure('public.compute_split_legacy(bigint,boolean,integer,boolean)') is null)::text, 'true');
select tests.eq('Ancien calcul SUPPRIMÉ (compute_split)', (to_regprocedure('public.compute_split(bigint,boolean,integer)') is null)::text, 'true');
select tests.eq('Ancienne bascule SUPPRIMÉE (admin_set_commission_active)', (to_regprocedure('public.admin_set_commission_active(boolean)') is null)::text, 'true');
select tests.eq('EXEMPLE CLIENT pendant le lancement : 10 000 FCFA, affilié 20 % => Plateforme 0 / Affilié 2000 / Vendeur 8000',
  (select platform_fee || '/' || affiliate_fee || '/' || (10000 - platform_fee - affiliate_fee) from public.compute_split_for(10000, true, 20, false)), '0/2000/8000');
select tests.eq('Lancement : sans affilié => 0 / 0 / 10000', (select platform_fee || '/' || affiliate_fee from public.compute_split_for(10000, false, 0, false)), '0/0');
select tests.eq('Lancement : physique = même règle', (select platform_fee::text from public.compute_split_for(10000, false, 0, true)), '0');

-- Fin du lancement SIMULÉE : le taux passe tout seul à 3 % (aucune action de l'admin)
select tests.as_db();
update public.commission_settings set launch_start_date = current_date - 31, launch_end_date = current_date - 1;
select tests.as_service();
select tests.eq('Lancement terminé : bascule AUTOMATIQUE à 8 %', (select platform_fee::text from public.compute_split_for(10000, false, 0, false)), '800');
select tests.eq('Lancement terminé : taux effectif = 8', public.effective_platform_percent()::text, '8.00');
select tests.as_db();
update public.commission_settings set launch_start_date = current_date, launch_end_date = current_date + 30;
select tests.as_service();
select tests.eq('Dernier jour du lancement inclus (0 %)', (select platform_fee::text from public.compute_split_for(10000, false, 0, false)), '0');
select tests.as_db();
update public.commission_settings set launch_start_date = current_date - 30, launch_end_date = current_date;
select tests.as_service();
select tests.eq('Le dernier jour du lancement est encore à 0 %', (select platform_fee::text from public.compute_split_for(10000, false, 0, false)), '0');
select tests.as_db();
update public.commission_settings set launch_start_date = current_date, launch_end_date = current_date + 30;
select tests.as_service();

select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas changer la commission', $$select public.admin_set_commission(3)$$, 'acces_refuse');
select tests.raises('Non-admin ne peut pas régler le taux après lancement', $$select public.admin_set_after_launch_percent(4)$$, 'acces_refuse');
select tests.as_anon();
select tests.raises('Anonyme ne peut pas appeler admin_set_commission', $$select public.admin_set_commission(3)$$, 'permission');
select tests.eq('Anonyme voit le taux', (select platform_fee_percent::text from public.commission_settings where id = 1), '0.00');
select tests.raises('Anonyme ne peut pas régler le taux après lancement', $$select public.admin_set_after_launch_percent(4)$$, 'permission');
select tests.raises('Anonyme ne voit pas qui a modifié', $$select updated_by_admin_id from public.commission_settings$$, 'permission');
select tests.raises('Anonyme ne peut pas écrire', $$update public.commission_settings set platform_fee_percent = 9$$, 'permission');

select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_commission(0);
select tests.eq('0 %, affilié 20 % : 0 / 2000', (select platform_fee || '/' || affiliate_fee from public.compute_split_for(10000, true, 20, false)), '0/2000');
select public.admin_set_after_launch_percent(4);
select tests.eq('Taux après lancement choisi = 4 % (le lancement 0 % continue)', (select platform_fee_percent || '/' || after_launch_percent from public.commission_settings where id = 1), '0.00/4.00');
select tests.eq('Pendant le lancement : toujours 0 %', (select platform_fee::text from public.compute_split_for(10000, false, 0, false)), '0');
select tests.raises('Taux après lancement 11 % refusé', $$select public.admin_set_after_launch_percent(11)$$, 'commission_invalide');
select public.admin_set_after_launch_percent(5);
select public.admin_set_after_launch_percent(3);
select public.admin_set_commission(3);
select tests.eq('3 %, affilié 20 % : 300 / 2000 (vendeur 7700)', (select platform_fee || '/' || affiliate_fee || '/' || (10000 - platform_fee - affiliate_fee) from public.compute_split_for(10000, true, 20, false)), '300/2000/7700');
select tests.eq('3 %, sans affilié : 300 / 0 (vendeur 9700)', (select platform_fee || '/' || affiliate_fee from public.compute_split_for(10000, false, 20, false)), '300/0');
select public.admin_set_commission(4);
select tests.eq('4 % : 400 sur 10000', (select platform_fee::text from public.compute_split_for(10000, false, 0, false)), '400');
select public.admin_set_commission(5);
select tests.eq('5 % : 500 sur 10000', (select platform_fee::text from public.compute_split_for(10000, false, 0, false)), '500');
select public.admin_set_commission(3);
select tests.eq('3 %, affilié 50 % : 300 / 5000 (vendeur 4700)', (select platform_fee || '/' || affiliate_fee from public.compute_split_for(10000, true, 50, false)), '300/5000');
select tests.eq('Affilié 60 % bloqué à 50 %', (select affiliate_fee::text from public.compute_split_for(10000, true, 60, false)), '5000');
select tests.eq('Affilié 1 % : 100 sur 10000', (select affiliate_fee::text from public.compute_split_for(10000, true, 1, false)), '100');
select tests.eq('Arrondi à l''entier inférieur (9999 à 3 %)', (select platform_fee::text from public.compute_split_for(9999, true, 20, false)), '299');
select tests.eq('Produit physique : même règle (pas de 8 %)', (select platform_fee::text from public.compute_split_for(10000, false, 0, true)), '300');
select tests.eq('Résultat toujours en entiers (pas de décimale)', (select (platform_fee::text !~ '\.' and affiliate_fee::text !~ '\.')::text from public.compute_split_for(9999, true, 33, false)), 'true');
select tests.raises('Plateforme 15 % refusée', $$select public.admin_set_commission(15)$$, 'commission_invalide');
select tests.raises('Plateforme négative refusée', $$select public.admin_set_commission(-1)$$, 'commission_invalide');
select public.admin_set_commission(2.5);
select tests.eq('2,5 % : 250 sur 10000', (select platform_fee::text from public.compute_split_for(10000, false, 0, false)), '250');
select public.admin_set_commission(3);

select tests.as_db();
update public.products set is_published = true, moderation_status = 'approved', affiliate_percent = 30 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.as_service();
select tests.eq('Historique : chaque changement est enregistré (10 actions)', (select count(*)::text from public.commission_history), '10');
select tests.eq('Historique : ancien -> nouveau', (select old_percent || '>' || new_percent from public.commission_history order by changed_at desc, id limit 1), '2.50>3.00');

-- Vente réelle de bout en bout (3 %, affilié 30 % choisi sur le produit)
select referral_code from public.profiles where id = '22222222-2222-2222-2222-222222222222' \gset aff2_
select tests.checkout('FP-NEWSYS', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'client9@t.cm', 1, null, null, null, :'aff2_referral_code') \gset
select public.confirm_fapshi_payment('FP-NEWSYS', 10000, 'mobile money', 9700)->>'status' as st \gset c9_
select tests.eq('VENTE RÉELLE : 300 / 3000 / 6700', (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.transactions where fapshi_trans_id = 'FP-NEWSYS'), '300/3000/6700');
select tests.checkout('FP-NEWSYS2', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'client10@t.cm', 1, null, null, null, null) \gset
select public.confirm_fapshi_payment('FP-NEWSYS2', 10000, 'mobile money', 9700)->>'status' as st \gset c10_
select tests.eq('VENTE RÉELLE sans affilié : 300 / 0 / 9700', (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.transactions where fapshi_trans_id = 'FP-NEWSYS2'), '300/0/9700');

-- VENTE RÉELLE PENDANT LE LANCEMENT : l'exemple exact du client (10 000 FCFA => Plateforme 0, Affilié 2 000, Vendeur 8 000)
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_commission(0);
select tests.as_db();
update public.products set affiliate_percent = 20 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.as_service();
select tests.checkout('FP-LANCE', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'client11@t.cm', 1, null, null, null, :'aff2_referral_code') \gset
select public.confirm_fapshi_payment('FP-LANCE', 10000, 'mobile money', 9700)->>'status' as st \gset c11_
select tests.eq('VENTE RÉELLE LANCEMENT : Plateforme 0 / Affilié 2000 / Vendeur 8000', (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.transactions where fapshi_trans_id = 'FP-LANCE'), '0/2000/8000');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_commission(3);

-- Produits : affiliation 1 % à 50 %
select tests.as_db();
update public.products set affiliate_percent = 1 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.eq('Affiliation 1 % acceptée', (select affiliate_percent::text from public.products where id = 'aaaaaaaa-0000-0000-0000-000000000001'), '1');
update public.products set affiliate_percent = 37 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.eq('Affiliation 37 % acceptée', (select affiliate_percent::text from public.products where id = 'aaaaaaaa-0000-0000-0000-000000000001'), '37');
select tests.raises('Affiliation 51 % refusée', $$update public.products set affiliate_percent = 51 where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'check');
select tests.raises('Affiliation 0 % refusée', $$update public.products set affiliate_percent = 0 where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'check');
select 'ÉCHECS: ' || tests.fail_count();

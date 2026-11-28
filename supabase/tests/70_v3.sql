-- Tests V3 : commissions par défaut, cycle de statut, montants manipulés, délais, RLS, purge, bienvenue.
-- À lancer APRÈS 10 à 60 (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = true, hold_days = 7;
update public.products set affiliate_percent = 20, is_published = true, moderation_status = 'approved' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
update public.profiles set fraud_review = false, is_blocked = false;
update public.profiles set phone = '699000111', whatsapp = '699000111' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set phone = '677888999', whatsapp = '677888999' where id = '22222222-2222-2222-2222-222222222222';
update auth.users set email = 'affilie@t.cm' where id = '22222222-2222-2222-2222-222222222222';
select referral_code from public.profiles where id = '22222222-2222-2222-2222-222222222222' \gset v3aff_

\echo ===== V3-1 : commissions flexibles ACTIVES PAR DÉFAUT =====
-- on repart d'une installation neuve : ligne unique, lancement 30 jours, 3 % ensuite
delete from public.commission_settings;
insert into public.commission_settings (id) values (1);
-- V3.9 : ces tests ne portent pas sur l'identité des vendeurs (testée dans 150_identite.sql)
update public.commission_settings set identity_required = false;
select tests.eq('Valeurs par défaut : mode lancement', (select is_launch_mode::text from public.commission_settings where id = 1), 'true');
select tests.eq('Valeurs par défaut : 30 jours de lancement', (select (launch_end_date - launch_start_date)::text from public.commission_settings where id = 1), '30');
select tests.eq('Valeurs par défaut : 8 % après le lancement', (select after_launch_percent::text from public.commission_settings where id = 1), '8.00');
select tests.eq('Colonne is_active (ancien système) supprimée', (select count(*)::text from information_schema.columns where table_name = 'commission_settings' and column_name = 'is_active'), '0');
select tests.eq('Ancien calcul compute_split_legacy supprimé', (select count(*)::text from pg_proc where proname = 'compute_split_legacy'), '0');
select tests.eq('Pendant le lancement : plateforme 0 %', (select public.effective_platform_percent()::text), '0');
select tests.eq('Exemple 10 000 FCFA, affilié 20 % : plateforme 0', (select platform_fee::text from public.compute_split_for(10000, true, 20, false)), '0');
select tests.eq('Exemple 10 000 FCFA, affilié 20 % : affilié 2000', (select affiliate_fee::text from public.compute_split_for(10000, true, 20, false)), '2000');
select tests.eq('Exemple 10 000 FCFA, affilié 20 % : vendeur 8000', (select (10000 - platform_fee - affiliate_fee)::text from public.compute_split_for(10000, true, 20, false)), '8000');
-- vente réelle de bout en bout
select tests.as_service();
select tests.checkout('V3-VENTE', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'client.v3@t.cm', 1, null, null, null, :'v3aff_referral_code') \gset
select public.confirm_fapshi_payment('V3-VENTE', 10000, 'mobile money', 9700)->>'status' as st \gset v3a_
select tests.eq('Vente 10 000 : confirmée', :'v3a_st', 'paid');
select tests.eq('Vente 10 000 : plateforme 0 / affilié 2000 / vendeur 8000',
  (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.transactions where fapshi_trans_id = 'V3-VENTE'), '0/2000/8000');
select tests.eq('Vente digitale : fonds libérés après 24 h',
  (select (release_at between paid_at + interval '23 hours' and paid_at + interval '25 hours')::text from public.transactions where fapshi_trans_id = 'V3-VENTE'), 'true');
select tests.eq('Statut de la commande digitale : Livré', (select o.status || '/' || o.payment_status from public.orders o join public.transactions t on t.order_id = o.id where t.fapshi_trans_id = 'V3-VENTE'), 'delivered/paid');
-- après la fin du lancement : 3 % automatiquement
select tests.as_db();
update public.commission_settings set launch_start_date = current_date - 40, launch_end_date = current_date - 10;
select tests.eq('Lancement terminé : bascule automatique à 8 %', (select public.effective_platform_percent()::text), '8.00');
select tests.eq('Après lancement : 10 000 FCFA, affilié 20 % -> plateforme 800', (select platform_fee::text from public.compute_split_for(10000, true, 20, false)), '800');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_after_launch_percent(5);
select tests.as_db();
select tests.eq('Admin : taux après lancement 5 %', (select public.effective_platform_percent()::text), '5.00');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.raises('Non-admin : changer la commission refusé', $$select public.admin_set_after_launch_percent(1)$$, 'acces_refuse');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Commission > 10 % refusée', $$select public.admin_set_after_launch_percent(11)$$, 'commission_invalide');
select tests.as_db();
update public.commission_settings set after_launch_percent = 3, platform_fee_percent = 3;
update public.commission_settings set launch_start_date = current_date, launch_end_date = current_date + 30;

\echo ===== V3-2 : montant manipulé => bloqué + fraud_logs =====
select tests.as_service();
select tests.checkout('V3-MONTANT', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'pirate@t.cm', 1, null, null, null, null) \gset
select count(*) as n_avant from public.fraud_logs \gset
select public.confirm_fapshi_payment('V3-MONTANT', 100, 'mobile money', 90)->>'status' as st \gset v3m_
select tests.eq('Montant différent : transaction en revue', :'v3m_st', 'review');
select tests.eq('Montant différent : raison enregistrée', (select review_reason from public.transactions where fapshi_trans_id = 'V3-MONTANT'), 'montant_different');
select tests.eq('Montant différent : écrit dans fraud_logs', (select (count(*) - :n_avant)::text from public.fraud_logs), '1');
select tests.eq('Montant différent : fraud_logs = bloqué', (select action || '/' || status from public.fraud_logs where reason like 'Montant différent%' order by created_at desc limit 1), 'blocked/blocked');
select tests.eq('Montant différent : commande annulée, jamais livrée', (select o.status from public.orders o join public.transactions t on t.order_id = o.id where t.fapshi_trans_id = 'V3-MONTANT'), 'cancelled');
select tests.eq('Montant différent : aucun lien de téléchargement utilisable (pas de livraison)', (select (o.status <> 'delivered')::text from public.orders o join public.transactions t on t.order_id = o.id where t.fapshi_trans_id = 'V3-MONTANT'), 'true');
select tests.eq('Webhook rejoué : ignoré (already)', (select public.confirm_fapshi_payment('V3-MONTANT', 10000, 'mobile money', 9700)->>'status'), 'already');
select tests.eq('Webhook rejoué : toujours en revue (pas de saut vers payé)', (select status from public.transactions where fapshi_trans_id = 'V3-MONTANT'), 'review');
select public.confirm_fapshi_payment('V3-VENTE', 10000, 'mobile money', 9700)->>'status' as st \gset v3d_
select tests.eq('Double webhook sur une vente payée : ignoré', :'v3d_st', 'already');
select tests.eq('Double webhook : un seul crédit au vendeur', (select count(*)::text from public.transactions where fapshi_trans_id = 'V3-VENTE' and status = 'paid'), '1');
select tests.eq('fapshi_trans_id unique (index)', (select count(*)::text from pg_indexes where tablename = 'transactions' and indexdef ilike '%unique%fapshi_trans_id%'), '1');

\echo ===== V3-3 : cycle de statut sans saut =====
select tests.as_service();
select tests.checkout('V3-PHYS', 'aaaaaaaa-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'acheteur@t.cm', 1, 'pickup_douala', null, '699111222', null) \gset
select order_id as v3oid from public.transactions where fapshi_trans_id = 'V3-PHYS' \gset
select tests.as_db();
select tests.raises('Commande non payée : "Confirmée" refusé', format($$update public.orders set status = 'confirmed' where id = %L$$, :'v3oid'), 'transition_statut_invalide');
select tests.as_service();
select public.confirm_fapshi_payment('V3-PHYS', 15000, 'mobile money', 14500)->>'status' as st \gset v3p_
select tests.as_db();
select tests.eq('Physique payé : En attente de traitement (payé, pas livré)', (select status || '/' || payment_status from public.orders where id = :'v3oid'), 'pending/paid');
select tests.raises('Saut Payé -> Livré refusé', format($$update public.orders set status = 'delivered' where id = %L$$, :'v3oid'), 'transition_statut_invalide');
select tests.raises('Saut Payé -> Terminé refusé', format($$update public.orders set status = 'completed' where id = %L$$, :'v3oid'), 'transition_statut_invalide');
select tests.raises('Retour en arrière du paiement refusé', format($$update public.orders set payment_status = 'pending' where id = %L$$, :'v3oid'), 'transition_paiement_invalide');
update public.orders set status = 'confirmed' where id = :'v3oid';
update public.orders set status = 'ready_for_pickup' where id = :'v3oid';
select tests.raises('Retour en arrière du statut refusé', format($$update public.orders set status = 'confirmed' where id = %L$$, :'v3oid'), 'transition_statut_invalide');
update public.orders set status = 'delivered', delivered_at = now() where id = :'v3oid';
select tests.raises('Livré -> Terminé refusé tant que les fonds ne sont pas libérés', format($$update public.orders set status = 'completed' where id = %L$$, :'v3oid'), 'transition_statut_invalide');
select tests.raises('Transaction payée -> en attente refusé', $$update public.transactions set status = 'pending' where fapshi_trans_id = 'V3-PHYS'$$, 'transition_transaction_invalide');
-- libération : l'acheteur confirme, la tâche planifiée libère, la commande devient Terminée
select tests.as_user('33333333-3333-3333-3333-333333333333');
select public.buyer_confirm_delivery(:'v3oid'::uuid);
select tests.as_db();
update public.transactions set paid_at = now() - interval '8 days', release_at = now() where fapshi_trans_id = 'V3-PHYS';   -- le délai de 7 jours est écoulé
select tests.as_service();
select public.release_due_funds(null);
select tests.eq('Fonds libérés -> commande Terminée', (select status from public.orders where id = :'v3oid'), 'completed');
select tests.as_db();
select tests.raises('Terminé : plus aucun changement possible', format($$update public.orders set status = 'cancelled' where id = %L$$, :'v3oid'), 'transition_statut_invalide');

\echo ===== V3-4 : délais 24 h digital / 7 jours physique =====
select tests.as_service();
select tests.checkout('V3-PHYS2', 'aaaaaaaa-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'acheteur@t.cm', 1, 'pickup_douala', null, '699111222', :'v3aff_referral_code') \gset
select public.confirm_fapshi_payment('V3-PHYS2', 15000, 'mobile money', 14500) is not null as ok \gset
select tests.eq('Physique : pas de libération avant la livraison', (select (release_at is null)::text from public.transactions where fapshi_trans_id = 'V3-PHYS2'), 'true');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.seller_update_order_status(order_id, 'confirmed') from public.transactions where fapshi_trans_id = 'V3-PHYS2';
select public.seller_update_order_status(order_id, 'ready_for_pickup') from public.transactions where fapshi_trans_id = 'V3-PHYS2';
select public.seller_update_order_status(order_id, 'delivered') from public.transactions where fapshi_trans_id = 'V3-PHYS2';
select tests.as_db();
select tests.eq('Physique : fonds retenus au moins 7 jours', (select (release_at >= paid_at + interval '7 days')::text from public.transactions where fapshi_trans_id = 'V3-PHYS2'), 'true');

\echo ===== V3-5 : affilié qui s''achète lui-même =====
select tests.as_service();
select tests.checkout('V3-SELF', 'aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'affilie@t.cm', 1, null, null, null, :'v3aff_referral_code') \gset
select public.confirm_fapshi_payment('V3-SELF', 10000, 'mobile money', 9700)->>'status' as st \gset v3s_
select tests.eq('Auto-achat affilié : paiement accepté', :'v3s_st', 'paid');
select tests.eq('Auto-achat affilié : commission 0', (select coalesce(affiliate_fee, 0)::text from public.transactions where fapshi_trans_id = 'V3-SELF'), '0');
select tests.checkout('V3-SELF2', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'affilie@t.cm', 1, null, null, null, :'v3aff_referral_code') \gset
select public.confirm_fapshi_payment('V3-SELF2', 10000, 'mobile money', 9700)->>'status' as st \gset v3s2_
select tests.eq('Même email que l''affilié (visiteur) : commission 0', (select coalesce(affiliate_fee, 0)::text from public.transactions where fapshi_trans_id = 'V3-SELF2'), '0');
select tests.eq('Même email que l''affilié : tracé dans fraud_logs', (select (count(*) >= 1)::text from public.fraud_logs where reason ilike '%affilié%' and action = 'blocked'), 'true');

\echo ===== V3-6 : RLS sur TOUTES les tables =====
select tests.as_db();
select tests.eq('Toutes les tables du schéma public ont RLS activé',
  (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), '0');
select tests.eq('Les 13 tables exigées existent toutes et ont RLS',
  (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
      and c.relname in ('profiles','products','affiliate_links','transactions','wallets','withdrawals','commission_settings','wholesale_products','wholesale_requests','fraud_logs','waitlist_international','product_locations','disputes')), '13');
select tests.eq('Aucune table ne laisse authenticated écrire directement (INSERT/UPDATE/DELETE) sauf colonnes/tables prévues',
  (select string_agg(c.relname, ',' order by c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relname in ('transactions','wallets','withdrawals','fraud_logs','commission_settings','disputes','wholesale_requests','waitlist_international','orders')
      and (has_table_privilege('authenticated', c.oid, 'INSERT') or has_table_privilege('authenticated', c.oid, 'DELETE') or has_table_privilege('authenticated', c.oid, 'UPDATE'))), null);
select tests.eq('Chaque table du schéma public a au moins une politique RLS explicite',
  (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname)), '0');
-- un utilisateur ne voit que SES données
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.eq('Autre utilisateur : ne voit aucune transaction', (select count(*)::text from public.transactions), '0');
select tests.eq('Autre utilisateur : ne voit aucun retrait', (select count(*)::text from public.withdrawals), '0');
select tests.eq('Autre utilisateur : ne voit aucun fraud_logs (RLS admin seulement)', (select count(*)::text from public.fraud_logs), '0');
select tests.eq('Autre utilisateur : ne voit aucun litige', (select count(*)::text from public.disputes), '0');
select tests.eq('Autre utilisateur : ne voit pas le portefeuille des autres', (select count(*)::text from public.wallets where user_id <> '55555555-5555-5555-5555-555555555555'), '0');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin : voit les transactions', (select (count(*) > 0)::text from public.transactions), 'true');
select tests.eq('Admin : voit fraud_logs', (select (count(*) > 0)::text from public.fraud_logs), 'true');
select tests.as_anon();
select tests.raises('Anonyme : fraud_logs fermé', $$select * from public.fraud_logs$$, 'permission denied');
select tests.raises('Anonyme : transactions fermées', $$select * from public.transactions$$, 'permission denied');

\echo ===== V3-7 : nettoyage des logs 30 jours =====
select tests.as_db();
insert into public.fraud_logs (reason, risk_score, action, status, created_at) values ('Vieux journal', 10, 'allowed', 'closed', now() - interval '40 days');
insert into public.fraud_logs (reason, risk_score, action, status, created_at) values ('Alerte ouverte ancienne', 80, 'flagged', 'open', now() - interval '40 days');
insert into public.fraud_logs (reason, risk_score, action, status, created_at) values ('Montant différent : reçu 1 FCFA, attendu 2 FCFA', 100, 'blocked', 'blocked', now() - interval '40 days');
insert into public.account_ips (user_id, ip, first_seen) values ('55555555-5555-5555-5555-555555555555', '9.9.9.9', now() - interval '40 days') on conflict do nothing;
select public.purge_old_logs() is not null as ok \gset
select tests.eq('Purge : journal de plus de 30 jours supprimé', (select count(*)::text from public.fraud_logs where reason = 'Vieux journal'), '0');
select tests.eq('Purge : alerte encore ouverte conservée', (select count(*)::text from public.fraud_logs where reason = 'Alerte ouverte ancienne'), '1');
select tests.eq('Purge : preuve de montant manipulé conservée (180 jours)', (select count(*)::text from public.fraud_logs where reason like 'Montant différent : reçu 1 FCFA%'), '1');
select tests.eq('Purge : vieilles IP supprimées', (select count(*)::text from public.account_ips where ip = '9.9.9.9'), '0');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.raises('Purge : non appelable par un utilisateur', $$select public.purge_old_logs()$$, 'permission denied');

\echo ===== V3-8 : email de bienvenue une seule fois =====
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.eq('Bienvenue : 1re réservation = vrai', (select public.claim_welcome_email()::text), 'true');
select tests.eq('Bienvenue : 2e réservation = faux (déjà envoyé)', (select public.claim_welcome_email()::text), 'false');
select public.release_welcome_email();
select tests.eq('Bienvenue : après échec d''envoi, on peut réessayer', (select public.claim_welcome_email()::text), 'true');
select tests.as_anon();
select tests.raises('Bienvenue : anonyme refusé', $$select public.claim_welcome_email()$$, 'permission denied');

\echo ===== V3-9 : pages à 3 requêtes max (fonctions de synthèse) =====
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('admin_overview : renvoie stats + frais + affiliés + boosts', (select (public.admin_overview() ?& array['stats','fees','affiliates','boost_revenue'])::text), 'true');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.raises('admin_overview : refusé aux non-admins', $$select public.admin_overview()$$, 'acces_refuse');
select tests.as_anon();
select tests.raises('admin_overview : refusé aux anonymes', $$select public.admin_overview()$$, 'permission denied');
select tests.raises('seller_dashboard : refusé aux anonymes', $$select public.seller_dashboard()$$, 'permission denied');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('seller_dashboard : portefeuille + stats du vendeur connecté', (select (public.seller_dashboard() ?& array['wallet','stats'])::text), 'true');
select tests.eq('seller_dashboard : ne renvoie que le portefeuille du vendeur', (select coalesce(public.seller_dashboard()->'wallet'->>'user_id', '') ), '11111111-1111-1111-1111-111111111111');

\echo ===== V3-10 : photos avant envoi (vendeur) et après réception (acheteur) =====
select tests.as_db();
select id as ph_pend from public.orders where delivery_method is not null and status = 'pending' and buyer_id = '33333333-3333-3333-3333-333333333333' limit 1 \gset
select id as ph_done from public.orders where delivery_method is not null and status = 'completed' and not disputed limit 1 \gset
select id as ph_digi from public.orders where delivery_method is null and payment_status = 'paid' limit 1 \gset
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Photo avant envoi : le vendeur peut l''ajouter', (select public.order_add_photo(:'ph_pend', :'ph_pend' || '/avant.jpg')), 'before_shipping');
select tests.raises('Photo : chemin hors du dossier de la commande refusé', format($$select public.order_add_photo(%L, 'autre/x.jpg')$$, :'ph_pend'), 'fichier_invalide');
select tests.raises('Photo avant envoi : trop tard une fois la commande terminée', format($$select public.order_add_photo(%L, %L)$$, :'ph_done', :'ph_done' || '/x.jpg'), 'photo_trop_tard');
select tests.raises('Photo : commande digitale refusée', format($$select public.order_add_photo(%L, %L)$$, :'ph_digi', :'ph_digi' || '/x.jpg'), 'commande_non_physique');
select tests.eq('Photo : le vendeur voit sa photo', (select count(*)::text from public.order_photos where order_id = :'ph_pend'), '1');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Photo après réception : trop tôt (colis pas encore expédié)', format($$select public.order_add_photo(%L, %L)$$, :'ph_pend', :'ph_pend' || '/y.jpg'), 'photo_trop_tot');
select tests.eq('Photo après réception : l''acheteur peut l''ajouter', (select public.order_add_photo(:'ph_done', :'ph_done' || '/recu.jpg')), 'after_receipt');
select tests.eq('Photo : l''acheteur voit la photo du vendeur de sa commande', (select count(*)::text from public.order_photos where order_id = :'ph_pend'), '1');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.eq('Photo : un inconnu ne voit aucune photo (RLS)', (select count(*)::text from public.order_photos), '0');
select tests.raises('Photo : un inconnu ne peut pas en ajouter', format($$select public.order_add_photo(%L, %L)$$, :'ph_pend', :'ph_pend' || '/z.jpg'), 'acces_refuse');
select tests.as_anon();
select tests.raises('Photo : anonyme refusé', format($$select public.order_add_photo(%L, %L)$$, :'ph_pend', :'ph_pend' || '/z.jpg'), 'permission denied');
select tests.raises('Photo : écriture directe dans la table refusée', format($$insert into public.order_photos (order_id, user_id, kind, path) values (%L, %L, 'before_shipping', 'x')$$, :'ph_pend', '11111111-1111-1111-1111-111111111111'), 'permission denied');

select tests.as_db();
\echo
select 'ÉCHECS: ' || tests.fail_count();

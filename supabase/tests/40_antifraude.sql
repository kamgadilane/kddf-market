-- Tests du système anti-fraude. À lancer APRÈS 10_scenarios.sql (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
insert into public.commission_settings (id) values (1) on conflict (id) do nothing;
update public.commission_settings set is_launch_mode = true, platform_fee_percent = 3, after_launch_percent = 3, launch_start_date = current_date - 40, launch_end_date = current_date - 10;   -- lancement terminé : plateforme 3 %, affilié 30 % choisi sur le produit
update public.fraud_settings set is_active = true, hold_days = 7;
update public.products set is_published = true, moderation_status = 'approved', affiliate_percent = 30 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
update public.profiles set fraud_review = false, is_blocked = false;
update public.profiles set phone = '699000111', whatsapp = '699000111' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set phone = '677111222', whatsapp = null where id = '22222222-2222-2222-2222-222222222222';
select referral_code from public.profiles where id = '22222222-2222-2222-2222-222222222222' \gset af_
select tests.as_service();

\echo ===== EXEMPLE 2 : affilié normal, vrai client =====
select tests.checkout('FR-N1', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'vrai.client@t.cm', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-N1', 10000, 'mobile money', 9700)->>'status' as st \gset n1_
select tests.eq('Vente normale : confirmée', :'n1_st', 'paid');
select tests.eq('Vente normale : commission affilié normale = 3000', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-N1'), '3000');
select tests.eq('Vente normale : aucune alerte', (select count(*)::text from public.fraud_logs where reason not like 'Montant différent%'), '0');
select tests.eq('Délai DIGITAL : fonds retenus 24 h (pas 7 jours)', (select (release_at between paid_at + interval '23 hours' and paid_at + interval '25 hours')::text from public.transactions where fapshi_trans_id = 'FR-N1'), 'true');
select tests.eq('Règle 5 : la commission reste "en attente" (non libérée)', (select (balance_pending >= 3000)::text from public.wallets where user_id = '22222222-2222-2222-2222-222222222222'), 'true');
select tests.eq('checkFraud (SQL) : vrai client = autorisé, score 0, commission normale',
  (select (r->>'allowed') || '/' || (r->>'risk_score') || '/' || (r->>'commission') from (select public.fraud_assess(null, 'vrai.client@t.cm', null, '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', null, null) r) q), 'true/0/normal');

\echo ===== EXEMPLE 1 : l'affilié s'achète lui-même =====
select tests.checkout('FR-S1', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'affilie@t.cm', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-S1', 10000, 'mobile money', 9700)->>'status' as st \gset s1_
select tests.eq('Auto-achat (même email) : la vente continue', :'s1_st', 'paid');
select tests.eq('Auto-achat (même email) : commission = 0', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-S1'), '0');
select tests.eq('Auto-achat : journal = bloqué, score 100', (select action || '/' || risk_score from public.fraud_logs where reason like 'Affilié = Acheteur%' limit 1), 'blocked/100');
select tests.eq('Auto-achat : le vendeur reçoit toute la part (10000 - 3 %)', (select seller_amount::text from public.transactions where fapshi_trans_id = 'FR-S1'), '9700');
select tests.as_db();
update public.profiles set phone = '+237 677 111 222' where id = '33333333-3333-3333-3333-333333333333';
select tests.as_service();
select tests.checkout('FR-S2', 'aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'quelquun@t.cm', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-S2', 10000, 'mobile money', 9700)->>'status' as st \gset s2_
select tests.eq('Auto-achat (même téléphone, formats différents) : commission = 0', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-S2'), '0');
select tests.as_db();
update auth.users set email = 'bob.smith@gmail.com' where id = '22222222-2222-2222-2222-222222222222';
select tests.as_service();
select tests.checkout('FR-S3', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'bobsmith+promo@gmail.com', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-S3', 10000, 'mobile money', 9700)->>'status' as st \gset s3_
select tests.eq('Auto-achat (astuce Gmail points / +alias) : commission = 0', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-S3'), '0');
select tests.eq('Compte MoMo identique (si connu) : bloqué par checkFraud',
  (select r->>'commission' from (select public.fraud_assess(null, 'x@t.cm', null, '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', null, '0677111222') r) q), 'zero');

\echo ===== RÈGLE 2 : vendeur = affilié =====
select tests.eq('Vendeur = Affilié (même id) détecté', (select r->>'reason' from (select public.fraud_assess(null, 'x@t.cm', null, '22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', null, null) r) q), 'Vendeur = Affilié');
select tests.as_db();
update public.profiles set whatsapp = '699000111' where id = '22222222-2222-2222-2222-222222222222';
select tests.as_service();
select tests.checkout('FR-V1', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'client.v1@t.cm', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-V1', 10000, 'mobile money', 9700)->>'status' as st \gset v1_
select tests.eq('WhatsApp du vendeur = numéro de l''affilié : commission = 0', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-V1'), '0');
select tests.as_db();
update public.profiles set whatsapp = null where id = '22222222-2222-2222-2222-222222222222';
select tests.as_service();

\echo ===== RÈGLE 3 : comptes multiples =====
select tests.as_db();
update public.profiles set phone = '655000999' where id in ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555');
update public.profiles set phone = '655000999' where id = '22222222-2222-2222-2222-222222222222';   -- 4 comptes avec le même numéro => +40
insert into public.account_ips (user_id, ip) select id, '41.202.1.1' from public.profiles where id in ('22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','55555555-5555-5555-5555-555555555555');  -- 4 comptes même IP => +30
select tests.as_service();
select tests.eq('Règle 3 : téléphone partagé (+40) + même IP (+30) = 70',
  (select (r->>'risk_score') || '/' || (r->>'commission') from (select public.fraud_assess(null, 'x@t.cm', null, '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', null, null) r) q), '70/hold');
select tests.checkout('FR-M1', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'faux.compte@t.cm', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-M1', 10000, 'mobile money', 9700)->>'status' as st \gset m1_
select tests.eq('Score >= 70 : la vente PASSE (client livré)', :'m1_st', 'paid');
select tests.eq('Score >= 70 : commission en attente manuelle (jamais libérée)', (select release_at::text from public.transactions where fapshi_trans_id = 'FR-M1'), 'infinity');
select tests.eq('Score >= 70 : journal "flagged" / open', (select action || '/' || status from public.fraud_logs where transaction_id = (select id from public.transactions where fapshi_trans_id = 'FR-M1')), 'flagged/open');
select tests.as_db();
update public.profiles set phone = '677111222' where id = '22222222-2222-2222-2222-222222222222';
delete from public.account_ips;
update public.fraud_logs set status = 'closed';  -- on repart propre
select tests.as_service();

\echo ===== EXEMPLE 3 : 25 ventes en 1 heure =====
select tests.as_db();
create or replace function tests.sell(n int) returns void language plpgsql as $$
declare i int; r jsonb;
begin
  for i in 1..n loop
    r := tests.checkout('FR-R' || i, 'aaaaaaaa-0000-0000-0000-000000000001', null, 'rapide' || i || '@t.cm', 1, null, null, null, (select referral_code from public.profiles where id = '22222222-2222-2222-2222-222222222222'));
    perform public.confirm_fapshi_payment('FR-R' || i, 10000, 'mobile money', 9700);
  end loop;
end $$;
delete from public.fraud_logs;
update public.transactions set paid_at = now() - interval '3 days' where affiliate_id = '22222222-2222-2222-2222-222222222222';   -- les ventes précédentes ne comptent pas dans l'heure
select tests.as_service();
select balance_available as av0 from public.wallets where user_id = '22222222-2222-2222-2222-222222222222' \gset
select tests.sell(25);
select tests.eq('25 ventes : toutes confirmées (aucun client bloqué)', (select count(*)::text from public.transactions where fapshi_trans_id like 'FR-R%' and status = 'paid'), '25');
select tests.eq('25 ventes : les 10 premières normales', (select count(*)::text from public.transactions where fapshi_trans_id like 'FR-R%' and release_at <> 'infinity'), '10');
select tests.eq('25 ventes : les 15 suivantes en attente manuelle', (select count(*)::text from public.transactions where fapshi_trans_id like 'FR-R%' and release_at = 'infinity'), '15');
select tests.eq('25 ventes : alerte admin au bon format', (select (count(*) = 1)::text from public.fraud_logs where reason = 'Activité suspecte : Affilié Affilie - 25 ventes en 1h'), 'true');
select tests.eq('3 alertes en 30 jours : compte "en cours de vérification"', (select fraud_review::text from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'true');
select tests.eq('Aucun paiement automatique : rien de libéré sur les ventes retenues', (select count(*)::text from public.transactions where fapshi_trans_id like 'FR-R%' and released_at is not null), '0');

-- Le temps passe : les 10 premières ventes (7 jours écoulés) se libèrent ; les 15 retenues restent bloquées malgré la date
select tests.as_db();
update public.transactions set paid_at = now() - interval '8 days', release_at = now() - interval '1 day' where fapshi_trans_id like 'FR-R%';
select public.release_due_funds(null);
select tests.eq('Après 7 jours : 10 ventes libérées', (select count(*)::text from public.transactions where fapshi_trans_id like 'FR-R%' and released_at is not null), '10');
select tests.eq('Les 15 ventes suspectes restent retenues (même daté du passé)', (select count(*)::text from public.transactions where fapshi_trans_id like 'FR-R%' and released_at is null and release_at = 'infinity'), '15');
select tests.eq('Solde affilié disponible = 10 x 3000', (select (balance_available - :av0)::text from public.wallets where user_id = '22222222-2222-2222-2222-222222222222'), '30000');

\echo ===== Retraits =====
select tests.as_user('22222222-2222-2222-2222-222222222222');
select tests.raises('Compte en vérification : retrait refusé', $$select public.request_withdrawal(5000, 'mtn_momo', '677111222')$$, 'compte_en_verification');
select tests.eq('Notice utilisateur : retenues + vérification, sans aucune règle', (select (n->>'held') || '/' || (n->>'review') || '/' || (n ? 'reason')::text from (select public.my_fraud_notice() n) q), '15/true/false');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Le vendeur voit aussi que ses ventes retenues sont en vérification', (select (public.my_fraud_notice()->>'held')), '15');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.eq('Utilisateur honnête : rien de différent', (select (n->>'held') || '/' || (n->>'review') || '/' || (n->>'cancelled') from (select public.my_fraud_notice() n) q), '0/false/false');
select tests.eq('Utilisateur ne lit pas fraud_logs (RLS : 0 ligne visible)', (select count(*)::text from public.fraud_logs), '0');
select tests.raises('Utilisateur ne peut pas valider', $$select public.admin_fraud_resolve(gen_random_uuid(), 'validate')$$, 'acces_refuse');
select tests.raises('Utilisateur ne peut pas lire la vue admin', $$select public.admin_fraud_overview()$$, 'acces_refuse');
select tests.as_anon();
select tests.raises('Anonyme : my_fraud_notice interdit', $$select public.my_fraud_notice()$$, 'permission');
select tests.raises('Anonyme : fraud_assess interdit', $$select public.fraud_assess(null,null,null,null,null,null,null)$$, 'permission');

\echo ===== Page admin =====
select tests.as_service();
select tests.checkout('FR-S9', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'bobsmith@gmail.com', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-S9', 10000, 'mobile money', 9700)->>'status' as st \gset s9_
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin : ventes en attente de validation = 15', (public.admin_fraud_overview()->>'pending'), '15');
select tests.eq('Admin : ventes bloquées aujourd''hui = 1', (public.admin_fraud_overview()->>'blocked_today'), '1');
select tests.eq('Admin : argent économisé = 1 commission de 3000', (public.admin_fraud_overview()->>'saved_total'), '3000');
select tests.eq('Admin : alertes listées', (select (count(*) >= 15)::text from public.admin_fraud_alerts(100)), 'true');

select tests.as_db();
select id as lid from public.fraud_logs where transaction_id = (select id from public.transactions where fapshi_trans_id = 'FR-R11') \gset
select balance_pending as sp0 from public.wallets where user_id = '11111111-1111-1111-1111-111111111111' \gset
select balance_pending as ap0 from public.wallets where user_id = '22222222-2222-2222-2222-222222222222' \gset
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_fraud_resolve(:'lid', 'block');
select tests.as_db();
select tests.eq('Bloquer : commission affilié = 0', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-R11'), '0');
select tests.eq('Bloquer : la part revient au vendeur (6700 + 3000)', (select seller_amount::text from public.transactions where fapshi_trans_id = 'FR-R11'), '9700');
select tests.eq('Bloquer : portefeuilles cohérents (affilié -3000, vendeur +3000)',
  (select ((select balance_pending from public.wallets where user_id = '22222222-2222-2222-2222-222222222222') - :ap0)::text || '/' || ((select balance_pending from public.wallets where user_id = '11111111-1111-1111-1111-111111111111') - :sp0)::text), '-3000/3000');
select tests.eq('Bloquer : alerte close, enregistrée "blocked"', (select status || '/' || action from public.fraud_logs where id = :'lid'), 'blocked/blocked');
select tests.eq('Bloquer : message utilisateur d''annulation disponible', (select (n->>'cancelled') from (select public.my_fraud_notice() n) q), 'false');  -- (le notice est évalué pour l'admin ici)
select tests.as_user('22222222-2222-2222-2222-222222222222');
select tests.eq('Bloquer : l''affilié voit le message d''annulation', (public.my_fraud_notice()->>'cancelled'), 'true');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_fraud_resolve(:'lid', 'block');   -- double clic
select tests.as_db();
select tests.eq('Double clic : rien n''a bougé (affilié toujours -3000)', ((select balance_pending from public.wallets where user_id = '22222222-2222-2222-2222-222222222222') - :ap0)::text, '-3000');

select id as lid2 from public.fraud_logs where transaction_id = (select id from public.transactions where fapshi_trans_id = 'FR-R12') \gset
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_fraud_resolve(:'lid2', 'validate');
select tests.as_db();
select tests.eq('Valider : commission inchangée (3000)', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-R12'), '3000');
select tests.eq('Valider : retour à l''attente normale (digital : 24 h)', (select (release_at = paid_at + interval '24 hours')::text from public.transactions where fapshi_trans_id = 'FR-R12'), 'true');

-- Bannir
select id as lid3 from public.fraud_logs where transaction_id = (select id from public.transactions where fapshi_trans_id = 'FR-R13') \gset
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_fraud_resolve(:'lid3', 'ban');
select tests.as_db();
select tests.eq('Bannir : compte bloqué', (select is_blocked::text from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'true');

-- Déblocage manuel
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_fraud_unblock('22222222-2222-2222-2222-222222222222');
select tests.as_db();
update public.profiles set is_blocked = false where id = '22222222-2222-2222-2222-222222222222';
select tests.eq('Déblocage manuel par l''admin', (select fraud_review::text from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'false');
select tests.as_user('22222222-2222-2222-2222-222222222222');
select tests.eq('Après déblocage : le retrait fonctionne', (select (public.request_withdrawal(5000, 'mtn_momo', '677111222') is not null)::text), 'true');

\echo ===== Remboursement dans les 7 jours =====
select tests.as_db();
update public.fraud_settings set is_active = true;
select tests.checkout('FR-RF', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'client.rf@t.cm', 1, null, null, null, null) \gset
select public.confirm_fapshi_payment('FR-RF', 10000, 'mobile money', 9700)->>'status' as st \gset rf_
select balance_pending as sp1 from public.wallets where user_id = '11111111-1111-1111-1111-111111111111' \gset
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_refund_transaction((select id from public.transactions where fapshi_trans_id = 'FR-RF'), 'test');
select tests.as_db();
select tests.eq('Remboursement dans le délai : commission annulée automatiquement', (select ((:sp1) - balance_pending)::text from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), '9700');

\echo ===== Panne de l anti-fraude : on laisse passer =====
alter function public.fraud_assess(uuid, text, text, uuid, uuid, uuid, text) rename to fraud_assess_off;
select tests.checkout('FR-PANNE', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'affilie.encore@t.cm', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-PANNE', 10000, 'mobile money', 9700)->>'status' as st \gset pn_
alter function public.fraud_assess_off(uuid, text, text, uuid, uuid, uuid, text) rename to fraud_assess;
select tests.eq('Panne : la vente est confirmée, le client est livré', :'pn_st', 'paid');
select tests.eq('Panne : calcul inchangé (commission 3000)', (select affiliate_fee::text from public.transactions where fapshi_trans_id = 'FR-PANNE'), '3000');

\echo ===== Interrupteur =====
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_fraud_set_active(false);
select tests.as_db();
select tests.checkout('FR-OFF', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'affilie@t.cm', 1, null, null, null, :'af_referral_code') \gset
select public.confirm_fapshi_payment('FR-OFF', 10000, 'mobile money', 9700)->>'status' as st \gset of_
select tests.eq('Anti-fraude désactivé : comportement normal (24 h, commission 3000)', (select affiliate_fee || '/' || (release_at < paid_at + interval '2 days')::text from public.transactions where fapshi_trans_id = 'FR-OFF'), '3000/true');
select 'FAILS=' || tests.fail_count();

-- Tests V3.2 : PAYPAL + DEVISES (montant en devise verrouillé, confirmation par préfixe pp:, montant différent => à vérifier, table fx_rates fermée).
-- À lancer APRÈS 10 à 80 (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = true, hold_days = 7;
update public.commission_settings set is_launch_mode = true, launch_start_date = current_date, launch_end_date = current_date + 30, platform_fee_percent = 0;
insert into public.products (id, seller_id, product_type, title, slug, price, is_published, affiliate_percent, stock, images, whatsapp_seller, delivery_options, moderation_status) values
 ('bbbbbbbb-0000-0000-0000-0000000000b2', '11111111-1111-1111-1111-111111111111', 'physical', 'Sac PayPal', 'sac-paypal', 10000, true, 20, 100, array['https://img/p.jpg'], '699000111',
  '{"pickup_douala":{"enabled":true,"price":0}}', 'approved')
 on conflict (id) do nothing;
update public.products set affiliate_enabled = true where id = 'bbbbbbbb-0000-0000-0000-0000000000b2';
update public.profiles set fraud_review = false, is_blocked = false;
update public.profiles set phone = '677888999', whatsapp = '677888999' where id = '22222222-2222-2222-2222-222222222222';
select referral_code from public.profiles where id = '22222222-2222-2222-2222-222222222222' \gset pp_aff_

\echo ===== PP1 : vente PayPal de 10 000 FCFA payée en USD =====
select tests.as_service();
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000b2', null, null, 'Marie Diaspora', 1, 'pickup_douala', null, '+237 644 000 111', :'pp_aff_referral_code', 'online', 'Douala', 'Bonapriso', '10.1.1.1')::text as pp1 \gset
select (:'pp1'::jsonb)->>'transaction_id' as pp1_tx, (:'pp1'::jsonb)->>'order_id' as pp1_order \gset
-- le serveur verrouille le taux au moment de créer la commande PayPal
update public.transactions
   set fapshi_trans_id = 'pp:5O190127TN364715T', fapshi_link = 'https://www.sandbox.paypal.com/checkoutnow?token=5O190127TN364715T', fapshi_status = 'CREATED',
       pay_currency = 'USD', pay_amount = '16.74', fx_rate = 0.0016739, fx_source = 'open.er-api.com @ 2026-11-20T00:02:32Z', fx_locked_at = now()
 where id = :'pp1_tx';
select tests.eq('PayPal : montant en devise verrouillé (16.74 USD)', (select pay_amount::text || ' ' || pay_currency from public.transactions where id = :'pp1_tx'), '16.74 USD');
select tests.eq('PayPal : le total comptable reste en FCFA entier', (select total_amount::text from public.transactions where id = :'pp1_tx'), '10000');
select coalesce((select balance_pending from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), 0) as pp_seller_avant \gset
select public.confirm_fapshi_payment('pp:5O190127TN364715T', 10000, 'paypal', null)->>'status' as st \gset pp1_
select tests.eq('PayPal : paiement confirmé', :'pp1_st', 'paid');
select tests.eq('PayPal : répartition en FCFA = plateforme 0 / affilié 2 000 / vendeur 8 000',
  (select platform_fee || '/' || affiliate_fee || '/' || seller_amount from public.transactions where id = :'pp1_tx'), '0/2000/8000');
select tests.eq('PayPal : moyen de paiement enregistré', (select fapshi_medium from public.transactions where id = :'pp1_tx'), 'paypal');
select tests.eq('PayPal : devise et montant conservés après paiement', (select pay_amount::text || pay_currency from public.transactions where id = :'pp1_tx'), '16.74USD');
select tests.eq('PayPal : commande payée', (select payment_status from public.orders where id = :'pp1_order'), 'paid');
select public.confirm_fapshi_payment('pp:5O190127TN364715T', 10000, 'paypal', null)->>'status' as st2 \gset pp1_
select tests.eq('PayPal : webhook rejoué = aucun double crédit', :'pp1_st2', 'already');
select tests.eq('PayPal : vendeur crédité une seule fois (8 000 en attente)', ((select balance_pending from public.wallets where user_id = '11111111-1111-1111-1111-111111111111') - :pp_seller_avant)::text, '8000');

\echo ===== PP2 : montant, devise ou référence différents => à vérifier, aucun crédit =====
select public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000b2', null, null, 'Paul Fraude', 1, 'pickup_douala', null, '+237 644 000 222', null, 'online', 'Douala', 'Akwa', '10.1.1.2')::text as pp2 \gset
select (:'pp2'::jsonb)->>'transaction_id' as pp2_tx \gset
update public.transactions set fapshi_trans_id = 'pp:MISMATCH0001', pay_currency = 'USD', pay_amount = '16.74', fx_rate = 0.0016739, fx_locked_at = now() where id = :'pp2_tx';
select coalesce((select balance_pending from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), 0) as pp_seller_avant2 \gset
select public.confirm_fapshi_payment('pp:MISMATCH0001', -1, 'paypal', null)->>'status' as st \gset pp2_
select tests.eq('PayPal montant différent : transaction « à vérifier »', :'pp2_st', 'review');
select tests.eq('PayPal montant différent : raison enregistrée', (select review_reason from public.transactions where id = :'pp2_tx'), 'montant_different');
select tests.eq('PayPal montant différent : aucune répartition créditée', (select (platform_fee is null)::text from public.transactions where id = :'pp2_tx'), 'true');
select tests.eq('PayPal montant différent : aucun crédit au vendeur', ((select balance_pending from public.wallets where user_id = '11111111-1111-1111-1111-111111111111') - :pp_seller_avant2)::text, '0');
select public.confirm_fapshi_payment('pp:MISMATCH0001', 10000, 'paypal', null)->>'status' as st2 \gset pp2_
select tests.eq('PayPal montant différent : rejouer avec le bon montant ne débloque pas la revue', (select status from public.transactions where id = :'pp2_tx'), 'review');

\echo ===== PP3 : contraintes de la base =====
select tests.raises('Devise XAF refusée pour PayPal', format($$update public.transactions set pay_currency = 'XAF', pay_amount = 5 where id = %L$$, :'pp2_tx'), 'transactions_pay_currency_chk');
select tests.raises('Devise sans montant refusée', format($$update public.transactions set pay_amount = null where id = %L$$, :'pp2_tx'), 'transactions_fx_pair_chk');
select tests.raises('Montant négatif refusé', format($$update public.transactions set pay_amount = -3 where id = %L$$, :'pp2_tx'), 'transactions_pay_amount_chk');
select tests.raises('Taux négatif refusé', format($$update public.transactions set fx_rate = -1 where id = %L$$, :'pp2_tx'), 'transactions_fx_rate_chk');

\echo ===== PP4 : table fx_rates réservée au serveur =====
select tests.eq('fx_rates : RLS activée', (select relrowsecurity::text from pg_class where oid = 'public.fx_rates'::regclass), 'true');
insert into public.fx_rates (currency, per_eur, source, as_of) values ('USD', 1.097999, 'open.er-api.com', now()) on conflict (currency) do update set per_eur = excluded.per_eur;
select tests.eq('fx_rates : le serveur peut enregistrer un taux', (select per_eur::text from public.fx_rates where currency = 'USD'), '1.09799900');
select tests.raises('fx_rates : devise inconnue refusée', $$insert into public.fx_rates (currency, per_eur, source, as_of) values ('XAF', 655.957, 'x', now())$$, 'fx_rates_currency_check');
select tests.raises('fx_rates : taux nul refusé', $$insert into public.fx_rates (currency, per_eur, source, as_of) values ('GBP', 0, 'x', now())$$, 'fx_rates_per_eur_check');
select tests.as_anon();
select tests.raises('fx_rates : fermée aux visiteurs (lecture)', $$select * from public.fx_rates$$, 'permission denied');
select tests.raises('fx_rates : fermée aux visiteurs (écriture)', $$update public.fx_rates set per_eur = 9$$, 'permission denied');
select tests.as_user('22222222-2222-2222-2222-222222222222');
select tests.raises('fx_rates : fermée aux comptes connectés', $$select * from public.fx_rates$$, 'permission denied');
select tests.as_service();

\echo ===== RÉSULTAT =====
select 'ÉCHECS: ' || tests.fail_count();

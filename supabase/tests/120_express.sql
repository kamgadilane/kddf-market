-- Tests V3.5 : retrait express (supplément réglable).  À lancer APRÈS 10 à 110.
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = false;
update public.profiles set fraud_review = false, is_blocked = false, commission_exempt = false;
update public.commission_settings set withdrawal_fee_percent = 1.5, withdrawal_fee_min = 200, express_fee_percent = 2;
update public.wallets set balance_available = 900000, commission_due = 0 where user_id = '11111111-1111-1111-1111-111111111111';

\echo ===== Retrait express =====
select tests.eq('Supplément express par défaut = 2', (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'commission_settings' and column_name = 'express_fee_percent'), '2');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(100000, 'mtn_momo', '699000111') as n1 \gset x_
select public.request_withdrawal(100000, 'mtn_momo', '699000111', true) as e1 \gset x_
select public.request_withdrawal(100000, 'mtn_momo', '699000111', false) as n2 \gset x_
select tests.as_db();
select tests.eq('Retrait normal (ancien appel à 3 paramètres) : 1,5 % = 1 500, pas express', (select fee || '/' || express || '/' || express_fee from public.withdrawals where id = :'x_n1'), '1500/false/0');
select tests.eq('Retrait express : 1 500 + 2 % (2 000) = 3 500, partie express 2 000', (select fee || '/' || express || '/' || express_fee from public.withdrawals where id = :'x_e1'), '3500/true/2000');
select tests.eq('Express = faux explicite : comme un retrait normal', (select fee || '/' || express from public.withdrawals where id = :'x_n2'), '1500/false');
select tests.eq('Le solde bloqué est bien le montant demandé (frais déduits du paiement, pas du solde)', (select balance_available::text from public.wallets where user_id = '11111111-1111-1111-1111-111111111111'), '600000');

-- Petit montant : minimum normal 200 + express 2 % de 1 000 = 20
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(1000, 'mtn_momo', '699000111', true) as e2 \gset x_
select tests.as_db();
select tests.eq('Express sur 1 000 : 200 + 20 = 220', (select fee || '/' || express_fee from public.withdrawals where id = :'x_e2'), '220/20');

-- Commission cash déduite d'abord : l'express porte sur le reste
update public.wallets set commission_due = 500 where user_id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(10500, 'mtn_momo', '699000111', true) as e3 \gset x_
select tests.as_db();
select tests.eq('Commission cash 500 déduite, base 10 000 : 200 + 200 = 400', (select commission_deducted || '/' || fee || '/' || express_fee from public.withdrawals where id = :'x_e3'), '500/400/200');

-- Compte exempté : express gratuit
update public.profiles set commission_exempt = true where id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(20000, 'mtn_momo', '699000111', true) as e4 \gset x_
select tests.as_db();
select tests.eq('Compte exempté : express sans aucun frais, mais bien marqué express', (select fee || '/' || express from public.withdrawals where id = :'x_e4'), '0/true');
update public.profiles set commission_exempt = false where id = '11111111-1111-1111-1111-111111111111';

-- L'admin règle le supplément
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas régler l''express', $$select public.admin_set_revenue_settings(5, 3000, 1.5, 200, 1)$$, 'acces_refuse');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Express 11 % refusé', $$select public.admin_set_revenue_settings(5, 3000, 1.5, 200, 11)$$, 'valeur_invalide');
select tests.raises('Express négatif refusé', $$select public.admin_set_revenue_settings(5, 3000, 1.5, 200, -1)$$, 'valeur_invalide');
select public.admin_set_revenue_settings(5, 3000, 1.5, 200);
select tests.as_db();
select tests.eq('Appel sans 5e paramètre : express inchangé (2)', (select express_fee_percent::text from public.commission_settings where id = 1), '2.00');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_revenue_settings(5, 3000, 1.5, 200, 1);
select tests.as_db();
select tests.eq('Express réglé à 1 %', (select express_fee_percent::text from public.commission_settings where id = 1), '1.00');
update public.wallets set balance_available = 900000, commission_due = 0 where user_id = '11111111-1111-1111-1111-111111111111';
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(100000, 'mtn_momo', '699000111', true) as e5 \gset x_
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_revenue_settings(5, 3000, 1.5, 200, 0);
select tests.as_user('11111111-1111-1111-1111-111111111111');
select public.request_withdrawal(100000, 'mtn_momo', '699000111', true) as e6 \gset x_
select tests.as_db();
select tests.eq('Express à 1 % : 1 500 + 1 000 = 2 500', (select fee::text from public.withdrawals where id = :'x_e5'), '2500');
select tests.eq('Express à 0 % : aucun supplément (frais normaux seulement)', (select fee || '/' || express_fee from public.withdrawals where id = :'x_e6'), '1500/0');
select tests.eq('Ancien retrait express inchangé après changement de tarif', (select fee::text from public.withdrawals where id = :'x_e1'), '3500');

-- Sécurité : on ne peut pas écrire express/express_fee soi-même ni lire le détail des autres
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.raises('Un vendeur ne peut pas modifier un retrait', $$update public.withdrawals set express_fee = 0, fee = 0$$, 'permission');
select tests.as_anon();
select tests.raises('Anonyme ne peut pas demander de retrait', $$select public.request_withdrawal(5000, 'mtn_momo', '699000111', true)$$, 'permission');
select tests.as_db();
update public.commission_settings set express_fee_percent = 2;

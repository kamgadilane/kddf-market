-- Tests V3.9 : protection des comptes (2FA facultative, téléphone confirmé). À lancer APRÈS 150.
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
delete from auth.mfa_factors;
update public.commission_settings set phone_required = false, identity_required = false;
select set_config('request.jwt.claims', '', false);

\echo ===== S1 : 2FA facultative =====
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin SANS 2FA : accès normal', public.is_admin()::text, 'true');
select tests.as_db();
insert into auth.mfa_factors (user_id, status) values ('44444444-4444-4444-4444-444444444444', 'verified');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin AVEC 2FA mais session mot de passe seul (aal1) : refusé', public.is_admin()::text, 'false');
select tests.raises('Fonction admin refusée en aal1', $$select * from public.admin_identity_list()$$, 'acces_refuse');
select set_config('request.jwt.claims', '{"aal":"aal2"}', false);
select tests.eq('Admin AVEC 2FA et code validé (aal2) : accès', public.is_admin()::text, 'true');
select set_config('request.jwt.claims', '', false);
select tests.as_db();
select tests.eq('Le serveur (sans session utilisateur) n''est pas bloqué', public.mfa_ok()::text, 'true');
-- Un facteur non confirmé (activation commencée, jamais terminée) ne bloque personne
delete from auth.mfa_factors;
insert into auth.mfa_factors (user_id, status) values ('44444444-4444-4444-4444-444444444444', 'unverified');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Activation 2FA abandonnée : pas de blocage', public.is_admin()::text, 'true');

\echo ===== S2 : retraits protégés par la 2FA =====
select tests.as_db();
delete from auth.mfa_factors;
insert into auth.mfa_factors (user_id, status) values ('11111111-1111-1111-1111-111111111111', 'verified');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select tests.raises('Retrait refusé en aal1 quand la 2FA est activée', $$insert into public.withdrawals (user_id, amount, method, phone_number) values ('11111111-1111-1111-1111-111111111111', 1000, 'mtn_momo', '670000000')$$, 'verification_2fa_requise');
select set_config('request.jwt.claims', '{"aal":"aal2"}', false);
select tests.eq('Retrait accepté en aal2', tests.rows($$insert into public.withdrawals (user_id, amount, method, phone_number) values ('11111111-1111-1111-1111-111111111111', 1000, 'mtn_momo', '670000000')$$), '1');
select set_config('request.jwt.claims', '', false);
select set_config('request.jwt.claim.sub', '', false);
delete from public.withdrawals where phone_number = '670000000';
delete from auth.mfa_factors;

\echo ===== S3 : téléphone confirmé =====
insert into auth.users (id, email, phone) values ('77777777-7777-7777-7777-777777777777', 'tel7@test.cm', '237670000007') on conflict (id) do nothing;
update auth.users set phone_confirmed_at = null where id = '77777777-7777-7777-7777-777777777777';
delete from public.products where slug like 'guide-tel-%';
select tests.as_user('77777777-7777-7777-7777-777777777777');
select tests.eq('Téléphone non confirmé', (public.my_phone()->>'verified'), 'false');
select tests.as_db();
select tests.eq('Règle désactivée (défaut) : publier sans téléphone confirmé', tests.rows($$insert into public.products (seller_id, product_type, digital_kind, title, slug, price, is_published) values ('77777777-7777-7777-7777-777777777777', 'digital', 'file', 'Guide tel A', 'guide-tel-a', 5000, true)$$), '1');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Non-admin ne règle pas le téléphone', $$select public.admin_set_phone_required(true)$$, 'x') where false;
select public.admin_set_phone_required(true);
select tests.as_db();
select tests.raises('Règle activée : publication refusée sans téléphone confirmé', $$insert into public.products (seller_id, product_type, digital_kind, title, slug, price, is_published) values ('77777777-7777-7777-7777-777777777777', 'digital', 'file', 'Guide tel B', 'guide-tel-b', 5000, true)$$, 'telephone_non_verifie');
select tests.eq('Un brouillon reste possible', tests.rows($$insert into public.products (seller_id, product_type, digital_kind, title, slug, price, is_published) values ('77777777-7777-7777-7777-777777777777', 'digital', 'file', 'Guide tel C', 'guide-tel-c', 5000, false)$$), '1');
update auth.users set phone_confirmed_at = now() where id = '77777777-7777-7777-7777-777777777777';
select tests.eq('Après confirmation SMS : publication autorisée', tests.rows($$update public.products set is_published = true where slug = 'guide-tel-c'$$), '1');
select tests.as_user('77777777-7777-7777-7777-777777777777');
select tests.eq('Mon téléphone apparaît comme confirmé', (public.my_phone()->>'verified') || '/' || (public.my_phone()->>'phone'), 'true/237670000007');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas changer la règle', $$select public.admin_set_phone_required(false)$$, 'acces_refuse');
select tests.raises('Non-admin ne voit pas le bilan sécurité', $$select public.admin_security_overview()$$, 'acces_refuse');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Bilan sécurité lisible par l''admin', (public.admin_security_overview() ? 'identity_pending')::text, 'true');
select public.admin_set_phone_required(false);
select tests.as_anon();
select tests.raises('Anonyme ne peut pas appeler mfa_ok', $$select public.mfa_ok()$$, 'permission');

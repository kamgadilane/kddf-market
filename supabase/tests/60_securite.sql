-- Tests des correctifs de sécurité (section 27). À lancer APRÈS 10 à 50.
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = false;

\echo ===== C1 : vues et tables en lecture seule =====
select tests.eq('Aucune vue publique modifiable par anon/authenticated',
  (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('v','m')
      and (has_table_privilege('anon', c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE') or has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE'))), '0');
select tests.eq('Aucune table publique en écriture pour anon',
  (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and (has_table_privilege('anon', c.oid, 'INSERT') or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'))), '0');
select tests.eq('Aucune table publique TRUNCATE pour authenticated',
  (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and has_table_privilege('authenticated', c.oid, 'TRUNCATE')), '0');

select count(*) as profiles_avant from public.profiles \gset
select tests.as_anon();
select tests.raises('Anonyme : DELETE sur public_profiles refusé', $$delete from public.public_profiles$$, 'permission denied');
select tests.raises('Anonyme : DELETE sur seller_public_stats refusé', $$delete from public.seller_public_stats$$, 'permission denied');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Connecté : DELETE sur public_profiles refusé', $$delete from public.public_profiles$$, 'permission denied');
select tests.raises('Connecté : UPDATE sur public_profiles refusé', $$update public.public_profiles set store_name = 'x'$$, 'permission denied');
select tests.raises('Connecté : DELETE sur seller_public_stats refusé', $$delete from public.seller_public_stats$$, 'permission denied');
select tests.raises('Connecté : INSERT sur active_boosts refusé', $$insert into public.active_boosts (product_id, plan, ends_at) values (gen_random_uuid(), 'x', now())$$, 'permission denied');
select tests.as_db();
select tests.eq('Les profils sont intacts', (select count(*)::text from public.profiles), :'profiles_avant');
select tests.as_anon();
select tests.eq('Les vues publiques restent lisibles (anon)', (select (count(*) >= 0)::text from public.public_profiles), 'true');

\echo ===== Fonctions internes fermées =====
select tests.as_anon();
select tests.raises('Anonyme : fraud_hold_days() refusé', $$select public.fraud_hold_days()$$, 'permission denied');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Connecté : fraud_active() refusé', $$select public.fraud_active()$$, 'permission denied');
select tests.raises('Connecté : fraud_record_ip() (IP du navigateur) refusé', $$select public.fraud_record_ip('1.2.3.4')$$, 'permission denied');
select tests.raises('Connecté : rate_limit_hit() refusé', $$select public.rate_limit_hit('k', 1, 60)$$, 'permission denied');
select tests.raises('Connecté : register_download() refusé', $$select public.register_download(gen_random_uuid(), 200)$$, 'permission denied');
select tests.raises('Connecté : outbox_claim() refusé', $$select * from public.outbox_claim(5)$$, 'permission denied');
select tests.raises('Connecté : email_outbox illisible', $$select count(*) from public.email_outbox$$, 'permission denied');
select tests.raises('Connecté : rate_limits illisible', $$select count(*) from public.rate_limits$$, 'permission denied');

\echo ===== Limitation de débit =====
select tests.as_service();
select tests.eq('1er appel autorisé', (select public.rate_limit_hit('t:ip1', 3, 60))::text, 'true');
select tests.eq('2e appel autorisé', (select public.rate_limit_hit('t:ip1', 3, 60))::text, 'true');
select tests.eq('3e appel autorisé', (select public.rate_limit_hit('t:ip1', 3, 60))::text, 'true');
select tests.eq('4e appel refusé', (select public.rate_limit_hit('t:ip1', 3, 60))::text, 'false');
select tests.eq('Une autre clé est indépendante', (select public.rate_limit_hit('t:ip2', 3, 60))::text, 'true');
select tests.as_db();
update public.rate_limits set window_start = now() - interval '2 minutes' where key = 't:ip1';
select tests.as_service();
select tests.eq('Fenêtre écoulée : de nouveau autorisé', (select public.rate_limit_hit('t:ip1', 3, 60))::text, 'true');
select tests.eq('Paramètres invalides : on laisse passer', (select public.rate_limit_hit(null, 3, 60))::text, 'true');

\echo ===== File d'attente des emails =====
select tests.as_service();
insert into public.email_outbox (kind, to_email, subject, html, text_body) values ('purchase', 'a@b.cm', 'Sujet', '<p>lien secret</p>', 'lien secret');
select id as mail_id from public.email_outbox where to_email = 'a@b.cm' \gset
select tests.eq('outbox_claim renvoie l''email dû', (select count(*)::text from public.outbox_claim(10)), '1');
select tests.eq('Tentative comptée', (select attempts::text from public.email_outbox where id = :'mail_id'), '1');
select tests.eq('Pas renvoyé tout de suite (verrou temporel)', (select count(*)::text from public.outbox_claim(10)), '0');
select public.outbox_report(:'mail_id', false, 'Resend 500');
select tests.eq('Échec : reste en attente', (select status from public.email_outbox where id = :'mail_id'), 'pending');
select tests.eq('Échec : erreur mémorisée', (select last_error from public.email_outbox where id = :'mail_id'), 'Resend 500');
select tests.as_db();
update public.email_outbox set next_attempt_at = now() - interval '1 minute' where id = :'mail_id';
select tests.as_service();
select tests.eq('Réessai possible après le délai', (select count(*)::text from public.outbox_claim(10)), '1');
select public.outbox_report(:'mail_id', true);
select tests.eq('Succès : statut envoyé', (select status from public.email_outbox where id = :'mail_id'), 'sent');
select tests.eq('Succès : le contenu sensible est effacé', (select html from public.email_outbox where id = :'mail_id'), '[envoyé]');
select tests.as_db();
update public.email_outbox set status = 'pending', attempts = 6, html = 'x' where id = :'mail_id';
select tests.as_service();
select public.outbox_report(:'mail_id', false, 'toujours KO');
select tests.eq('6 échecs : abandon', (select status from public.email_outbox where id = :'mail_id'), 'dead');

\echo ===== Téléchargements =====
select tests.as_db();
select download_token as paid_token, product_id as paid_product from public.orders where payment_status = 'paid' and status <> 'cancelled' limit 1 \gset
select download_token as unpaid_token from public.orders where payment_status <> 'paid' limit 1 \gset
select tests.as_service();
select tests.eq('Commande payée : produit renvoyé', (select (public.register_download(:'paid_token'::uuid, 200) = :'paid_product'::uuid)::text), 'true');
select tests.eq('Compteur incrémenté', (select download_count::text from public.orders where download_token = :'paid_token'::uuid), '1');
select tests.eq('Commande non payée : refusé', (select (public.register_download(:'unpaid_token'::uuid, 200) is null)::text), 'true');
select tests.eq('Jeton inconnu : refusé', (select (public.register_download(gen_random_uuid(), 200) is null)::text), 'true');
select tests.eq('Limite atteinte : refusé', (select (public.register_download(:'paid_token'::uuid, 1) is null)::text), 'true');

\echo ===== Fichiers vendus : chemin de stockage =====
select tests.as_user('11111111-1111-1111-1111-111111111111');
insert into public.product_files (product_id, storage_path, file_name) values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111/guide.pdf', 'guide.pdf');
select tests.eq('Fichier du vendeur enregistré', (select count(*)::text from public.product_files where storage_path = '11111111-1111-1111-1111-111111111111/guide.pdf'), '1');
select tests.raises('Chemin d''un autre vendeur refusé',
  $$insert into public.product_files (product_id, storage_path, file_name) values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222/secret.pdf', 'secret.pdf')$$, 'fichier_invalide');
select tests.raises('Chemin sans dossier refusé',
  $$insert into public.product_files (product_id, storage_path, file_name) values ('aaaaaaaa-0000-0000-0000-000000000001', 'secret.pdf', 'secret.pdf')$$, 'fichier_invalide');
select tests.raises('Modification vers le chemin d''un autre refusée',
  $$update public.product_files set storage_path = '22222222-2222-2222-2222-222222222222/x.pdf' where file_name = 'guide.pdf'$$, 'fichier_invalide');

\echo ===== IP : enregistrée par le serveur seulement =====
select tests.as_service();
select public.fraud_record_ip_for('33333333-3333-3333-3333-333333333333', '203.0.113.9');
select tests.eq('IP enregistrée', (select count(*)::text from public.account_ips where user_id = '33333333-3333-3333-3333-333333333333' and ip = '203.0.113.9'), '1');
select public.fraud_record_ip_for('33333333-3333-3333-3333-333333333333', 'x');
select tests.eq('IP trop courte ignorée', (select count(*)::text from public.account_ips where user_id = '33333333-3333-3333-3333-333333333333'), '1');
select public.fraud_record_ip_for('33333333-3333-3333-3333-333333333333', '10.0.0.' || g) from generate_series(1, 40) g;
select tests.eq('Plafond de 30 IP par compte', (select count(*)::text from public.account_ips where user_id = '33333333-3333-3333-3333-333333333333'), '30');

\echo ===== Grossiste : compte récent refusé =====
select tests.as_db();
update public.profiles set created_at = now() where id = '33333333-3333-3333-3333-333333333333';
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Compte de moins de 24 h refusé', $$select public.wholesale_apply('33333333-3333-3333-3333-333333333333/cni.jpg', '33333333-3333-3333-3333-333333333333/shop.jpg', '+237699000333')$$, 'compte_trop_recent');
select tests.as_db();
update public.profiles set created_at = now() - interval '3 days' where id = '33333333-3333-3333-3333-333333333333';

\echo ===== Liste d'attente =====
select tests.as_anon();
select tests.eq('Inscription liste d''attente', (select (public.join_waitlist('GA', '+24101020304') >= 1))::text, 'true');
select tests.eq('Nouveau pays en attente (Bénin)', (select (public.join_waitlist('BJ', '+22901020304') >= 1))::text, 'true');
select tests.raises('Pays invalide refusé', $$select public.join_waitlist('FR', '+33612345678')$$, 'pays_invalide');

select tests.as_db();
\echo
select 'ÉCHECS: ' || tests.fail_count();

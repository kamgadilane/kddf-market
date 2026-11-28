-- Tests V3.7 : annonces / cloche de notification.  À lancer APRÈS 10 à 120.
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
delete from public.announcements;
delete from public.pro_subscriptions;
-- 1111 = vendeur (a des produits) ; 3333 = acheteur sans produit
select tests.eq('Prérequis : 1111 vend, 3333 ne vend pas', ((select count(*) from public.products where seller_id = '11111111-1111-1111-1111-111111111111') > 0 and (select count(*) from public.products where seller_id = '33333333-3333-3333-3333-333333333333') = 0)::text, 'true');

\echo ===== Annonces : envoi et sécurité =====
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas envoyer', $$select public.admin_send_announcement('Bonjour', 'Message de test', 'all', null)$$, 'acces_refuse');
select tests.raises('Non-admin ne peut pas lister côté admin', $$select * from public.admin_list_announcements()$$, 'acces_refuse');
select tests.raises('Accès direct à la table refusé', $$select * from public.announcements$$, 'permission');
select tests.raises('Écriture directe refusée', $$insert into public.announcements (title, body) values ('abc', 'def')$$, 'permission');
select tests.as_anon();
select tests.raises('Anonyme ne peut pas envoyer', $$select public.admin_send_announcement('Bonjour', 'Message de test', 'all', null)$$, 'permission');
select tests.raises('Anonyme ne peut pas lire ses annonces', $$select * from public.my_announcements()$$, 'permission');

select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Titre trop court refusé', $$select public.admin_send_announcement('ab', 'Message de test', 'all', null)$$, 'annonce_invalide');
select tests.raises('Message vide refusé', $$select public.admin_send_announcement('Titre ok', '  ', 'all', null)$$, 'annonce_invalide');
select tests.raises('Message de 501 caractères refusé', format('select public.admin_send_announcement(%L, %L, %L, null)', 'Titre ok', repeat('a', 501), 'all'), 'annonce_invalide');
select tests.raises('Audience inconnue refusée', $$select public.admin_send_announcement('Titre ok', 'Message de test', 'tous', null)$$, 'annonce_invalide');
select tests.raises('Lien javascript: refusé', $$select public.admin_send_announcement('Titre ok', 'Message de test', 'all', 'javascript:alert(1)')$$, 'annonce_lien_invalide');
select tests.raises('Lien http (non sécurisé) refusé', $$select public.admin_send_announcement('Titre ok', 'Message de test', 'all', 'http://exemple.com')$$, 'annonce_lien_invalide');
select tests.raises('Lien //site refusé', $$select public.admin_send_announcement('Titre ok', 'Message de test', 'all', '//evil.com')$$, 'annonce_lien_invalide');
select tests.raises('Durée 0 jour refusée', $$select public.admin_send_announcement('Titre ok', 'Message de test', 'all', null, 0)$$, 'annonce_invalide');

select public.admin_send_announcement('Bienvenue', 'Découvrez le retrait express.', 'all', '/dashboard/wallet') as a_all \gset
select public.admin_send_announcement('Pour les vendeurs', 'Pensez à mettre vos produits à jour.', 'sellers', 'https://kddf-market.vercel.app/dashboard') as a_sel \gset
select public.admin_send_announcement('Pour les Pro', 'Merci pour votre abonnement.', 'pro', null) as a_pro \gset
select public.admin_send_announcement('Expirée', 'Cette annonce va expirer.', 'all', null, 1) as a_exp \gset
select tests.as_db();
update public.announcements set expires_at = now() - interval '1 minute' where id = :'a_exp';
update public.announcements set created_at = now() - interval '40 days' where title = 'Bienvenue' and false;

\echo ===== Annonces : lecture par audience =====
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.eq('Acheteur : voit seulement l''annonce « tous » (1)', (select count(*)::text from public.my_announcements()), '1');
select tests.eq('Acheteur : 1 non lue', public.my_unread_announcements()::text, '1');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Vendeur non Pro : « tous » + « vendeurs » (2)', (select count(*)::text from public.my_announcements()), '2');
select tests.as_db();
insert into public.pro_subscriptions (user_id, amount, status, fapshi_trans_id, starts_at, ends_at, paid_at) values ('11111111-1111-1111-1111-111111111111', 3000, 'paid', 'ann-pro', now() - interval '1 hour', now() + interval '10 days', now());
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Vendeur Pro : les 3 annonces (all, vendeurs, Pro)', (select count(*)::text from public.my_announcements()), '3');
select tests.eq('Annonce expirée jamais visible', (select count(*)::text from public.my_announcements() where title = 'Expirée'), '0');
select tests.eq('Le lien interne est conservé', (select link from public.my_announcements() where title = 'Bienvenue'), '/dashboard/wallet');

\echo ===== Annonces : lu / non lu =====
select tests.eq('Vendeur Pro : 3 non lues avant ouverture', public.my_unread_announcements()::text, '3');
select public.mark_announcements_read();
select tests.eq('Après ouverture de la cloche : 0 non lue', public.my_unread_announcements()::text, '0');
select tests.eq('Les annonces restent listées, marquées lues', (select count(*) filter (where is_read)::text from public.my_announcements()), '3');
select public.mark_announcements_read();
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.eq('Lecture d''un autre compte inchangée (acheteur : toujours 1 non lue)', public.my_unread_announcements()::text, '1');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_send_announcement('Nouvelle', 'Une nouvelle annonce pour tous.', 'all', null) as a_new \gset
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Nouvelle annonce : 1 non lue', public.my_unread_announcements()::text, '1');

\echo ===== Annonces : liste admin, suppression, limite =====
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin : voit 5 annonces avec le nombre de lectures', (select count(*)::text from public.admin_list_announcements()), '5');
select tests.eq('Admin : « Bienvenue » lue par 1 compte', (select reads::text from public.admin_list_announcements() where title = 'Bienvenue'), '1');
select public.admin_delete_announcement(:'a_new'::uuid);
select tests.eq('Annonce supprimée', (select count(*)::text from public.admin_list_announcements() where title = 'Nouvelle'), '0');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas supprimer', $$select public.admin_delete_announcement(gen_random_uuid())$$, 'acces_refuse');
select tests.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin for i in 1..6 loop perform public.admin_send_announcement('Rafale ' || i, 'Test de limite', 'all', null); end loop; end $$;
select tests.raises('Plus de 10 annonces par heure : refusé', $$select public.admin_send_announcement('Trop', 'Une de trop', 'all', null)$$, 'trop_d_annonces');
select tests.as_db();
delete from public.announcements;

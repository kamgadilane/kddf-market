-- Tests V3.9 : identité des vendeurs (cartes + selfie, validation admin, garde de publication) et alertes d'erreurs.
-- À lancer APRÈS 10 à 140 (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.commission_settings set identity_required = true;
delete from public.identity_verifications;
delete from public.user_notifications;
-- Nouveau vendeur 5555 (le profil est créé par le déclencheur d'inscription)
insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555', 'identite5@test.cm') on conflict (id) do nothing;
insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666', 'identite6@test.cm') on conflict (id) do nothing;

\echo ===== I1 : sans identité validée, publier est refusé ; un brouillon reste possible =====
select tests.eq('Le bucket privé « identity » existe', (select count(*) || '/' || bool_or(public)::text from storage.buckets where id = 'identity'), '1/false');
select tests.eq('Brouillon autorisé', tests.rows($$insert into public.products (id, seller_id, product_type, digital_kind, title, slug, price, is_published) values ('cccccccc-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'digital', 'file', 'Guide brouillon', 'guide-brouillon', 5000, false)$$), '1');
select tests.raises('Publication à la création refusée', $$insert into public.products (seller_id, product_type, digital_kind, title, slug, price, is_published) values ('55555555-5555-5555-5555-555555555555', 'digital', 'file', 'Guide publié', 'guide-publie', 5000, true)$$, 'identite_requise');
select tests.raises('Publier un brouillon refusé', $$update public.products set is_published = true where id = 'cccccccc-0000-0000-0000-000000000001'$$, 'identite_requise');
select tests.eq('Le brouillon est resté brouillon', (select is_published::text from public.products where id = 'cccccccc-0000-0000-0000-000000000001'), 'false');
select tests.eq('Un administrateur publie sans documents', tests.rows($$insert into public.products (id, seller_id, product_type, digital_kind, title, slug, price, is_published) values ('cccccccc-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', 'digital', 'file', 'Guide admin', 'guide-admin', 5000, true)$$), '1');

\echo ===== I2 : envoi des documents =====
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.eq('État initial : none', (public.my_identity()->>'status'), 'none');
select tests.raises('Chemin d''un autre utilisateur refusé', $$select public.identity_submit('66666666-6666-6666-6666-666666666666/recto.jpg', '55555555-5555-5555-5555-555555555555/verso.jpg', '55555555-5555-5555-5555-555555555555/selfie.mp4', 'video')$$, 'identite_documents_invalides');
select tests.raises('Document manquant refusé', $$select public.identity_submit('55555555-5555-5555-5555-555555555555/recto.jpg', null, '55555555-5555-5555-5555-555555555555/selfie.mp4', 'video')$$, 'identite_documents_invalides');
select tests.raises('Type de selfie inconnu refusé', $$select public.identity_submit('55555555-5555-5555-5555-555555555555/recto.jpg', '55555555-5555-5555-5555-555555555555/verso.jpg', '55555555-5555-5555-5555-555555555555/selfie.mp4', 'gif')$$, 'identite_documents_invalides');
select public.identity_submit('55555555-5555-5555-5555-555555555555/recto.jpg', '55555555-5555-5555-5555-555555555555/verso.jpg', '55555555-5555-5555-5555-555555555555/selfie.mp4', 'video');
select tests.eq('Après envoi : pending', (public.my_identity()->>'status'), 'pending');
select tests.raises('Second envoi pendant l''attente refusé', $$select public.identity_submit('55555555-5555-5555-5555-555555555555/recto2.jpg', '55555555-5555-5555-5555-555555555555/verso2.jpg', '55555555-5555-5555-5555-555555555555/selfie2.jpg', 'photo')$$, 'identite_en_attente');
select tests.eq('Je ne vois que ma propre demande', (select count(*)::text from public.identity_verifications), '1');
select tests.raises('Écriture directe refusée', $$update public.identity_verifications set status = 'approved'$$, 'permission');
select tests.raises('Insertion directe refusée', $$insert into public.identity_verifications (user_id, front_path, back_path, selfie_path, status) values ('55555555-5555-5555-5555-555555555555', 'a', 'b', 'c', 'approved')$$, 'permission');
select tests.as_db();
select tests.raises('Toujours bloqué tant que pending', $$update public.products set is_published = true where id = 'cccccccc-0000-0000-0000-000000000001'$$, 'identite_requise');
select tests.eq('L''administrateur a reçu une alerte dans la cloche', (select count(*)::text from public.user_notifications where user_id = '44444444-4444-4444-4444-444444444444' and link = '/admin/identite'), '1');

\echo ===== I3 : décision de l'administrateur =====
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas lister', $$select * from public.admin_identity_list()$$, 'acces_refuse');
select tests.raises('Non-admin ne peut pas décider', $$select public.admin_identity_decide('55555555-5555-5555-5555-555555555555', true, null)$$, 'acces_refuse');
select tests.as_anon();
select tests.raises('Anonyme ne peut pas envoyer', $$select public.identity_submit('a/b', 'a/c', 'a/d', 'photo')$$, 'permission');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('La liste admin contient la demande', (select count(*)::text from public.admin_identity_list() where user_id = '55555555-5555-5555-5555-555555555555'), '1');
select tests.raises('Refus sans motif refusé', $$select public.admin_identity_decide('55555555-5555-5555-5555-555555555555', false, '  ')$$, 'motif_requis');
select public.admin_identity_decide('55555555-5555-5555-5555-555555555555', false, 'Photo floue : le texte de la carte est illisible');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.eq('Statut refusé + motif visible', (public.my_identity()->>'status') || '/' || (public.my_identity()->>'reason'), 'rejected/Photo floue : le texte de la carte est illisible');
select tests.as_db();
select tests.eq('Le vendeur est prévenu du refus (cloche)', (select count(*)::text from public.user_notifications where user_id = '55555555-5555-5555-5555-555555555555' and title = 'Identité refusée'), '1');
select tests.raises('Toujours bloqué après refus', $$update public.products set is_published = true where id = 'cccccccc-0000-0000-0000-000000000001'$$, 'identite_requise');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Décider une demande déjà traitée refusé', $$select public.admin_identity_decide('55555555-5555-5555-5555-555555555555', true, null)$$, 'demande_introuvable');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select public.identity_submit('55555555-5555-5555-5555-555555555555/recto3.jpg', '55555555-5555-5555-5555-555555555555/verso3.jpg', '55555555-5555-5555-5555-555555555555/selfie3.jpg', 'photo');
select tests.eq('Nouvel envoi possible après refus : pending', (public.my_identity()->>'status'), 'pending');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_identity_decide('55555555-5555-5555-5555-555555555555', true, null);
select tests.as_db();
select tests.eq('Validé : statut approved + badge vérifié', (select v.status || '/' || p.is_verified::text from public.identity_verifications v join public.profiles p on p.id = v.user_id where v.user_id = '55555555-5555-5555-5555-555555555555'), 'approved/true');
select tests.eq('Le vendeur peut publier', tests.rows($$update public.products set is_published = true where id = 'cccccccc-0000-0000-0000-000000000001'$$), '1');
select tests.eq('Le vendeur est prévenu de la validation (cloche)', (select count(*)::text from public.user_notifications where user_id = '55555555-5555-5555-5555-555555555555' and title = 'Identité validée'), '1');
select tests.as_user('55555555-5555-5555-5555-555555555555');
select tests.raises('Renvoyer des documents une fois validé refusé', $$select public.identity_submit('55555555-5555-5555-5555-555555555555/r.jpg', '55555555-5555-5555-5555-555555555555/v.jpg', '55555555-5555-5555-5555-555555555555/s.jpg', 'photo')$$, 'identite_deja_verifiee');

\echo ===== I4 : interrupteur administrateur =====
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas changer la règle', $$select public.admin_set_identity_required(false)$$, 'acces_refuse');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_identity_required(false);
select tests.as_db();
select tests.eq('Règle désactivée : un autre vendeur publie sans documents', tests.rows($$insert into public.products (seller_id, product_type, digital_kind, title, slug, price, is_published) values ('66666666-6666-6666-6666-666666666666', 'digital', 'file', 'Guide libre', 'guide-libre', 5000, true)$$), '1');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_set_identity_required(true);
select tests.as_anon();
select tests.eq('La règle est lisible publiquement (affichage de la bannière)', (select identity_required::text from public.commission_settings where id = 1), 'true');

\echo ===== I5 : alertes d'erreurs pour l'administrateur =====
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Un utilisateur ne peut pas déclencher d''alerte', $$select public.alert_admins_error('x', '/p')$$, 'permission');
select tests.as_service();
select tests.eq('1re alerte : envoyée', public.alert_admins_error('TypeError : x is undefined', '/p/abc')::text, 'true');
select tests.eq('2e alerte dans les 30 min : ignorée (pas de déluge)', public.alert_admins_error('Autre erreur', '/')::text, 'false');
select tests.as_db();
select tests.eq('Une seule alerte dans la cloche de l''admin', (select count(*)::text from public.user_notifications where user_id = '44444444-4444-4444-4444-444444444444' and title = 'Erreur sur le site'), '1');
update public.user_notifications set created_at = now() - interval '31 minutes' where title = 'Erreur sur le site';
select tests.as_service();
select tests.eq('Après 30 min : nouvelle alerte envoyée', public.alert_admins_error('Erreur plus tard', null)::text, 'true');


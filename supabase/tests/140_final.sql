-- Tests V3.8 : PROJET FINAL (frais de service acheteur, limite du plan gratuit, notifications personnelles, journal d'erreurs, suppression de compte, export).
-- À lancer APRÈS 10 à 130 (schema.sql déjà exécuté).
\set ON_ERROR_STOP off
\pset tuples_only on
\pset format unaligned
select tests.as_db();
update public.fraud_settings set is_active = false;
update public.profiles set fraud_review = false, is_blocked = false, commission_exempt = false;
delete from public.pro_subscriptions;
update public.commission_settings set is_launch_mode = true, launch_start_date = current_date - 40, launch_end_date = current_date - 10, platform_fee_percent = 8, after_launch_percent = 8, pro_percent = 5, free_product_limit = 10;
insert into public.service_fee_rules (gateway, percent, fixed_amount) values ('fapshi', 0, 0), ('flutterwave', 3, 0), ('crypto', 1, 0), ('paypal', 5, 300)
  on conflict (gateway) do update set percent = excluded.percent, fixed_amount = excluded.fixed_amount;
insert into public.products (id, seller_id, product_type, title, slug, price, is_published, affiliate_percent, stock, images, whatsapp_seller, delivery_options, moderation_status) values
 ('bbbbbbbb-0000-0000-0000-0000000000f1', '11111111-1111-1111-1111-111111111111', 'physical', 'Sac Final', 'sac-final', 10000, true, 20, 500, array['https://img/p.jpg'], '699000111',
  '{"pickup_douala":{"enabled":true,"price":0}}', 'approved')
 on conflict (id) do nothing;

-- Crée une commande de 10 000 FCFA (retrait Douala) et renvoie l'identifiant de la transaction
create or replace function tests.new_order(p_phone text) returns uuid language plpgsql security definer as $$
declare r jsonb;
begin
  r := public.create_checkout_order('bbbbbbbb-0000-0000-0000-0000000000f1', null, null, 'Client Final', 1, 'pickup_douala', null, p_phone, null, 'online', 'Douala', 'Bonapriso', '10.3.3.3');
  return (r->>'transaction_id')::uuid;
end $$;


-- Applique les frais puis renvoie « frais/total » lus APRÈS la mise à jour (une même requête SQL ne voit pas ses propres modifications)
create or replace function tests.fee(p_tx uuid, p_gw text) returns text language plpgsql security definer as $$
begin
  perform public.apply_service_fee(p_tx, p_gw);
  return (select service_fee || '/' || total_amount from public.transactions where id = p_tx);
end $$;
create or replace function tests.rows(p_sql text) returns text language plpgsql security definer as $$
declare n integer;
begin execute p_sql; get diagnostics n = row_count; return n::text; end $$;
create or replace function tests.confirm(p_ref text, p_amount bigint) returns text language plpgsql security definer as $$
declare r jsonb;
begin
  r := public.confirm_fapshi_payment(p_ref, p_amount, 'paypal', null);
  return (r->>'status') || '/' || coalesce((select review_reason from public.transactions where fapshi_trans_id = p_ref), '');
end $$;

\echo ===== F1 : frais de service selon la passerelle =====
select tests.as_service();
select tests.new_order('+237 655 140 001') as tx1 \gset
select tests.eq('PayPal : 5 % de 10 000 + 300 = 800, total 10 800', tests.fee(:'tx1', 'paypal'), '800/10800');
select tests.eq('Appel répété = même résultat (pas de cumul)', (select service_fee || '/' || total_amount from public.transactions where id = :'tx1'), '800/10800');
select tests.eq('Cartes : 3 % = 300', tests.fee(:'tx1', 'flutterwave'), '300/10300');
select tests.eq('Crypto : 1 % = 100', tests.fee(:'tx1', 'crypto'), '100/10100');
select tests.eq('Fapshi : 0 frais, total = prix', tests.fee(:'tx1', 'fapshi'), '0/10000');
select tests.eq('Passerelle inconnue : aucun frais', split_part(tests.fee(:'tx1', 'inconnue'), '/', 1), '0');
select tests.eq('Le prix de la commande (vendeur) ne change jamais', (select o.total_price::text from public.orders o join public.transactions t on t.order_id = o.id where t.id = :'tx1'), '10000');
select tests.raises('Transaction inconnue refusée', $$select public.apply_service_fee('00000000-0000-0000-0000-00000000dead', 'paypal')$$, 'transaction_inconnue');

\echo ===== F2 : paiement PayPal avec frais : le vendeur ne paie pas les frais =====
select public.apply_service_fee(:'tx1', 'paypal');
update public.transactions set fapshi_trans_id = 'fin-1', fapshi_link = 'https://pay.test/fin-1' where id = :'tx1';
select public.confirm_fapshi_payment('fin-1', 10800, 'paypal', null);
select tests.eq('Total payé 10 800 = frais 800 + commission 800 + vendeur 9 200', (select total_amount || '=' || service_fee || '+' || platform_fee || '+' || seller_amount from public.transactions where id = :'tx1'), '10800=800+800+9200');
select tests.eq('Statut payé', (select status from public.transactions where id = :'tx1'), 'paid');
select tests.raises('Frais modifiables seulement avant le paiement', format('select public.apply_service_fee(%L, %L)', :'tx1', 'crypto'), 'transaction_deja_traitee');

\echo ===== F3 : montant sans les frais = bloqué =====
select tests.new_order('+237 655 140 002') as tx2 \gset
select public.apply_service_fee(:'tx2', 'paypal');
update public.transactions set fapshi_trans_id = 'fin-2', fapshi_link = 'https://pay.test/fin-2' where id = :'tx2';
select tests.eq('Payé 10 000 alors que 10 800 attendus -> à vérifier', tests.confirm('fin-2', 10000), 'review/montant_different');

\echo ===== F4 : vente Mobile Money (0 frais) inchangée =====
select tests.new_order('+237 655 140 003') as tx3 \gset
select public.apply_service_fee(:'tx3', 'fapshi');
update public.transactions set fapshi_trans_id = 'fin-3', fapshi_link = 'https://pay.test/fin-3' where id = :'tx3';
select public.confirm_fapshi_payment('fin-3', 10000, 'mtn', null);
select tests.eq('Mobile Money : 10 000 = 0 + 800 + 9 200', (select total_amount || '=' || service_fee || '+' || platform_fee || '+' || seller_amount from public.transactions where id = :'tx3'), '10000=0+800+9200');
select tests.eq('Garantie : somme exacte pour toutes les ventes payées', (select count(*)::text from public.transactions where status = 'paid' and total_amount <> service_fee + platform_fee + affiliate_fee + seller_amount), '0');

\echo ===== F5 : sécurité et réglage admin =====
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Un utilisateur ne peut pas appliquer de frais', $$select public.apply_service_fee('00000000-0000-0000-0000-00000000dead', 'paypal')$$, 'permission');
select tests.raises('Non-admin ne peut pas régler les frais', $$select public.admin_set_service_fee('paypal', 1, 0)$$, 'acces_refuse');
select tests.raises('Écriture directe sur les règles refusée', $$update public.service_fee_rules set percent = 0$$, 'permission');
select tests.eq('Un acheteur peut lire les frais (aperçu avant paiement)', (select count(*)::text from public.service_fee_rules), '4');
select tests.as_anon();
select tests.eq('Un visiteur peut lire les frais', (select count(*)::text from public.service_fee_rules), '4');
select tests.raises('Un visiteur ne peut pas les modifier', $$delete from public.service_fee_rules$$, 'permission');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Pourcentage 16 refusé', $$select public.admin_set_service_fee('paypal', 16, 0)$$, 'valeur_invalide');
select tests.raises('Montant fixe 5001 refusé', $$select public.admin_set_service_fee('paypal', 5, 5001)$$, 'valeur_invalide');
select tests.raises('Passerelle inconnue refusée', $$select public.admin_set_service_fee('bitcoin', 1, 0)$$, 'valeur_invalide');
select public.admin_set_service_fee('crypto', 2.5, 100);
select tests.eq('Réglage admin enregistré', (select percent || '/' || fixed_amount from public.service_fee_rules where gateway = 'crypto'), '2.50/100');
select tests.eq('Aperçu admin : frais de service encaissés = 800', (public.admin_overview()->>'service_fees'), '800');
select public.admin_set_service_fee('crypto', 1, 0);

\echo ===== G : limite du plan gratuit =====
select tests.as_db();
delete from public.products where seller_id = '33333333-3333-3333-3333-333333333333';
update public.commission_settings set free_product_limit = 2;
create or replace function tests.add_product(p_n text, p_pub boolean) returns void language plpgsql security definer as $$
begin
  insert into public.products (seller_id, product_type, title, slug, price, is_published, stock, images, whatsapp_seller, delivery_options, moderation_status)
  values ('33333333-3333-3333-3333-333333333333', 'physical', 'Produit ' || p_n, 'produit-' || p_n, 5000, p_pub, 10, array['https://img/p.jpg'], '699000222', '{"pickup_douala":{"enabled":true,"price":0}}', 'approved');
end $$;
select tests.add_product('a', true);
select tests.add_product('b', true);
select tests.raises('3e produit publié refusé (limite 2)', $$select tests.add_product('c', true)$$, 'limite_produits_gratuit');
select tests.add_product('d', false);
select tests.eq('Un brouillon ne compte pas', (select count(*)::text from public.products where seller_id = '33333333-3333-3333-3333-333333333333' and not is_published), '1');
select tests.raises('Publier le brouillon refusé', $$update public.products set is_published = true where slug = 'produit-d'$$, 'limite_produits_gratuit');
select tests.eq('Modifier un produit déjà publié reste possible', tests.rows($q$update public.products set price = 5100, is_published = true where slug = 'produit-a'$q$), '1');
select tests.eq('Dépublier puis republier : le slot est libéré', tests.rows($q$update public.products set is_published = false where slug = 'produit-a'$q$), '1');
select tests.eq('Publier le brouillon maintenant possible', tests.rows($q$update public.products set is_published = true where slug = 'produit-d'$q$), '1');
update public.products set is_published = false where slug = 'produit-d';
-- Pro = illimité
insert into public.pro_subscriptions (user_id, amount, status, starts_at, ends_at, paid_at) values ('33333333-3333-3333-3333-333333333333', 3000, 'paid', now(), now() + interval '30 days', now());
select tests.eq('Vendeur Pro : publication illimitée', tests.rows($q$update public.products set is_published = true where slug in ('produit-a', 'produit-d')$q$), '2');
delete from public.pro_subscriptions;
update public.products set is_published = false where slug in ('produit-a', 'produit-d');
-- Exempté = illimité ; limite 0 = illimité pour tous
update public.profiles set commission_exempt = true where id = '33333333-3333-3333-3333-333333333333';
select tests.eq('Compte exempté : publication illimitée', tests.rows($q$update public.products set is_published = true where slug in ('produit-a', 'produit-d')$q$), '2');
update public.profiles set commission_exempt = false where id = '33333333-3333-3333-3333-333333333333';
update public.products set is_published = false where slug in ('produit-a', 'produit-d');
update public.commission_settings set free_product_limit = 0;
select tests.eq('Limite 0 = illimité', tests.rows($q$update public.products set is_published = true where slug in ('produit-a', 'produit-b', 'produit-d')$q$), '3');
update public.commission_settings set free_product_limit = 10;
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Non-admin ne peut pas changer la limite', $$select public.admin_set_free_product_limit(50)$$, 'acces_refuse');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Limite négative refusée', $$select public.admin_set_free_product_limit(-1)$$, 'valeur_invalide');
select tests.raises('Limite 1001 refusée', $$select public.admin_set_free_product_limit(1001)$$, 'valeur_invalide');
select public.admin_set_free_product_limit(25);
select tests.as_db();
select tests.eq('Limite admin enregistrée', (select free_product_limit::text from public.commission_settings where id = 1), '25');
update public.commission_settings set free_product_limit = 10;

\echo ===== H : notifications personnelles =====
select tests.as_db();
delete from public.user_notifications;
select tests.new_order('+237 655 140 010') as tx4 \gset
select public.apply_service_fee(:'tx4', 'fapshi');
update public.transactions set fapshi_trans_id = 'fin-4', fapshi_link = 'https://pay.test/fin-4' where id = :'tx4';
select public.confirm_fapshi_payment('fin-4', 10000, 'mtn', null);
select tests.eq('Vente payée -> le vendeur reçoit « Nouvelle vente »', (select count(*)::text from public.user_notifications where user_id = '11111111-1111-1111-1111-111111111111' and title = 'Nouvelle vente'), '1');
select tests.eq('Les autres utilisateurs ne reçoivent rien', (select count(*)::text from public.user_notifications where user_id <> '11111111-1111-1111-1111-111111111111'), '0');
insert into public.withdrawals (id, user_id, amount, method, phone_number) values ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 1000, 'mtn_momo', '699000111');
update public.withdrawals set status = 'paid', processed_at = now() where id = 'cccccccc-0000-0000-0000-000000000001';
select tests.eq('Retrait payé -> notification', (select count(*)::text from public.user_notifications where title = 'Retrait effectué'), '1');
insert into public.withdrawals (id, user_id, amount, method, phone_number) values ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 1000, 'mtn_momo', '699000111');
update public.withdrawals set status = 'failed', processed_at = now() where id = 'cccccccc-0000-0000-0000-000000000002';
select tests.eq('Retrait refusé -> notification', (select count(*)::text from public.user_notifications where title = 'Retrait refusé'), '1');
insert into public.wholesale_applications (user_id, cni_path, shop_photo_path, whatsapp, status) values ('22222222-2222-2222-2222-222222222222', 'x/cni.jpg', 'x/shop.jpg', '699000333', 'pending')
  on conflict (user_id) do update set status = 'pending';
update public.wholesale_applications set status = 'approved' where user_id = '22222222-2222-2222-2222-222222222222';
select tests.eq('Grossiste validé -> notification', (select count(*)::text from public.user_notifications where user_id = '22222222-2222-2222-2222-222222222222' and title = 'Compte grossiste validé'), '1');
update public.products set moderation_status = 'pending' where id = 'bbbbbbbb-0000-0000-0000-0000000000f1';
update public.products set moderation_status = 'approved' where id = 'bbbbbbbb-0000-0000-0000-0000000000f1';
select tests.eq('Produit validé -> notification', (select count(*)::text from public.user_notifications where title = 'Produit validé'), '1');
select public.notify_user(null, 'a', 'b');
select tests.eq('notify_user(null) ne plante pas', 'ok', 'ok');

select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('La cloche du vendeur compte ses messages (au moins 4)', (select (public.my_unread_notifications() >= 4)::text), 'true');
select tests.eq('Liste fusionnée contient des messages personnels', (select (count(*) filter (where kind = 'perso') >= 4)::text from public.my_notifications(30)), 'true');
select tests.raises('Accès direct à la table refusé', $$select * from public.user_notifications$$, 'permission');
select public.mark_notifications_read();
select tests.eq('Tout lu après ouverture de la cloche', (select public.my_unread_notifications()::text), '0');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.eq('Un autre utilisateur ne voit pas ces messages', (select count(*)::text from public.my_notifications(30) where kind = 'perso'), '0');
select tests.as_anon();
select tests.raises('Visiteur : cloche refusée', $$select public.my_unread_notifications()$$, 'permission');
select tests.raises('Visiteur : lecture refusée', $$select * from public.my_notifications(10)$$, 'permission');
select tests.as_db();
update public.user_notifications set created_at = now() - interval '70 days' where title = 'Produit validé';
select public.notify_user('11111111-1111-1111-1111-111111111111', 'Test purge', 'Message de test');
select tests.eq('Les messages de plus de 60 jours sont nettoyés', (select count(*)::text from public.user_notifications where title = 'Produit validé'), '0');

\echo ===== I : journal des erreurs =====
select tests.as_service();
select public.log_app_error('client', repeat('x', 800), '/p/test', 'abc123', null);
select public.log_app_error('serveur', 'Erreur de test', '/api/test', null, '11111111-1111-1111-1111-111111111111');
select public.log_app_error('nimportequoi', '   ', null, null, '00000000-0000-0000-0000-00000000dead');
select tests.eq('3 erreurs enregistrées', (select count(*)::text from public.app_errors), '3');
select tests.eq('Message tronqué à 500', (select max(char_length(message))::text from public.app_errors), '500');
select tests.eq('Source inconnue -> client ; message vide -> erreur inconnue ; utilisateur inconnu ignoré', (select count(*)::text from public.app_errors where source = 'client' and message = 'erreur inconnue' and user_id is null), '1');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.raises('Un utilisateur ne peut pas écrire dans le journal', $$select public.log_app_error('client', 'x', null, null, null)$$, 'permission');
select tests.raises('Un utilisateur ne peut pas lire le journal', $$select * from public.admin_list_errors()$$, 'acces_refuse');
select tests.raises('Accès direct refusé', $$select * from public.app_errors$$, 'permission');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.eq('Admin : liste du journal', (select count(*)::text from public.admin_list_errors()), '3');
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.raises('Non-admin ne peut pas vider', $$select public.admin_clear_errors()$$, 'acces_refuse');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select public.admin_clear_errors();
select tests.eq('Journal vidé', (select count(*)::text from public.admin_list_errors()), '0');
select tests.as_db();
insert into public.app_errors (created_at, message) values (now() - interval '40 days', 'vieille erreur');
select tests.as_service();
select public.log_app_error('client', 'nouvelle', null, null, null);
select tests.eq('Les erreurs de plus de 30 jours sont purgées', (select count(*)::text from public.app_errors where message = 'vieille erreur'), '0');

\echo ===== J : export et suppression de compte =====
select tests.as_user('11111111-1111-1111-1111-111111111111');
select tests.eq('Export : ventes présentes', (select (jsonb_array_length(public.export_my_data()->'ventes') >= 3)::text), 'true');
select tests.eq('Export : profil présent', (select (public.export_my_data()->'profil'->>'id')), '11111111-1111-1111-1111-111111111111');
select tests.raises('Vendeur avec solde : suppression refusée', $$select public.delete_my_account()$$, 'solde_non_vide');
select tests.as_user('44444444-4444-4444-4444-444444444444');
select tests.raises('Admin : suppression refusée', $$select public.delete_my_account()$$, 'admin_non_supprimable');
select tests.as_anon();
select tests.raises('Visiteur : suppression refusée', $$select public.delete_my_account()$$, 'permission');
select tests.raises('Visiteur : export refusé', $$select public.export_my_data()$$, 'permission');
select tests.as_db();
update public.disputes set status = 'refusé' where status = 'en_attente' and (buyer_id = '33333333-3333-3333-3333-333333333333' or seller_id = '33333333-3333-3333-3333-333333333333');
update public.orders set buyer_id = null where buyer_id = '33333333-3333-3333-3333-333333333333';
insert into public.withdrawals (id, user_id, amount, method, phone_number) values ('cccccccc-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 1000, 'mtn_momo', '699000222');
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.raises('Retrait en attente : suppression refusée', $$select public.delete_my_account()$$, 'retrait_en_cours');
select tests.as_db();
delete from public.withdrawals where id = 'cccccccc-0000-0000-0000-000000000003';
select tests.as_user('33333333-3333-3333-3333-333333333333');
select tests.eq('Compte sans historique : supprimable, pas de trace à garder', (public.delete_my_account()->>'keep_login_record'), 'false');
select tests.as_db();
select tests.eq('Profil anonymisé', (select full_name || '/' || (deleted_at is not null)::text || '/' || coalesce(phone, 'null') from public.profiles where id = '33333333-3333-3333-3333-333333333333'), 'Compte supprimé/true/null');
select tests.eq('Produits dépubliés', (select count(*)::text from public.products where seller_id = '33333333-3333-3333-3333-333333333333' and is_published), '0');

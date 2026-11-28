-- KDDF Market V3.8 - MISE À JOUR FINALE (à exécuter UNE FOIS dans Supabase > SQL Editor, AVANT d'envoyer le nouveau code).
-- Contient uniquement le bloc 33 ; peut être relancée sans risque.

-- =====================================================================
-- 33. V3.8 PROJET FINAL
--   33.1 Frais de service payés par l'acheteur selon le moyen de paiement (PayPal, cartes, crypto), réglables dans l'admin
--   33.2 Limite de produits publiés du plan gratuit (10 par défaut, réglable ; 0 = illimité ; Pro / exempté / admin = illimité)
--   33.3 Notifications personnelles dans la cloche (vente, retrait, grossiste, litige, produit validé, Pro)
--   33.4 Journal des erreurs de l'application (visible dans Admin > Erreurs)
--   33.5 Suppression de compte et export des données personnelles
--   Ce bloc est aussi fourni seul dans supabase/mise-a-jour-finale.sql (à exécuter AVANT d'envoyer le nouveau code).
--   Il peut être exécuté plusieurs fois sans risque.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 33.1 FRAIS DE SERVICE ACHETEUR
--   transactions.total_amount = ce que l'acheteur PAIE (prix + livraison + frais de service).
--   Le vendeur reçoit toujours : prix + livraison - commission - part d'affilié (les frais de service restent à la plateforme).
--   orders.total_price ne change pas (prix + livraison) : c'est la base du vendeur.
-- ---------------------------------------------------------------------
create table if not exists public.service_fee_rules (
  gateway      text primary key check (gateway in ('fapshi', 'flutterwave', 'crypto', 'paypal')),
  percent      numeric(4, 2) not null default 0 check (percent between 0 and 15),
  fixed_amount integer not null default 0 check (fixed_amount between 0 and 5000),   -- FCFA
  updated_at   timestamptz not null default now()
);
-- Valeurs de départ (estimées d'après les frais des passerelles, modifiables dans Admin > Commissions) :
-- Fapshi (Mobile Money) 0 % car la plateforme absorbe ses 3 % ; PayPal 5 % + 300 FCFA ; cartes 3 % ; crypto 1 %.
insert into public.service_fee_rules (gateway, percent, fixed_amount) values
  ('fapshi', 0, 0), ('flutterwave', 3, 0), ('crypto', 1, 0), ('paypal', 5, 300)
on conflict (gateway) do nothing;

alter table public.service_fee_rules enable row level security;
revoke all on public.service_fee_rules from anon, authenticated;
grant select on public.service_fee_rules to anon, authenticated;   -- l'acheteur voit les frais avant de payer
drop policy if exists service_fee_rules_lecture on public.service_fee_rules;
create policy service_fee_rules_lecture on public.service_fee_rules for select using (true);

alter table public.transactions add column if not exists service_fee     bigint not null default 0 check (service_fee >= 0);
alter table public.transactions add column if not exists service_gateway text;

-- Garantie finale mise à jour : total payé = frais de service + commission + affilié + vendeur
alter table public.transactions drop constraint if exists paid_split_is_exact;
alter table public.transactions add constraint paid_split_is_exact check (
  status <> 'paid'
  or (
    platform_fee is not null and affiliate_fee is not null and seller_amount is not null
    and total_amount = service_fee + platform_fee + affiliate_fee + seller_amount
  )
);

-- Calcule et enregistre les frais de service d'une transaction EN ATTENTE, selon la passerelle choisie.
-- Idempotent : le total est toujours recalculé depuis la commande (prix + livraison), jamais depuis le total précédent.
create or replace function public.apply_service_fee(p_tx uuid, p_gateway text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t     public.transactions%rowtype;
  o     public.orders%rowtype;
  r     public.service_fee_rules%rowtype;
  v_fee bigint := 0;
begin
  select * into t from public.transactions where id = p_tx for update;
  if not found then raise exception 'transaction_inconnue'; end if;
  if t.status <> 'pending' then raise exception 'transaction_deja_traitee'; end if;
  select * into o from public.orders where id = t.order_id;
  select * into r from public.service_fee_rules where gateway = p_gateway;
  if found and (r.percent > 0 or r.fixed_amount > 0) then
    v_fee := ceil(o.total_price * r.percent / 100)::bigint + r.fixed_amount;
  end if;
  update public.transactions
     set service_fee = v_fee, service_gateway = p_gateway, total_amount = o.total_price + v_fee
   where id = t.id;
  return jsonb_build_object('service_fee', v_fee, 'total', o.total_price + v_fee);
end $$;
revoke all on function public.apply_service_fee(uuid, text) from public, anon, authenticated;
grant execute on function public.apply_service_fee(uuid, text) to service_role;

-- Réglage par l'administrateur
create or replace function public.admin_set_service_fee(p_gateway text, p_percent numeric, p_fixed integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_gateway is null or p_gateway not in ('fapshi', 'flutterwave', 'crypto', 'paypal')
     or p_percent is null or p_percent < 0 or p_percent > 15
     or p_fixed is null or p_fixed < 0 or p_fixed > 5000 then
    raise exception 'valeur_invalide';
  end if;
  insert into public.service_fee_rules (gateway, percent, fixed_amount, updated_at)
  values (p_gateway, p_percent, p_fixed, now())
  on conflict (gateway) do update set percent = excluded.percent, fixed_amount = excluded.fixed_amount, updated_at = now();
end $$;
revoke all on function public.admin_set_service_fee(text, numeric, integer) from public, anon;
grant execute on function public.admin_set_service_fee(text, numeric, integer) to authenticated;

-- Confirmation de paiement : le vendeur ne reçoit JAMAIS les frais de service (version mise à jour de la fonction)
create or replace function public.confirm_fapshi_payment(
  p_trans_id text,
  p_amount   bigint,
  p_medium   text,
  p_revenue  bigint
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t            public.transactions%rowtype;
  o            public.orders%rowtype;
  p            public.products%rowtype;
  s            record;
  v_review     text;
  v_key        text;
  v_goods      bigint;
  v_has_aff    boolean;
  v_seller_amt bigint;
  v_digital    boolean;
begin
  select * into t from public.transactions where fapshi_trans_id = p_trans_id for update;
  if not found then raise exception 'transaction_inconnue'; end if;

  -- Déjà traitée : on ne fait rien (protection contre les webhooks rejoués).
  if t.status in ('paid', 'review', 'refunded') then
    return jsonb_build_object('status', 'already', 'order_id', t.order_id);
  end if;

  select * into o from public.orders where id = t.order_id for update;
  select * into p from public.products where id = o.product_id for update;
  v_digital := (p.product_type = 'digital');

  -- Contrôle 1 : le montant payé doit être EXACTEMENT celui de la commande.
  if p_amount is distinct from t.total_amount then
    v_review := 'montant_different';
  -- Contrôle 2 : stock (physique) ou clé de licence (digital) encore disponible.
  elsif not v_digital then
    update public.products set stock = stock - o.quantity where id = p.id and stock >= o.quantity;
    if not found then v_review := 'stock_insuffisant'; end if;
  elsif p.digital_kind = 'license' then
    select key into v_key from public.license_keys
      where product_id = p.id and order_id is null
      order by created_at, id limit 1 for update skip locked;
    if v_key is null then
      v_review := 'licence_epuisee';
    else
      update public.license_keys set order_id = o.id, assigned_at = now()
        where product_id = p.id and key = v_key;
    end if;
  end if;

  -- Paiement reçu mais impossible de livrer automatiquement : on garde la trace,
  -- on NE crédite PERSONNE, et l'admin traite le cas (remboursement manuel).
  if v_review is not null then
    update public.transactions
       set status = 'review', review_reason = v_review, fapshi_status = 'SUCCESSFUL',
           fapshi_medium = p_medium, fapshi_revenue = p_revenue, paid_at = now()
     where id = t.id;
    update public.orders set payment_status = 'paid', paid_at = now() where id = o.id;
    update public.orders set status = 'cancelled' where id = o.id;
    -- MANIPULATION DE MONTANT : le montant reçu ne correspond pas à la commande -> bloqué + tracé dans fraud_logs (visible dans /admin/fraude)
    if v_review = 'montant_different' then
      begin
        insert into public.fraud_logs (user_id, order_id, seller_id, reason, risk_score, action, transaction_id, amount, status, resolved_at)
        values (o.buyer_id, o.id, o.seller_id,
                'Montant différent : reçu ' || coalesce(p_amount, 0) || ' FCFA, attendu ' || t.total_amount || ' FCFA',
                100, 'blocked', t.id, greatest(coalesce(p_amount, 0), 0), 'blocked', now());
      exception when others then
        raise warning 'fraud_logs (montant) ignoré : %', sqlerrm;   -- la trace ne doit jamais empêcher le blocage
      end;
    end if;
    return jsonb_build_object('status', 'review', 'reason', v_review, 'order_id', o.id);
  end if;

  -- Répartition (entiers FCFA) sur le prix des articles ; la livraison reste au vendeur.
  v_goods   := o.unit_price * o.quantity;
  v_has_aff := o.affiliate_id is not null and o.affiliate_id <> o.seller_id and o.affiliate_percent is not null;
  select * into s from public.compute_split_for_seller(o.seller_id, v_goods, v_has_aff, o.affiliate_percent, not v_digital);
  -- Frais de service payés par l'acheteur : ils restent à la plateforme (ils couvrent les frais de la passerelle), jamais au vendeur
  v_seller_amt := t.total_amount - coalesce(t.service_fee, 0) - s.platform_fee - s.affiliate_fee;
  if v_seller_amt < 0 then raise exception 'repartition_invalide'; end if;

  update public.transactions
     set status = 'paid',
         paid_at = now(),
         fapshi_status = 'SUCCESSFUL',
         fapshi_medium = p_medium,
         fapshi_revenue = p_revenue,
         affiliate_id = case when v_has_aff then o.affiliate_id else null end,
         goods_amount = v_goods,
         platform_fee = s.platform_fee,
         platform_fee_percent = round(s.platform_percent)::integer,
         platform_fee_rate = s.platform_percent,
         affiliate_fee = s.affiliate_fee,
         affiliate_fee_percent = s.affiliate_percent,
         seller_amount = v_seller_amt,
         -- digital : fonds libérés après 24 h ; physique : libérés à la livraison (voir plus bas)
         release_at = case when v_digital then now() + interval '24 hours' else null end
   where id = t.id;

  -- En attente -> Payé (puis, pour un produit digital, Payé -> Livré : deux étapes, jamais de saut)
  update public.orders set payment_status = 'paid', paid_at = now() where id = o.id;
  if v_digital then
    update public.orders set status = 'delivered', delivered_at = now() where id = o.id;
  end if;

  -- Soldes "en attente" du vendeur et de l'affilié
  insert into public.wallets (user_id, balance_pending, total_earned)
  values (o.seller_id, v_seller_amt, v_seller_amt)
  on conflict (user_id) do update
    set balance_pending = public.wallets.balance_pending + excluded.balance_pending,
        total_earned    = public.wallets.total_earned + excluded.total_earned,
        updated_at      = now();

  if v_has_aff and s.affiliate_fee > 0 then
    insert into public.wallets (user_id, balance_pending, total_earned)
    values (o.affiliate_id, s.affiliate_fee, s.affiliate_fee)
    on conflict (user_id) do update
      set balance_pending = public.wallets.balance_pending + excluded.balance_pending,
          total_earned    = public.wallets.total_earned + excluded.total_earned,
          updated_at      = now();
  end if;

  return jsonb_build_object(
    'status', 'paid',
    'order_id', o.id,
    'buyer_email', o.buyer_email,
    'buyer_name', o.buyer_name,
    'product_title', p.title,
    'product_type', p.product_type,
    'download_token', o.download_token,
    'license_key', v_key,
    'total', t.total_amount,
    'platform_fee', s.platform_fee,
    'affiliate_fee', s.affiliate_fee,
    'service_fee', coalesce(t.service_fee, 0),
    'seller_amount', v_seller_amt
  );
end $$;
revoke all on function public.confirm_fapshi_payment(text, bigint, text, bigint) from public, anon, authenticated;
grant execute on function public.confirm_fapshi_payment(text, bigint, text, bigint) to service_role;

-- Vue admin « frais par taux » (avec les frais de service encaissés)
drop view if exists public.admin_fee_summary;
create view public.admin_fee_summary with (security_invoker = true) as
  select coalesce(platform_fee_rate, platform_fee_percent)::numeric as platform_fee_percent,
         count(*)::bigint                       as sales,
         coalesce(sum(total_amount), 0)::bigint as volume,
         coalesce(sum(platform_fee), 0)::bigint as platform_fees,
         coalesce(sum(affiliate_fee), 0)::bigint as affiliate_fees,
         coalesce(sum(seller_amount), 0)::bigint as seller_amounts,
         coalesce(sum(fapshi_revenue), 0)::bigint as fapshi_received,
         coalesce(sum(service_fee), 0)::bigint  as service_fees
    from public.transactions
   where status = 'paid'
   group by coalesce(platform_fee_rate, platform_fee_percent)::numeric;
grant select on public.admin_fee_summary to authenticated;
revoke all on public.admin_fee_summary from anon;

create or replace function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  select jsonb_build_object(
    'stats',           (select to_jsonb(s) from public.admin_stats s),
    'fees',            coalesce((select jsonb_agg(to_jsonb(f)) from public.admin_fee_summary f), '[]'::jsonb),
    'affiliates',      public.admin_affiliate_count(),
    'boost_revenue',   (select coalesce(sum(amount), 0) from public.product_boosts where status = 'paid'),
    'pro_revenue',     (select coalesce(sum(amount), 0) from public.pro_subscriptions where status = 'paid'),
    'pro_active',      (select count(*) from public.active_pro),
    'withdrawal_fees', (select coalesce(sum(fee), 0) from public.withdrawals where status = 'paid'),
    'service_fees',    (select coalesce(sum(service_fee), 0) from public.transactions where status = 'paid')
  ) into v;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 33.2 LIMITE DU PLAN GRATUIT : nombre de produits PUBLIÉS (les brouillons ne comptent pas)
-- ---------------------------------------------------------------------
alter table public.commission_settings add column if not exists free_product_limit integer not null default 10 check (free_product_limit between 0 and 1000);
grant select (free_product_limit) on public.commission_settings to anon, authenticated;

create or replace function public.products_free_limit_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_limit integer; v_count integer;
begin
  if not new.is_published then return new; end if;
  if tg_op = 'UPDATE' and old.is_published then return new; end if;     -- déjà publié : modification normale
  select free_product_limit into v_limit from public.commission_settings where id = 1;
  v_limit := coalesce(v_limit, 10);
  if v_limit = 0 then return new; end if;                               -- 0 = illimité
  if coalesce((select commission_exempt from public.profiles where id = new.seller_id), false)
     or coalesce((select role = 'admin' from public.profiles where id = new.seller_id), false)
     or public.is_pro(new.seller_id) then
    return new;
  end if;
  select count(*) into v_count from public.products where seller_id = new.seller_id and is_published and id <> new.id;
  if v_count >= v_limit then raise exception 'limite_produits_gratuit'; end if;
  return new;
end $$;
revoke all on function public.products_free_limit_guard() from public, anon, authenticated;
drop trigger if exists products_free_limit_trg on public.products;
create trigger products_free_limit_trg before insert or update of is_published on public.products
  for each row execute function public.products_free_limit_guard();

create or replace function public.admin_set_free_product_limit(p_limit integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_limit is null or p_limit < 0 or p_limit > 1000 then raise exception 'valeur_invalide'; end if;
  update public.commission_settings set free_product_limit = p_limit where id = 1;
end $$;
revoke all on function public.admin_set_free_product_limit(integer) from public, anon;
grant execute on function public.admin_set_free_product_limit(integer) to authenticated;

-- ---------------------------------------------------------------------
-- 33.3 NOTIFICATIONS PERSONNELLES (la cloche affiche maintenant les annonces ET les messages personnels)
-- ---------------------------------------------------------------------
create table if not exists public.user_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 80),
  body       text not null check (char_length(body) between 1 and 300),
  link       text check (link is null or (char_length(link) <= 300 and link ~ '^/($|[^/])')),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists user_notifications_user_idx on public.user_notifications (user_id, created_at desc);
alter table public.user_notifications enable row level security;
revoke all on public.user_notifications from anon, authenticated;
drop policy if exists notifications_aucun_acces_direct on public.user_notifications;
create policy notifications_aucun_acces_direct on public.user_notifications for all using (false) with check (false);

-- Interne : ne bloque JAMAIS l'action qui l'a déclenchée (vente, retrait...) ; supprime les messages de plus de 60 jours de cette personne
create or replace function public.notify_user(p_user uuid, p_title text, p_body text, p_link text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  begin
    delete from public.user_notifications where user_id = p_user and created_at < now() - interval '60 days';
    insert into public.user_notifications (user_id, title, body, link)
    values (p_user, left(p_title, 80), left(p_body, 300), p_link);
  exception when others then
    raise warning 'notify_user ignoré : %', sqlerrm;
  end;
end $$;
revoke all on function public.notify_user(uuid, text, text, text) from public, anon, authenticated;

create or replace function public.trg_notify_order() returns trigger language plpgsql security definer set search_path = public as $$
declare v_title text;
begin
  select title into v_title from public.products where id = new.product_id;
  if tg_op = 'INSERT' then
    if new.payment_method = 'cod' then
      perform public.notify_user(new.seller_id, 'Nouvelle commande (paiement à la livraison)', coalesce(v_title, 'Produit') || ' × ' || new.quantity, '/dashboard/orders');
    end if;
  elsif new.payment_status = 'paid' and old.payment_status is distinct from 'paid' and new.payment_method is distinct from 'cod' then
    perform public.notify_user(new.seller_id, 'Nouvelle vente', coalesce(v_title, 'Produit') || ' × ' || new.quantity, '/dashboard/orders');
  end if;
  return null;
end $$;
drop trigger if exists notify_order_ins on public.orders;
create trigger notify_order_ins after insert on public.orders for each row execute function public.trg_notify_order();
drop trigger if exists notify_order_upd on public.orders;
create trigger notify_order_upd after update of payment_status on public.orders for each row execute function public.trg_notify_order();

create or replace function public.trg_notify_withdrawal() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'paid' then
      perform public.notify_user(new.user_id, 'Retrait effectué', 'Votre retrait de ' || new.amount || ' FCFA a été envoyé.', '/dashboard/wallet');
    elsif new.status = 'failed' then
      perform public.notify_user(new.user_id, 'Retrait refusé', 'Votre retrait de ' || new.amount || ' FCFA n''a pas pu être effectué : votre solde a été rétabli.', '/dashboard/wallet');
    end if;
  end if;
  return null;
end $$;
drop trigger if exists notify_withdrawal_upd on public.withdrawals;
create trigger notify_withdrawal_upd after update of status on public.withdrawals for each row execute function public.trg_notify_withdrawal();

create or replace function public.trg_notify_wholesale() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'approved' then
      perform public.notify_user(new.user_id, 'Compte grossiste validé', 'Vous pouvez maintenant vendre en gros.', '/dashboard/products');
    elsif new.status = 'rejected' then
      perform public.notify_user(new.user_id, 'Candidature grossiste refusée', 'Vérifiez vos documents puis déposez une nouvelle demande.', '/grossistes');
    end if;
  end if;
  return null;
end $$;
drop trigger if exists notify_wholesale_upd on public.wholesale_applications;
create trigger notify_wholesale_upd after update of status on public.wholesale_applications for each row execute function public.trg_notify_wholesale();

create or replace function public.trg_notify_product() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.moderation_status is distinct from old.moderation_status then
    if new.moderation_status = 'approved' then
      perform public.notify_user(new.seller_id, 'Produit validé', '« ' || left(new.title, 60) || ' » est visible sur la boutique.', '/dashboard/products');
    elsif new.moderation_status = 'rejected' then
      perform public.notify_user(new.seller_id, 'Produit refusé', '« ' || left(new.title, 60) || ' » n''a pas été accepté. Modifiez-le puis renvoyez-le.', '/dashboard/products');
    end if;
  end if;
  return null;
end $$;
drop trigger if exists notify_product_upd on public.products;
create trigger notify_product_upd after update of moderation_status on public.products for each row execute function public.trg_notify_product();

create or replace function public.trg_notify_dispute() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_user(new.seller_id, 'Litige ouvert sur une commande', 'Un acheteur a ouvert un litige. Consultez vos commandes.', '/dashboard/orders');
  return null;
end $$;
drop trigger if exists notify_dispute_ins on public.disputes;
create trigger notify_dispute_ins after insert on public.disputes for each row execute function public.trg_notify_dispute();

create or replace function public.trg_notify_pro() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    perform public.notify_user(new.user_id, 'Abonnement Pro activé', 'Merci ! Vos avantages Pro sont actifs.', '/dashboard/pro');
  end if;
  return null;
end $$;
drop trigger if exists notify_pro_upd on public.pro_subscriptions;
create trigger notify_pro_upd after update of status on public.pro_subscriptions for each row execute function public.trg_notify_pro();

revoke all on function public.trg_notify_order(), public.trg_notify_withdrawal(), public.trg_notify_wholesale(), public.trg_notify_product(), public.trg_notify_dispute(), public.trg_notify_pro() from public, anon, authenticated;

-- Fonctions de la cloche : annonces + messages personnels, fusionnés
create or replace function public.my_notifications(p_limit integer default 30)
returns table (id uuid, title text, body text, link text, created_at timestamptz, is_read boolean, kind text)
language sql stable security definer set search_path = public as $$
  select * from (
    select a.id, a.title, a.body, a.link, a.created_at,
           exists (select 1 from public.announcement_reads r where r.announcement_id = a.id and r.user_id = auth.uid()) as is_read,
           'annonce'::text as kind
      from public.visible_announcements(auth.uid()) a
    union all
    select n.id, n.title, n.body, n.link, n.created_at, (n.read_at is not null), 'perso'::text
      from public.user_notifications n
     where auth.uid() is not null and n.user_id = auth.uid() and n.created_at > now() - interval '60 days'
  ) x
  order by x.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 60)
$$;

create or replace function public.my_unread_notifications()
returns integer language sql stable security definer set search_path = public as $$
  select (
    (select count(*) from public.visible_announcements(auth.uid()) a
      where not exists (select 1 from public.announcement_reads r where r.announcement_id = a.id and r.user_id = auth.uid()))
    + (select count(*) from public.user_notifications n where auth.uid() is not null and n.user_id = auth.uid() and n.read_at is null and n.created_at > now() - interval '60 days')
  )::integer
$$;

create or replace function public.mark_notifications_read()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  perform public.mark_announcements_read();
  update public.user_notifications set read_at = now() where user_id = auth.uid() and read_at is null;
end $$;

revoke all on function public.my_notifications(integer), public.my_unread_notifications(), public.mark_notifications_read() from public, anon;
grant execute on function public.my_notifications(integer), public.my_unread_notifications(), public.mark_notifications_read() to authenticated;

-- ---------------------------------------------------------------------
-- 33.4 JOURNAL DES ERREURS (écrit par le serveur via /api/errors ; lu par l'admin)
-- ---------------------------------------------------------------------
create table if not exists public.app_errors (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  source     text not null default 'client' check (source in ('client', 'serveur')),
  message    text not null check (char_length(message) <= 500),
  url        text check (url is null or char_length(url) <= 300),
  digest     text check (digest is null or char_length(digest) <= 80),
  user_id    uuid references public.profiles(id) on delete set null
);
create index if not exists app_errors_created_idx on public.app_errors (created_at desc);
alter table public.app_errors enable row level security;
revoke all on public.app_errors from anon, authenticated;
drop policy if exists app_errors_aucun_acces_direct on public.app_errors;
create policy app_errors_aucun_acces_direct on public.app_errors for all using (false) with check (false);

create or replace function public.log_app_error(p_source text, p_message text, p_url text, p_digest text, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.app_errors where created_at < now() - interval '30 days';
  insert into public.app_errors (source, message, url, digest, user_id)
  values (case when p_source = 'serveur' then 'serveur' else 'client' end,
          left(coalesce(nullif(btrim(p_message), ''), 'erreur inconnue'), 500), left(p_url, 300), left(p_digest, 80),
          (select id from public.profiles where id = p_user));
end $$;
revoke all on function public.log_app_error(text, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.log_app_error(text, text, text, text, uuid) to service_role;

create or replace function public.admin_list_errors()
returns table (id bigint, created_at timestamptz, source text, message text, url text, digest text, occurrences bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  return query
    select e.id, e.created_at, e.source, e.message, e.url, e.digest,
           (select count(*) from public.app_errors x where x.message = e.message and x.created_at > now() - interval '30 days')
      from public.app_errors e order by e.created_at desc limit 100;
end $$;
create or replace function public.admin_clear_errors()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  delete from public.app_errors where true;
end $$;
revoke all on function public.admin_list_errors(), public.admin_clear_errors() from public, anon;
grant execute on function public.admin_list_errors(), public.admin_clear_errors() to authenticated;

-- ---------------------------------------------------------------------
-- 33.5 SUPPRESSION DE COMPTE + EXPORT DES DONNÉES
--   delete_my_account() vérifie les conditions puis ANONYMISE le profil et dépublie les produits ;
--   le serveur supprime ensuite le compte de connexion (ou le désactive si des ventes / retraits doivent être conservés).
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists deleted_at timestamptz;

create or replace function public.delete_my_account()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  w         record;
  v_history boolean;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if public.is_admin() then raise exception 'admin_non_supprimable'; end if;

  select coalesce(balance_pending, 0) + coalesce(balance_available, 0) as balance, coalesce(commission_due, 0) as due
    into w from public.wallets where user_id = v_uid;
  if found and w.balance > 0 then raise exception 'solde_non_vide'; end if;
  if found and w.due > 0 then raise exception 'commission_due'; end if;
  if exists (select 1 from public.withdrawals where user_id = v_uid and status = 'pending') then raise exception 'retrait_en_cours'; end if;
  if exists (select 1 from public.disputes where status = 'en_attente' and (buyer_id = v_uid or seller_id = v_uid)) then raise exception 'litige_en_cours'; end if;
  if exists (
    select 1 from public.orders
     where (seller_id = v_uid or buyer_id = v_uid) and payment_status = 'paid'
       and delivery_method is not null and status not in ('completed', 'cancelled')
  ) then raise exception 'commandes_en_cours'; end if;

  v_history := exists (select 1 from public.orders where seller_id = v_uid)
            or exists (select 1 from public.transactions where seller_id = v_uid)
            or exists (select 1 from public.withdrawals where user_id = v_uid);

  update public.products set is_published = false where seller_id = v_uid;
  delete from public.user_notifications where user_id = v_uid;
  update public.profiles
     set full_name = 'Compte supprimé', store_name = null, store_slug = null, avatar_url = null, phone = null, whatsapp = null,
         city = null, shop_logo_url = null, shop_banner_url = null, shop_description = null, deleted_at = now()
   where id = v_uid;
  return jsonb_build_object('keep_login_record', v_history);
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

create or replace function public.export_my_data()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  return jsonb_build_object(
    'exporte_le', now(),
    'profil', (select to_jsonb(p) from (select id, full_name, store_name, store_slug, phone, whatsapp, city, country, created_at from public.profiles where id = v_uid) p),
    'produits', coalesce((select jsonb_agg(to_jsonb(x)) from (select id, title, price, product_type, is_published, created_at from public.products where seller_id = v_uid order by created_at) x), '[]'::jsonb),
    'achats', coalesce((select jsonb_agg(to_jsonb(x)) from (select id, product_id, quantity, total_price, status, payment_status, created_at from public.orders where buyer_id = v_uid order by created_at) x), '[]'::jsonb),
    'ventes', coalesce((select jsonb_agg(to_jsonb(x)) from (select order_id, total_amount, service_fee, platform_fee, affiliate_fee, seller_amount, status, paid_at from public.transactions where seller_id = v_uid order by created_at) x), '[]'::jsonb),
    'retraits', coalesce((select jsonb_agg(to_jsonb(x)) from (select amount, method, status, created_at, processed_at from public.withdrawals where user_id = v_uid order by created_at) x), '[]'::jsonb),
    'portefeuille', (select to_jsonb(w) from (select balance_pending, balance_available, total_earned, total_withdrawn from public.wallets where user_id = v_uid) w)
  );
end $$;
revoke all on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

notify pgrst, 'reload schema';

-- KDDF Market : mise à jour « revenus » (frais de retrait, abonnement Pro, exemption, boosts 14/30 jours, bannières, tarifs modifiables).
-- À coller dans Supabase > SQL Editor > Run. Sans danger si lancé plusieurs fois.

-- =====================================================================
-- 28. REVENUS SUPPLÉMENTAIRES
--     frais de retrait, abonnement Pro, compte exempté de commission, boosts 14/30 jours, bannières sponsorisées
--     (Ce bloc est aussi fourni seul dans supabase/mise-a-jour-revenus.sql pour une base déjà en ligne : on peut le relancer sans risque.)
-- =====================================================================

-- 28.1  Nouvelles colonnes
alter table public.profiles            add column if not exists commission_exempt boolean not null default false;   -- 0 % de commission et pas de frais de retrait (modifiable seulement par l'admin)
alter table public.transactions        add column if not exists platform_fee_rate numeric(5, 2);                    -- taux exact appliqué (ex. 1,5 % pour un vendeur Pro)
alter table public.commission_settings add column if not exists pro_percent numeric(4, 2) not null default 5 check (pro_percent between 0 and 10);
alter table public.withdrawals         add column if not exists fee bigint not null default 0 check (fee >= 0);     -- frais de retrait prélevé sur le paiement

-- 28.2  Abonnement Pro (30 jours payés d'avance, sans renouvellement automatique)
create table if not exists public.pro_subscriptions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  amount          bigint not null check (amount >= 100),
  status          text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'expired', 'review')),
  fapshi_trans_id text unique,
  fapshi_link     text,
  fapshi_status   text,
  last_checked_at timestamptz,
  starts_at       timestamptz,
  ends_at         timestamptz,
  created_at      timestamptz not null default now(),
  paid_at         timestamptz
);
create index if not exists pro_subscriptions_user_idx on public.pro_subscriptions (user_id, status, ends_at);
alter table public.pro_subscriptions enable row level security;
drop policy if exists pro_subscriptions_select on public.pro_subscriptions;
create policy pro_subscriptions_select on public.pro_subscriptions for select using (user_id = auth.uid() or public.is_admin());
revoke insert, update, delete, truncate on public.pro_subscriptions from anon, authenticated;
revoke all on public.pro_subscriptions from anon;
grant select on public.pro_subscriptions to authenticated;

-- Vendeurs Pro actifs : public (sert au badge « Pro »)
create or replace view public.active_pro as
  select user_id, ends_at from public.pro_subscriptions
   where status = 'paid' and starts_at <= now() and ends_at > now();
grant select on public.active_pro to anon, authenticated;

create or replace function public.is_pro(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.pro_subscriptions where user_id = p_user and status = 'paid' and starts_at <= now() and ends_at > now())
$$;

-- Confirme le paiement d'un abonnement Pro (appelée par le serveur APRÈS vérification chez Fapshi). Un renouvellement s'ajoute à la fin de l'abonnement en cours.
create or replace function public.confirm_pro_payment(p_trans_id text, p_amount bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b       public.pro_subscriptions%rowtype;
  v_start timestamptz;
begin
  select * into b from public.pro_subscriptions where fapshi_trans_id = p_trans_id for update;
  if not found then raise exception 'abonnement_inconnu'; end if;
  if b.status in ('paid', 'review') then return jsonb_build_object('status', 'already', 'id', b.id); end if;

  if p_amount is distinct from b.amount then
    update public.pro_subscriptions set status = 'review', fapshi_status = 'SUCCESSFUL', paid_at = now() where id = b.id;
    return jsonb_build_object('status', 'review', 'id', b.id);
  end if;

  select greatest(now(), coalesce(max(ends_at), now())) into v_start
    from public.pro_subscriptions where user_id = b.user_id and status = 'paid' and ends_at > now();
  update public.pro_subscriptions
     set status = 'paid', fapshi_status = 'SUCCESSFUL', paid_at = now(), starts_at = v_start, ends_at = v_start + interval '30 days'
   where id = b.id;
  return jsonb_build_object('status', 'paid', 'id', b.id);
end $$;

create or replace function public.mark_pro_failed(p_trans_id text, p_fapshi_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.pro_subscriptions
     set status = case when p_fapshi_status = 'EXPIRED' then 'expired' else 'failed' end, fapshi_status = p_fapshi_status
   where fapshi_trans_id = p_trans_id and status = 'pending';
end $$;

-- 28.3  Taux de commission PAR VENDEUR : exempté = 0 %, Pro = pro_percent (réglable dans l'admin, 5 % par défaut) au plus, sinon taux normal
create or replace function public.seller_platform_rate(p_seller uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_base numeric; v_pro numeric;
begin
  if coalesce((select commission_exempt from public.profiles where id = p_seller), false) then return 0; end if;
  v_base := public.effective_platform_percent();
  if public.is_pro(p_seller) then
    select pro_percent into v_pro from public.commission_settings where id = 1;
    return least(v_base, coalesce(v_pro, 5));
  end if;
  return v_base;
end $$;

create or replace function public.compute_split_for_seller(p_seller uuid, p_goods bigint, p_has_affiliate boolean, p_affiliate_percent integer, p_physical boolean)
returns table (platform_percent numeric, platform_fee bigint, affiliate_percent integer, affiliate_fee bigint)
language plpgsql stable security definer set search_path = public as $$
declare
  v_pct numeric := public.seller_platform_rate(p_seller);
  v_aff integer := case when p_has_affiliate then least(greatest(coalesce(p_affiliate_percent, 0), 0), 50) else 0 end;
begin
  return query select v_pct, floor(p_goods * v_pct / 100)::bigint, v_aff,
                      case when p_has_affiliate then (p_goods * v_aff) / 100 else 0::bigint end;
end $$;

-- Fonctions internes : jamais appelables depuis le navigateur
revoke all on function public.is_pro(uuid)                                                    from public, anon, authenticated;
revoke all on function public.seller_platform_rate(uuid)                                      from public, anon, authenticated;
revoke all on function public.compute_split_for_seller(uuid, bigint, boolean, integer, boolean) from public, anon, authenticated;
revoke all on function public.confirm_pro_payment(text, bigint)                               from public, anon, authenticated;
revoke all on function public.mark_pro_failed(text, text)                                     from public, anon, authenticated;
grant execute on function public.confirm_pro_payment(text, bigint) to service_role;
grant execute on function public.mark_pro_failed(text, text)       to service_role;

-- Les ventes utilisent maintenant le taux du VENDEUR (exempté / Pro / normal)
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
  v_seller_amt := t.total_amount - s.platform_fee - s.affiliate_fee;
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
    'seller_amount', v_seller_amt
  );
end $$;

create or replace function public.seller_confirm_cash(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o       public.orders%rowtype;
  v_goods bigint;
  s       record;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.seller_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  if o.payment_method <> 'cod' or o.payment_status <> 'pending' or o.status = 'cancelled' or o.delivery_method is null then
    raise exception 'commande_invalide';
  end if;

  v_goods := o.unit_price * o.quantity;                       -- commission sur les articles (hors livraison)
  select * into s from public.compute_split_for_seller(o.seller_id, v_goods, false, 0, true);

  update public.orders set payment_status = 'paid', paid_at = now() where id = o.id;                 -- En attente -> Payé (cash encaissé)
  update public.orders set status = 'delivered', delivered_at = now() where id = o.id;               -- Payé -> Livré

  update public.transactions
     set status = 'paid', paid_at = now(), goods_amount = v_goods,
         platform_fee = s.platform_fee, platform_fee_percent = round(s.platform_percent)::integer, platform_fee_rate = s.platform_percent,
         affiliate_fee = 0, affiliate_fee_percent = 0, seller_amount = total_amount - s.platform_fee,
         release_at = now(), released_at = now()                -- le cash est déjà chez le vendeur : rien à libérer
   where order_id = o.id;

  update public.orders set status = 'completed' where id = o.id;                                    -- Livré -> Terminé (le cash est déjà chez le vendeur)
  update public.wallets set commission_due = commission_due + s.platform_fee, updated_at = now() where user_id = o.seller_id;
end $$;

-- Vue admin « frais par taux » : on regroupe sur le taux exact (1,5 % possible)
drop view if exists public.admin_fee_summary;
create view public.admin_fee_summary with (security_invoker = true) as
  select coalesce(platform_fee_rate, platform_fee_percent)::numeric as platform_fee_percent,
         count(*)::bigint                       as sales,
         coalesce(sum(total_amount), 0)::bigint as volume,
         coalesce(sum(platform_fee), 0)::bigint as platform_fees,
         coalesce(sum(affiliate_fee), 0)::bigint as affiliate_fees,
         coalesce(sum(seller_amount), 0)::bigint as seller_amounts,
         coalesce(sum(fapshi_revenue), 0)::bigint as fapshi_received
    from public.transactions
   where status = 'paid'
   group by coalesce(platform_fee_rate, platform_fee_percent)::numeric;
grant select on public.admin_fee_summary to authenticated;
revoke all on public.admin_fee_summary from anon;

-- 28.4  Frais de retrait (1,5 %, minimum 200 FCFA ; 0 pour un compte exempté)
create or replace function public.request_withdrawal(p_amount bigint, p_method text, p_phone text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_id     uuid;
  v_deduct bigint := 0;
  v_base   bigint;
  v_fee    bigint := 0;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if p_method is null or p_method not in ('mtn_momo', 'orange_money', 'wave', 'moov_money', 'mpesa', 'bank_transfer', 'crypto_usdt', 'crypto_btc', 'paypal') then raise exception 'methode_invalide'; end if;
  if public.is_blocked(v_uid) then raise exception 'compte_bloque'; end if;
  if p_amount is null or p_amount < 1000 then raise exception 'montant_minimum'; end if;   -- minimum de retrait : 1 000 FCFA
  -- Destination selon le moyen choisi
  if p_method in ('mtn_momo', 'orange_money', 'wave', 'moov_money', 'mpesa') then
    if p_phone is null or p_phone !~ '^\+?[0-9]{8,15}$' then raise exception 'telephone_invalide'; end if;
  elsif p_method = 'paypal' then
    if p_phone is null or p_phone !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(p_phone) > 254 then raise exception 'destination_invalide'; end if;
  elsif p_method in ('crypto_usdt', 'crypto_btc') then
    if p_phone is null or p_phone !~ '^[A-Za-z0-9:_-]{20,120}$' then raise exception 'destination_invalide'; end if;
  else  -- bank_transfer : IBAN / numéro de compte + nom de la banque (texte libre court)
    if p_phone is null or length(btrim(p_phone)) < 8 or length(p_phone) > 120 then raise exception 'destination_invalide'; end if;
  end if;

  perform public.release_due_funds(v_uid);

  update public.wallets
     set balance_available = balance_available - p_amount, updated_at = now()
   where user_id = v_uid and balance_available >= p_amount;
  if not found then raise exception 'solde_insuffisant'; end if;

  -- Commission due sur les ventes payées en cash à la livraison : prélevée sur CE retrait.
  select least(commission_due, p_amount) into v_deduct from public.wallets where user_id = v_uid;
  update public.wallets set commission_due = commission_due - v_deduct where user_id = v_uid;

  -- Frais de retrait : 1,5 % (minimum 200 FCFA) sur le montant restant après la commission cash. Compte exempté : aucun frais.
  -- Le frais n'est PAS retiré du solde : il est simplement déduit du paiement envoyé (à payer = demandé - commission cash - frais).
  v_base := p_amount - v_deduct;
  if not coalesce((select commission_exempt from public.profiles where id = v_uid), false) then
    v_fee := least(v_base, greatest(200, ceil(v_base * 15 / 1000.0)::bigint));
  end if;

  insert into public.withdrawals (user_id, amount, method, phone_number, commission_deducted, fee)
  values (v_uid, p_amount, p_method, p_phone, v_deduct, v_fee)
  returning id into v_id;
  return v_id;
end $$;

-- 28.5  L'admin exempte un compte (par e-mail) : 0 % de commission et aucun frais de retrait
create or replace function public.admin_set_commission_exempt(p_email text, p_exempt boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  select id into v_id from auth.users where lower(email) = lower(btrim(coalesce(p_email, ''))) limit 1;
  if v_id is null then raise exception 'utilisateur_introuvable'; end if;
  update public.profiles set commission_exempt = coalesce(p_exempt, false) where id = v_id;
end $$;
revoke all on function public.admin_set_commission_exempt(text, boolean) from public, anon;
grant execute on function public.admin_set_commission_exempt(text, boolean) to authenticated;

-- 28.6  Boosts 14 et 30 jours
do $b$
declare r record;
begin
  for r in select conname from pg_constraint where conrelid = 'public.product_boosts'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%plan%' loop
    execute format('alter table public.product_boosts drop constraint %I', r.conname);
  end loop;
  alter table public.product_boosts add constraint product_boosts_plan_check check (plan in ('3d', '7d', '14d', '30d'));
end $b$;

create or replace function public.confirm_boost_payment(p_trans_id text, p_amount bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b       public.product_boosts%rowtype;
  v_start timestamptz;
  v_days  integer;
begin
  select * into b from public.product_boosts where fapshi_trans_id = p_trans_id for update;
  if not found then raise exception 'boost_inconnu'; end if;
  if b.status in ('paid', 'review') then return jsonb_build_object('status', 'already', 'boost_id', b.id); end if;

  if p_amount is distinct from b.amount then
    update public.product_boosts set status = 'review', fapshi_status = 'SUCCESSFUL', paid_at = now() where id = b.id;
    return jsonb_build_object('status', 'review', 'boost_id', b.id);
  end if;

  v_days := regexp_replace(b.plan, '[^0-9]', '', 'g')::integer;   -- '3d' -> 3, '7d' -> 7, '14d' -> 14, '30d' -> 30
  -- Si le produit est déjà boosté, le nouveau boost commence à la fin du précédent.
  select greatest(now(), coalesce(max(ends_at), now())) into v_start
    from public.product_boosts where product_id = b.product_id and status = 'paid' and ends_at > now();

  update public.product_boosts
     set status = 'paid', fapshi_status = 'SUCCESSFUL', paid_at = now(),
         starts_at = v_start, ends_at = v_start + make_interval(days => v_days)
   where id = b.id;
  return jsonb_build_object('status', 'paid', 'boost_id', b.id);
end $$;

-- 28.7  Bannières sponsorisées et « produit de la semaine » (gérés par l'admin dans /admin/pub)
create table if not exists public.site_banners (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null default 'banner' check (kind in ('banner', 'product')),
  title      text not null check (char_length(title) between 2 and 80),
  body       text check (body is null or char_length(body) <= 200),
  link_url   text check (link_url is null or link_url ~ '^https?://' or link_url ~ '^/[^/]'),
  image_url  text check (image_url is null or image_url ~ '^https://'),
  label      text not null default 'Sponsorisé' check (char_length(label) <= 20),
  product_id uuid references public.products(id) on delete set null,
  is_active  boolean not null default true,
  starts_at  timestamptz,
  ends_at    timestamptz,
  created_at timestamptz not null default now()
);
alter table public.site_banners enable row level security;
drop policy if exists site_banners_read on public.site_banners;
create policy site_banners_read on public.site_banners for select
  using ((is_active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())) or public.is_admin());
drop policy if exists site_banners_write on public.site_banners;
create policy site_banners_write on public.site_banners for all using (public.is_admin()) with check (public.is_admin());
revoke all on public.site_banners from anon, authenticated;
grant select on public.site_banners to anon, authenticated;
grant insert, update, delete on public.site_banners to authenticated;

-- 28.8  Tableau de bord admin : revenus du site (commissions + boosts + abonnements Pro + frais de retrait)
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
    'withdrawal_fees', (select coalesce(sum(fee), 0) from public.withdrawals where status = 'paid')
  ) into v;
  return v;
end $$;


-- =====================================================================
-- 29. TARIFS MODIFIABLES DEPUIS L'ADMIN (Admin > Commissions) : taux Pro, prix Pro, frais de retrait
--     (Ce bloc suit le bloc 28 et est inclus dans supabase/mise-a-jour-revenus.sql.)
-- =====================================================================
alter table public.commission_settings add column if not exists pro_price integer not null default 3000 check (pro_price between 500 and 200000);
alter table public.commission_settings add column if not exists withdrawal_fee_percent numeric(4, 2) not null default 1.5 check (withdrawal_fee_percent between 0 and 10);
alter table public.commission_settings add column if not exists withdrawal_fee_min integer not null default 200 check (withdrawal_fee_min between 0 and 5000);

-- Valeurs recommandées (frais Fapshi = 3 % : à 3 % de commission on ne gagne rien) : normal 8 %, Pro 5 %.
-- On ne change que les valeurs encore aux anciens réglages par défaut (3 % et 1,5 %) : un taux choisi par l'admin n'est jamais écrasé.
alter table public.commission_settings alter column after_launch_percent set default 8;
alter table public.commission_settings alter column pro_percent set default 5;
do $m$
declare v_old numeric;
begin
  select after_launch_percent into v_old from public.commission_settings where id = 1;
  if v_old = 3 then
    update public.commission_settings
       set after_launch_percent = 8,
           platform_fee_percent = case when is_launch_mode then platform_fee_percent when platform_fee_percent = 3 then 8 else platform_fee_percent end,
           updated_at = now()
     where id = 1;
    insert into public.commission_history (old_percent, new_percent, old_active, new_active, changed_by) values (3, 8, true, true, null);
  end if;
end $m$;
update public.commission_settings set pro_percent = 5 where id = 1 and pro_percent = 1.5; -- (sur une base déjà mise à jour avec l’ancien 1,5 %)

-- Les tarifs sont publics (affichés aux vendeurs) : lecture autorisée, écriture réservée à l'admin (fonction ci-dessous)
grant select (pro_percent, pro_price, withdrawal_fee_percent, withdrawal_fee_min) on public.commission_settings to anon, authenticated;

create or replace function public.admin_set_revenue_settings(p_pro_percent numeric, p_pro_price integer, p_fee_percent numeric, p_fee_min integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_pro_percent is null or p_pro_percent < 0 or p_pro_percent > 10
     or p_pro_price is null or p_pro_price < 500 or p_pro_price > 200000
     or p_fee_percent is null or p_fee_percent < 0 or p_fee_percent > 10
     or p_fee_min is null or p_fee_min < 0 or p_fee_min > 5000 then
    raise exception 'valeur_invalide';
  end if;
  update public.commission_settings
     set pro_percent = round(p_pro_percent, 2), pro_price = p_pro_price,
         withdrawal_fee_percent = round(p_fee_percent, 2), withdrawal_fee_min = p_fee_min,
         updated_at = now(), updated_by_admin_id = auth.uid()
   where id = 1;
end $$;
revoke all on function public.admin_set_revenue_settings(numeric, integer, numeric, integer) from public, anon;
grant execute on function public.admin_set_revenue_settings(numeric, integer, numeric, integer) to authenticated;

-- Frais de retrait : lit maintenant les réglages
create or replace function public.request_withdrawal(p_amount bigint, p_method text, p_phone text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_id     uuid;
  v_deduct bigint := 0;
  v_base   bigint;
  v_fee    bigint := 0;
  v_fp     numeric := 1.5;
  v_fm     bigint  := 200;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if p_method is null or p_method not in ('mtn_momo', 'orange_money', 'wave', 'moov_money', 'mpesa', 'bank_transfer', 'crypto_usdt', 'crypto_btc', 'paypal') then raise exception 'methode_invalide'; end if;
  if public.is_blocked(v_uid) then raise exception 'compte_bloque'; end if;
  if p_amount is null or p_amount < 1000 then raise exception 'montant_minimum'; end if;   -- minimum de retrait : 1 000 FCFA
  -- Destination selon le moyen choisi
  if p_method in ('mtn_momo', 'orange_money', 'wave', 'moov_money', 'mpesa') then
    if p_phone is null or p_phone !~ '^\+?[0-9]{8,15}$' then raise exception 'telephone_invalide'; end if;
  elsif p_method = 'paypal' then
    if p_phone is null or p_phone !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(p_phone) > 254 then raise exception 'destination_invalide'; end if;
  elsif p_method in ('crypto_usdt', 'crypto_btc') then
    if p_phone is null or p_phone !~ '^[A-Za-z0-9:_-]{20,120}$' then raise exception 'destination_invalide'; end if;
  else  -- bank_transfer : IBAN / numéro de compte + nom de la banque (texte libre court)
    if p_phone is null or length(btrim(p_phone)) < 8 or length(p_phone) > 120 then raise exception 'destination_invalide'; end if;
  end if;

  perform public.release_due_funds(v_uid);

  update public.wallets
     set balance_available = balance_available - p_amount, updated_at = now()
   where user_id = v_uid and balance_available >= p_amount;
  if not found then raise exception 'solde_insuffisant'; end if;

  -- Commission due sur les ventes payées en cash à la livraison : prélevée sur CE retrait.
  select least(commission_due, p_amount) into v_deduct from public.wallets where user_id = v_uid;
  update public.wallets set commission_due = commission_due - v_deduct where user_id = v_uid;

  -- Frais de retrait : pourcentage et minimum REGLABLES par l'admin (commission_settings), sur le montant restant après la commission cash. Compte exempté : aucun frais.
  select withdrawal_fee_percent, withdrawal_fee_min into v_fp, v_fm from public.commission_settings where id = 1;
  -- Le frais n'est PAS retiré du solde : il est simplement déduit du paiement envoyé (à payer = demandé - commission cash - frais).
  v_base := p_amount - v_deduct;
  if not coalesce((select commission_exempt from public.profiles where id = v_uid), false) then
    v_fee := least(v_base, greatest(coalesce(v_fm, 200), ceil(v_base * coalesce(v_fp, 1.5) / 100.0)::bigint));
  end if;

  insert into public.withdrawals (user_id, amount, method, phone_number, commission_deducted, fee)
  values (v_uid, p_amount, p_method, p_phone, v_deduct, v_fee)
  returning id into v_id;
  return v_id;
end $$;

notify pgrst, 'reload schema';

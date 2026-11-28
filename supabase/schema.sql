-- =====================================================================
-- KDDF MARKET — Schéma Supabase COMPLET (pour une base vide)
--
-- COMMENT L'UTILISER :
--   Supabase > SQL Editor > New query > collez TOUT ce fichier > Run.
--
-- RÈGLES :
--   * Tous les montants sont des ENTIERS en FCFA (XAF). Aucun nombre à virgule.
--   * Le script peut être relancé sans erreur et ne supprime aucune donnée.
--   * Le calcul de la répartition (plateforme / affilié / vendeur) est fait ICI,
--     côté base de données, dans la fonction confirm_fapshi_payment().
--     Il ne peut donc jamais être falsifié depuis le navigateur.
--
-- RÉPARTITION (appliquée sur le prix des articles, hors frais de livraison) :
--   AVEC affilié : plateforme 5 %  | affilié = % choisi par produit | vendeur = le reste
--   SANS affilié : plateforme 10 % | affilié 0                      | vendeur = le reste
--   Les frais de livraison reviennent entièrement au vendeur.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 00. DROITS DE BASE (indispensable sur les projets Supabase récents)
-- Certains projets n'accordent PLUS automatiquement les droits sur les nouvelles tables aux rôles de l'API
-- (anon, authenticated, service_role) : le site reçoit alors « permission denied for table ... ».
-- On remet ici le comportement classique de Supabase ; les sections de sécurité plus bas
-- (REVOKE, politiques RLS, droits par colonne) retirent ensuite ce qui ne doit pas être ouvert.
-- Ce bloc est rejouable sans risque : le script entier restaure ensuite les restrictions.
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 0. FONCTIONS UTILITAIRES
-- ---------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Code d'affiliation unique de 8 caractères (ex : 3FA9C21B)
create or replace function public.generate_referral_code()
returns text language plpgsql as $$
declare
  v_code text;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
    exit when not exists (select 1 from public.profiles where referral_code = v_code);
  end loop;
  return v_code;
end $$;


-- ---------------------------------------------------------------------
-- 1. PROFILES  (vendeurs, acheteurs, affiliés, admin : tout le monde)
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text,
  store_name    text,
  store_slug    text unique,
  avatar_url    text,
  phone         text,
  country       text not null default 'CM',
  role          text not null default 'user' check (role in ('user', 'admin')),
  referral_code text not null unique default public.generate_referral_code(),
  created_at    timestamptz not null default now()
);

-- Nouvelles colonnes : contact vendeur (le numéro WhatsApp n'est JAMAIS public) et personnalisation de la boutique.
-- (phone = numéro d'appel)
alter table public.profiles add column if not exists whatsapp            text;
alter table public.profiles add column if not exists city                text;
alter table public.profiles add column if not exists shop_logo_url       text;
alter table public.profiles add column if not exists shop_banner_url     text;
alter table public.profiles add column if not exists shop_description    text;
alter table public.profiles add column if not exists shop_color          text not null default 'violet';
-- Couleur libre choisie par le vendeur (n'importe quelle couleur, au format #RRGGBB). Prioritaire sur shop_color.
alter table public.profiles add column if not exists shop_color_custom   text;
alter table public.profiles add column if not exists shop_theme          text not null default 'dark';
alter table public.profiles add column if not exists shop_sort           text not null default 'newest';
alter table public.profiles add column if not exists shop_show_whatsapp  boolean not null default true;

alter table public.profiles add column if not exists is_verified            boolean not null default false;  -- badge "Vendeur Vérifié" (donné par l'admin après vérification de la CNI)
alter table public.profiles add column if not exists is_blocked             boolean not null default false;  -- vendeur bloqué par l'admin
alter table public.profiles add column if not exists delivery_douala_price  bigint  not null default 1000;   -- prix de livraison à domicile à Douala (défaut de ses produits)
alter table public.profiles add column if not exists delivery_shipping_price bigint not null default 2500;   -- prix d'envoi par bus / expédition

create or replace function public.is_blocked(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_blocked from public.profiles where id = p_user), false);
$$;

do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_delivery_prices_chk') then
    alter table public.profiles add constraint profiles_delivery_prices_chk
      check (delivery_douala_price between 0 and 9999999 and delivery_shipping_price between 0 and 9999999);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_shop_color_chk') then
    alter table public.profiles add constraint profiles_shop_color_chk check (shop_color in ('noir', 'bleu', 'rouge', 'vert', 'orange', 'violet'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_shop_color_custom_chk') then
    alter table public.profiles add constraint profiles_shop_color_custom_chk check (shop_color_custom is null or shop_color_custom ~ '^#[0-9A-Fa-f]{6}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_shop_theme_chk') then
    alter table public.profiles add constraint profiles_shop_theme_chk check (shop_theme in ('light', 'dark'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_shop_sort_chk') then
    alter table public.profiles add constraint profiles_shop_sort_chk check (shop_sort in ('newest', 'oldest', 'price_asc', 'price_desc', 'name'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_whatsapp_chk') then
    alter table public.profiles add constraint profiles_whatsapp_chk check (whatsapp is null or whatsapp ~ '^[0-9]{8,15}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_shop_description_chk') then
    alter table public.profiles add constraint profiles_shop_description_chk check (shop_description is null or char_length(shop_description) <= 500);
  end if;
end $c$;

-- Vrai si l'utilisateur connecté est administrateur (vous).
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;


-- ---------------------------------------------------------------------
-- 2. WALLETS  (soldes internes : en attente / disponible)
-- ---------------------------------------------------------------------

create table if not exists public.wallets (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null unique references public.profiles(id) on delete cascade,
  balance_pending   bigint not null default 0 check (balance_pending >= 0),
  balance_available bigint not null default 0 check (balance_available >= 0),
  total_earned      bigint not null default 0,   -- total gagné depuis le début (en attente + disponible + retiré)
  total_withdrawn   bigint not null default 0,   -- total réellement retiré
  updated_at        timestamptz not null default now()
);
-- Commission de KDDF Market due sur les ventes payées en cash à la livraison : elle est prélevée sur le prochain retrait.
alter table public.wallets add column if not exists commission_due bigint not null default 0 check (commission_due >= 0);


-- ---------------------------------------------------------------------
-- 3. NOUVEL UTILISATEUR  => profil + portefeuille créés automatiquement
-- ---------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_local text := split_part(coalesce(new.email, 'user'), '@', 1);
begin
  insert into public.profiles (id, full_name, store_slug)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), v_local),
    lower(regexp_replace(v_local, '[^a-zA-Z0-9]', '', 'g')) || substr(new.id::text, 1, 4)
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Utilisateurs déjà inscrits avant ce script : on leur crée profil + portefeuille.
insert into public.profiles (id, full_name, store_slug)
select u.id,
       coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), split_part(coalesce(u.email, 'user'), '@', 1)),
       lower(regexp_replace(split_part(coalesce(u.email, 'user'), '@', 1), '[^a-zA-Z0-9]', '', 'g')) || substr(u.id::text, 1, 4)
from auth.users u
on conflict (id) do nothing;

insert into public.wallets (user_id)
select p.id from public.profiles p
on conflict (user_id) do nothing;


-- ---------------------------------------------------------------------
-- 4. PRODUCTS  (produits digitaux ET physiques)
-- ---------------------------------------------------------------------

-- Vérifie le JSON des options de livraison d'un produit physique.
-- Format attendu :
-- {"pickup_douala":{"enabled":true,"price":0},
--  "delivery_douala":{"enabled":true,"price":1000},
--  "shipping_cameroon":{"enabled":false,"price":0}}
create or replace function public.valid_delivery_options(o jsonb)
returns boolean language plpgsql immutable as $$
declare
  k text;
  v_any boolean := false;
begin
  if o is null or jsonb_typeof(o) <> 'object' then return false; end if;
  for k in select jsonb_object_keys(o) loop
    if k not in ('pickup_douala', 'delivery_douala', 'shipping_cameroon') then return false; end if;
    if jsonb_typeof(o -> k) <> 'object' then return false; end if;
    if jsonb_typeof(o -> k -> 'enabled') <> 'boolean' then return false; end if;
    if jsonb_typeof(o -> k -> 'price') <> 'number' then return false; end if;
    if (o -> k ->> 'price') !~ '^[0-9]{1,7}$' then return false; end if;           -- entier FCFA, 0 à 9 999 999
    if k = 'pickup_douala' and (o -> k ->> 'price')::int <> 0 then return false; end if;  -- retrait = gratuit
    if (o -> k ->> 'enabled')::boolean then v_any := true; end if;
  end loop;
  return v_any;                                                                       -- au moins une option active
end $$;

create table if not exists public.products (
  id                uuid primary key default gen_random_uuid(),
  seller_id         uuid not null references public.profiles(id) on delete cascade,
  product_type      text not null default 'digital' check (product_type in ('digital', 'physical')),
  -- sous-type d'un produit digital (obligatoire si digital, vide si physique)
  digital_kind      text check (digital_kind in ('file', 'course', 'license', 'bundle', 'coaching', 'service')),
  title             text not null check (char_length(title) between 2 and 150),
  slug              text not null,
  description       text,
  cover_url         text,
  price             bigint not null check (price >= 100),          -- FCFA entier (minimum Fapshi : 100)
  is_published      boolean not null default false,
  -- affiliation
  affiliate_enabled boolean not null default true,
  affiliate_percent integer not null default 30 check (affiliate_percent in (10, 20, 30, 40, 50)),
  -- spécifique digital (coaching / service)
  booking_url       text,
  duration_minutes  integer check (duration_minutes is null or duration_minutes > 0),
  delivery_notes    text,
  -- spécifique physique
  stock             integer check (stock is null or stock >= 0),
  images            text[] not null default '{}',
  weight            text,
  variant           text,
  delivery_options  jsonb,
  whatsapp_seller   text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (seller_id, slug),
  constraint digital_needs_kind check (product_type <> 'digital' or digital_kind is not null),
  constraint digital_has_no_stock check (product_type <> 'digital' or stock is null),
  constraint physical_needs_fields check (
    product_type <> 'physical' or (
      stock is not null
      and cardinality(images) between 1 and 5
      and whatsapp_seller is not null
      and public.valid_delivery_options(delivery_options)
    )
  )
);

-- Recherche et confiance
alter table public.products add column if not exists category          text;
alter table public.products add column if not exists city              text;     -- ville du vendeur (copiée de son profil par un trigger)
alter table public.products add column if not exists rating_avg        numeric(3, 2) not null default 0;
alter table public.products add column if not exists rating_count      integer not null default 0;
-- Modération : les produits EXISTANTS sont approuvés ; les NOUVEAUX produits attendent la validation de l'admin.
alter table public.products add column if not exists moderation_status text not null default 'approved'
  check (moderation_status in ('pending', 'approved', 'rejected'));
alter table public.products add column if not exists moderation_note   text;
alter table public.products alter column moderation_status set default 'pending';
create index if not exists products_search_idx on public.products (is_published, moderation_status, created_at desc);
create index if not exists products_category_idx on public.products (category);
create index if not exists products_seller_idx on public.products (seller_id);
create index if not exists products_published_idx on public.products (is_published, created_at desc);

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products
  for each row execute function public.set_updated_at();

-- Fichiers livrables d'un produit digital (PDF, ePub, vidéos...) — bucket privé "deliverables"
create table if not exists public.product_files (
  id           uuid primary key default gen_random_uuid(),
  product_id   uuid not null references public.products(id) on delete cascade,
  storage_path text not null,
  file_name    text not null,
  mime_type    text,
  size_bytes   bigint,
  position     integer not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists product_files_product_idx on public.product_files (product_id);

-- Offres groupées (bundles)
create table if not exists public.bundle_items (
  bundle_id  uuid not null references public.products(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  primary key (bundle_id, product_id),
  check (bundle_id <> product_id)
);


-- ---------------------------------------------------------------------
-- 5. ORDERS  (commandes)
-- ---------------------------------------------------------------------

create table if not exists public.orders (
  id                 uuid primary key default gen_random_uuid(),
  product_id         uuid not null references public.products(id) on delete restrict,
  seller_id          uuid not null references public.profiles(id) on delete restrict,
  buyer_id           uuid references public.profiles(id) on delete set null,   -- vide = achat physique sans compte (voir guest_id) ; le digital exige un compte
  buyer_email        text not null,
  buyer_name         text,
  affiliate_id       uuid references public.profiles(id) on delete set null,   -- affilié lié à la commande
  affiliate_percent  integer,                                                  -- % figé au moment de la commande
  quantity           integer not null default 1 check (quantity between 1 and 50),
  unit_price         bigint not null check (unit_price >= 100),
  delivery_method    text check (delivery_method in ('pickup_douala', 'delivery_douala', 'shipping_cameroon')),
  delivery_price     bigint not null default 0 check (delivery_price >= 0),
  total_price        bigint not null check (total_price >= 100),
  delivery_address   text,
  phone              text,
  -- Suivi de la commande : pending=En attente, confirmed=Confirmée, shipped=Expédiée,
  -- ready_for_pickup=Prête pour retrait, delivered=Livrée, completed=Terminée (fonds libérés), cancelled=Annulée
  -- Cycle strict, sans saut : En attente -> Payé -> Livré -> Terminé (voir le trigger orders_status_guard, section 28).
  status             text not null default 'pending'
                       check (status in ('pending', 'confirmed', 'shipped', 'ready_for_pickup', 'delivered', 'completed', 'cancelled')),
  payment_status     text not null default 'pending'
                       check (payment_status in ('pending', 'paid', 'failed', 'expired', 'refunded')),
  download_token     uuid not null default gen_random_uuid() unique,
  buyer_confirmed_at timestamptz,
  delivered_at       timestamptz,
  disputed           boolean not null default false,
  dispute_reason     text,
  disputed_at        timestamptz,
  created_at         timestamptz not null default now(),
  paid_at            timestamptz,
  constraint total_is_consistent check (total_price = unit_price * quantity + delivery_price),
  constraint delivery_needs_contact check (
    delivery_method is null
    or (phone is not null and (delivery_method = 'pickup_douala' or delivery_address is not null))
  )
);
create index if not exists orders_seller_idx on public.orders (seller_id, payment_status, created_at desc);
create index if not exists orders_buyer_idx on public.orders (buyer_id, created_at desc);
create index if not exists orders_buyer_email_idx on public.orders (lower(buyer_email));
create index if not exists orders_product_idx on public.orders (product_id);
-- online = payé en ligne via Fapshi (Orange Money / MTN MoMo) ; cod = paiement cash à la livraison (produits physiques seulement)
alter table public.orders add column if not exists payment_method text not null default 'online' check (payment_method in ('online', 'cod'));

-- Clés de licence (produits digitaux de type "license")
create table if not exists public.license_keys (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  key         text not null,
  order_id    uuid references public.orders(id) on delete set null,
  assigned_at timestamptz,
  created_at  timestamptz not null default now(),
  unique (product_id, key)
);
create index if not exists license_keys_free_idx on public.license_keys (product_id) where order_id is null;


-- ---------------------------------------------------------------------
-- 6. TRANSACTIONS  (paiement Fapshi + répartition de chaque vente)
-- ---------------------------------------------------------------------

create table if not exists public.transactions (
  id                    uuid primary key default gen_random_uuid(),
  order_id              uuid not null unique references public.orders(id) on delete cascade,
  product_id            uuid not null references public.products(id) on delete restrict,
  buyer_id              uuid references public.profiles(id) on delete set null,
  seller_id             uuid not null references public.profiles(id) on delete restrict,
  affiliate_id          uuid references public.profiles(id) on delete set null,   -- rempli à la confirmation, seulement s'il y a un affilié
  -- Répartition (rempli quand le paiement est confirmé). Total = plateforme + affilié + vendeur.
  total_amount          bigint not null check (total_amount >= 100),
  goods_amount          bigint,                 -- base de calcul des commissions (articles, sans livraison)
  platform_fee          bigint,
  platform_fee_percent  integer,
  affiliate_fee         bigint,
  affiliate_fee_percent integer,
  seller_amount         bigint,
  -- pending=en attente de paiement, paid=payée, failed=échec, expired=lien expiré,
  -- refunded=remboursée, review=payée mais à traiter à la main (stock épuisé, montant différent...)
  status                text not null default 'pending'
                          check (status in ('pending', 'paid', 'failed', 'expired', 'refunded', 'review')),
  review_reason         text,
  -- Fapshi
  fapshi_trans_id       text unique,
  fapshi_link           text,
  fapshi_status         text,                   -- CREATED / PENDING / SUCCESSFUL / FAILED / EXPIRED
  fapshi_medium         text,                   -- mobile money / orange money
  fapshi_revenue        bigint,                 -- montant reçu par vous après les frais Fapshi
  last_checked_at       timestamptz,
  -- Libération des fonds (en attente -> disponible)
  release_at            timestamptz,
  released_at           timestamptz,
  created_at            timestamptz not null default now(),
  paid_at               timestamptz,
  constraint split_is_sane check (
    platform_fee is null
    or (platform_fee >= 0 and affiliate_fee >= 0 and seller_amount >= 0)
  ),
  -- Garantie finale : une transaction payée doit TOUJOURS se répartir exactement sur le total.
  constraint paid_split_is_exact check (
    status <> 'paid'
    or (
      platform_fee is not null and affiliate_fee is not null and seller_amount is not null
      and total_amount = platform_fee + affiliate_fee + seller_amount
    )
  )
);
create index if not exists transactions_seller_idx on public.transactions (seller_id, created_at desc);
create index if not exists transactions_affiliate_idx on public.transactions (affiliate_id) where affiliate_id is not null;
create index if not exists transactions_status_idx on public.transactions (status, created_at);
create index if not exists transactions_release_idx on public.transactions (release_at) where status = 'paid' and released_at is null;

-- Journal brut des réponses Fapshi (audit). Réservé à l'admin : contient des données clients.
create table if not exists public.payment_events (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  source         text not null,                 -- webhook / verification
  payload        jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists payment_events_tx_idx on public.payment_events (transaction_id);


-- ---------------------------------------------------------------------
-- 7. AFFILIATION  (un lien unique par utilisateur : ?ref=CODE)
-- ---------------------------------------------------------------------

create table if not exists public.affiliate_links (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  code       text not null,                     -- = profiles.referral_code de l'affilié
  clicks     integer not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, product_id)
);
create index if not exists affiliate_links_product_idx on public.affiliate_links (product_id);


-- ---------------------------------------------------------------------
-- 8. WITHDRAWALS  (demandes de retrait des vendeurs et affiliés)
-- ---------------------------------------------------------------------

create table if not exists public.withdrawals (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete restrict,
  amount       bigint not null check (amount > 0),
  method       text not null check (method in ('mtn_momo', 'orange_money', 'fapshi')),
  phone_number text not null,
  status       text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  note         text,
  created_at   timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references public.profiles(id) on delete set null
);
-- Retraits universels : Mobile Money (MTN, Orange, Wave, Moov, M-Pesa), virement bancaire, crypto (USDT/BTC), PayPal.
-- La colonne phone_number contient la « destination » : numéro, IBAN/compte, adresse crypto ou email PayPal.
alter table public.withdrawals drop constraint if exists withdrawals_method_check;
alter table public.withdrawals add constraint withdrawals_method_check
  check (method in ('mtn_momo', 'orange_money', 'fapshi', 'wave', 'moov_money', 'mpesa', 'bank_transfer', 'crypto_usdt', 'crypto_btc', 'paypal'));
alter table public.withdrawals add column if not exists commission_deducted bigint not null default 0 check (commission_deducted >= 0);
create index if not exists withdrawals_user_idx on public.withdrawals (user_id, created_at desc);
create index if not exists withdrawals_status_idx on public.withdrawals (status, created_at);


-- ---------------------------------------------------------------------
-- 9. STATISTIQUES (visites des pages produit, pour le taux de conversion)
-- ---------------------------------------------------------------------

create table if not exists public.product_views (
  id         bigint generated always as identity primary key,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists product_views_idx on public.product_views (product_id, created_at);


-- =====================================================================
-- 10. SÉCURITÉ : ROW LEVEL SECURITY (RLS)
--     Règle générale : le navigateur ne peut JAMAIS écrire dans orders,
--     transactions, wallets, withdrawals. Tout passe par les fonctions
--     sécurisées plus bas ou par le serveur (clé service_role).
-- =====================================================================

alter table public.profiles        enable row level security;
alter table public.wallets         enable row level security;
alter table public.products        enable row level security;
alter table public.product_files   enable row level security;
alter table public.bundle_items    enable row level security;
alter table public.orders          enable row level security;
alter table public.license_keys    enable row level security;
alter table public.transactions    enable row level security;
alter table public.payment_events  enable row level security;
alter table public.affiliate_links enable row level security;
alter table public.withdrawals     enable row level security;
alter table public.product_views   enable row level security;

-- Profils : chacun voit le sien (téléphone, code...). L'admin voit tout.
-- Le public voit seulement la vue "public_profiles" (nom de boutique, sans téléphone).
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or public.is_admin());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- Un utilisateur ne peut modifier QUE ces colonnes (impossible de se donner le rôle admin).
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (full_name, store_name, store_slug, avatar_url, phone, country, whatsapp, city,
              shop_logo_url, shop_banner_url, shop_description, shop_color, shop_color_custom, shop_theme, shop_sort, shop_show_whatsapp,
              delivery_douala_price, delivery_shipping_price)
  on public.profiles to authenticated;

create or replace view public.public_profiles as
  select id, full_name, store_name, store_slug, avatar_url,
         shop_logo_url, shop_banner_url, shop_description, shop_color, shop_theme, shop_sort, shop_show_whatsapp, city,
         is_verified, shop_color_custom
    from public.profiles
   where not is_blocked;
grant select on public.public_profiles to anon, authenticated;

-- Portefeuilles : lecture de son propre solde uniquement.
drop policy if exists wallets_select on public.wallets;
create policy wallets_select on public.wallets for select
  using (user_id = auth.uid() or public.is_admin());

-- Produits
drop policy if exists products_select on public.products;
create policy products_select on public.products for select
  using ((is_published and moderation_status = 'approved') or seller_id = auth.uid() or public.is_admin());
drop policy if exists products_insert on public.products;
create policy products_insert on public.products for insert
  with check (seller_id = auth.uid() and not public.is_blocked(auth.uid()));
drop policy if exists products_update on public.products;
create policy products_update on public.products for update
  using (seller_id = auth.uid()) with check (seller_id = auth.uid() and not public.is_blocked(auth.uid()));
drop policy if exists products_delete on public.products;
create policy products_delete on public.products for delete
  using (seller_id = auth.uid());

-- Fichiers livrables et clés : visibles uniquement par le vendeur du produit.
-- (L'acheteur y accède via l'API serveur, après vérification du paiement.)
drop policy if exists product_files_owner on public.product_files;
create policy product_files_owner on public.product_files for all
  using (exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid()))
  with check (exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid()));

drop policy if exists license_keys_owner on public.license_keys;
create policy license_keys_owner on public.license_keys for all
  using (exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid()))
  with check (exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid()));

drop policy if exists bundle_items_select on public.bundle_items;
create policy bundle_items_select on public.bundle_items for select using (true);
drop policy if exists bundle_items_owner on public.bundle_items;
create policy bundle_items_owner on public.bundle_items for all
  using (exists (select 1 from public.products p where p.id = bundle_id and p.seller_id = auth.uid()))
  with check (
    exists (select 1 from public.products p where p.id = bundle_id and p.seller_id = auth.uid())
    and exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid())
  );

-- Commandes : l'acheteur voit les siennes ; le vendeur voit les commandes PAYÉES qui le concernent.
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders for select
  using (
    buyer_id = auth.uid()
    or (seller_id = auth.uid() and (payment_status = 'paid' or (payment_method = 'cod' and status <> 'cancelled')))
    or public.is_admin()
  );

-- Transactions : le vendeur voit les siennes, l'admin voit tout.
-- L'affilié passe par la vue "affiliate_sales" (il ne voit que SA commission).
drop policy if exists transactions_select on public.transactions;
create policy transactions_select on public.transactions for select
  using ((seller_id = auth.uid() and status in ('paid', 'refunded', 'review')) or public.is_admin());

drop policy if exists payment_events_select on public.payment_events;
create policy payment_events_select on public.payment_events for select
  using (public.is_admin());

-- Liens d'affiliation : l'affilié voit les siens ; le vendeur voit ceux de ses produits.
drop policy if exists affiliate_links_select on public.affiliate_links;
create policy affiliate_links_select on public.affiliate_links for select
  using (
    user_id = auth.uid()
    or exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid())
    or public.is_admin()
  );

-- Retraits : chacun voit les siens ; l'admin voit tout.
drop policy if exists withdrawals_select on public.withdrawals;
create policy withdrawals_select on public.withdrawals for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists product_views_select on public.product_views;
create policy product_views_select on public.product_views for select
  using (
    exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid())
    or public.is_admin()
  );

-- Défense en plus des règles RLS : aucune écriture directe depuis le navigateur.
revoke insert, update, delete, truncate on
  public.wallets, public.orders, public.transactions, public.payment_events,
  public.affiliate_links, public.withdrawals, public.product_views
  from anon, authenticated;

-- Les visiteurs non connectés ne doivent voir aucune de ces tables.
revoke all on
  public.wallets, public.orders, public.transactions, public.payment_events,
  public.affiliate_links, public.withdrawals, public.product_views,
  public.product_files, public.license_keys
  from anon;


-- =====================================================================
-- 11. RÉPARTITION DES REVENUS (le cœur du système)
-- =====================================================================

-- Le calcul (plateforme + affilié + vendeur) est défini dans la section 24 : public.compute_split_for().
--   * ENTIERS FCFA uniquement (division entière = arrondi inférieur, le vendeur reçoit le reste) ;
--   * plateforme : 0 % pendant 30 jours de lancement, puis 3 % (réglable 3/4/5 % dans /admin/commissions) ;
--   * affilié : 1 % à 50 % choisi sur le produit (20 % par défaut).
-- L'ancien calcul 5 % / 8 % / 10 % et l'ancienne fonction compute_split() sont SUPPRIMÉS.
drop function if exists public.compute_split(bigint, boolean, integer);
drop function if exists public.compute_split_for(bigint, boolean, integer, boolean);


-- =====================================================================
-- 12. FONCTIONS APPELÉES PAR LE SERVEUR (service_role uniquement)
-- =====================================================================

-- Crée la commande + la transaction (en attente) pour un achat.
-- Le prix, le stock et les frais de livraison sont relus ICI dans la base :
-- on ne fait jamais confiance au navigateur.
drop function if exists public.create_checkout_order(uuid, uuid, text, text, integer, text, text, text, text);
drop function if exists public.create_checkout_order(uuid, uuid, text, text, integer, text, text, text, text, text);
-- V3.1 GUEST CHECKOUT :
--   * produit PHYSIQUE : achat possible SANS compte (nom + téléphone + ville + quartier) ; un compte invité est créé en arrière-plan
--     (table guest_accounts, liée au numéro) et un code KDDF-XXXX est généré (transactions.order_code) ;
--   * produit DIGITAL : compte OBLIGATOIRE (p_buyer_id requis) ;
--   * anti-fraude téléphone : plus de 5 commandes en 1 h avec le même numéro => commande bloquée + trace dans fraud_logs
--     (si l'anti-fraude plante : la commande passe, "allowed: true").
create or replace function public.create_checkout_order(
  p_product_id      uuid,
  p_buyer_id        uuid,
  p_email           text,
  p_name            text,
  p_quantity        integer,
  p_delivery_method text,
  p_address         text,
  p_phone           text,
  p_ref_code        text,
  p_payment_method  text default 'online',
  p_city            text default null,
  p_district        text default null,
  p_ip              text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  p            public.products%rowtype;
  v_qty        integer := coalesce(p_quantity, 1);
  v_delivery   bigint := 0;
  v_aff_id     uuid;
  v_aff_pct    integer;
  v_total      bigint;
  v_order_id   uuid;
  v_token      uuid;
  v_tx_id      uuid;
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_name       text := nullif(btrim(coalesce(p_name, '')), '');
  v_address    text := nullif(btrim(coalesce(p_address, '')), '');
  v_city       text := nullif(btrim(coalesce(p_city, '')), '');
  v_district   text := nullif(btrim(coalesce(p_district, '')), '');
  v_phone_key  text;
  v_guest      uuid;
  v_code       text;
  v_ip         text := nullif(left(btrim(coalesce(p_ip, '')), 64), '');
  v_n          integer;
  v_try        integer := 0;
begin
  select * into p from public.products where id = p_product_id and is_published and moderation_status = 'approved';
  if not found then raise exception 'produit_introuvable'; end if;
  if public.is_blocked(p.seller_id) then raise exception 'vendeur_bloque'; end if;

  p_payment_method := coalesce(p_payment_method, 'online');
  if p_payment_method not in ('online', 'cod') then raise exception 'paiement_invalide'; end if;
  -- Le paiement à la livraison est INTERDIT pour les produits digitaux (livrés tout de suite).
  if p_payment_method = 'cod' and p.product_type <> 'physical' then raise exception 'cod_interdit_digital'; end if;

  if p.product_type = 'digital' then
    -- DIGITAL : compte obligatoire pour recevoir le fichier.
    if p_buyer_id is null then raise exception 'compte_requis_digital'; end if;
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'email_invalide'; end if;
    v_qty := 1;
    p_delivery_method := null;
    v_address := null;
    p_phone := null;
    v_city := null;
    v_district := null;
  else
    -- PHYSIQUE : l'email n'est pas obligatoire. Sans email, on utilise une adresse technique (jamais utilisée pour écrire au client).
    if v_email = '' then
      v_email := 'invite-' || coalesce(public.fraud_phone_key(p_phone), 'inconnu') || '@example.com';
    elsif v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      raise exception 'email_invalide';
    end if;
    if v_qty < 1 or v_qty > 50 then raise exception 'quantite_invalide'; end if;
    if p.stock is null or p.stock < v_qty then raise exception 'stock_insuffisant'; end if;
    if p_delivery_method is null
       or coalesce((p.delivery_options -> p_delivery_method ->> 'enabled')::boolean, false) is not true then
      raise exception 'livraison_invalide';
    end if;
    v_delivery := (p.delivery_options -> p_delivery_method ->> 'price')::bigint;
    if p_phone is null or char_length(trim(p_phone)) < 8 then raise exception 'telephone_invalide'; end if;
    v_phone_key := public.fraud_phone_key(p_phone);
    if v_phone_key is null then raise exception 'telephone_invalide'; end if;
    -- Achat sans compte : nom complet, ville et quartier obligatoires.
    if p_buyer_id is null then
      if v_name is null or char_length(v_name) < 2 then raise exception 'nom_invalide'; end if;
      if v_city is null or char_length(v_city) < 2 then raise exception 'ville_invalide'; end if;
      if v_district is null or char_length(v_district) < 2 then raise exception 'quartier_invalide'; end if;
    end if;
    -- Adresse de livraison = « Quartier, Ville » (+ repère éventuel)
    if v_city is not null and v_district is not null then
      v_address := v_district || ', ' || v_city || case when v_address is not null then ' (' || v_address || ')' else '' end;
    end if;
    if p_delivery_method <> 'pickup_douala' and char_length(coalesce(v_address, '')) < 5 then
      raise exception 'adresse_invalide';
    end if;

    -- ANTI-FRAUDE (téléphone) : plus de 5 commandes en 1 h avec le même numéro => bloqué.
    -- Si l'anti-fraude plante, la commande passe (allowed: true).
    begin
      if public.fraud_active() then
        select count(*) into v_n from public.orders
         where public.fraud_phone_key(phone) = v_phone_key and created_at > now() - interval '1 hour';
        if v_n >= 5 then
          insert into public.fraud_logs (user_id, seller_id, reason, risk_score, action, status, amount)
          values (p_buyer_id, p.seller_id,
                  format('Plus de 5 commandes en 1 h avec le même numéro (%s commandes, numéro se terminant par %s)', v_n + 1, right(v_phone_key, 3)),
                  100, 'blocked', 'closed', 0);
          return jsonb_build_object('blocked', true, 'reason', 'trop_de_commandes_numero');
        end if;
      end if;
    exception when others then
      raise warning 'anti-fraude (téléphone) ignoré : %', sqlerrm;
    end;
  end if;

  -- Affilié : code valide, produit ouvert à l'affiliation, ni le vendeur lui-même, ni l'acheteur lui-même.
  -- (pas d'affiliation sur un paiement à la livraison : la commission est prélevée sur le retrait du vendeur)
  -- Un acheteur SANS compte qui est arrivé par un lien d'affiliation (cookie 30 jours) donne la commission à l'affilié.
  if p_ref_code is not null and p.affiliate_enabled and p_payment_method = 'online' then
    select id into v_aff_id from public.profiles where referral_code = upper(trim(p_ref_code));
    if v_aff_id is not null and (v_aff_id = p.seller_id or v_aff_id is not distinct from p_buyer_id) then
      v_aff_id := null;
    end if;
    if v_aff_id is not null then v_aff_pct := p.affiliate_percent; end if;
  end if;

  v_total := p.price * v_qty + v_delivery;

  -- Compte invité en arrière-plan, lié au numéro (le client ne le voit jamais)
  if p_buyer_id is null and p.product_type = 'physical' then
    insert into public.guest_accounts (phone_key, phone, full_name, city, district, orders_count, last_order_at)
    values (v_phone_key, btrim(p_phone), v_name, v_city, v_district, 1, now())
    on conflict (phone_key) do update
      set full_name = coalesce(excluded.full_name, public.guest_accounts.full_name),
          city = coalesce(excluded.city, public.guest_accounts.city),
          district = coalesce(excluded.district, public.guest_accounts.district),
          phone = excluded.phone,
          orders_count = public.guest_accounts.orders_count + 1,
          last_order_at = now()
    returning id into v_guest;
  end if;

  insert into public.orders (
    product_id, seller_id, buyer_id, guest_id, buyer_email, buyer_name, affiliate_id, affiliate_percent,
    quantity, unit_price, delivery_method, delivery_price, total_price, delivery_address, phone, payment_method, client_ip
  ) values (
    p.id, p.seller_id, p_buyer_id, v_guest, v_email, v_name, v_aff_id, v_aff_pct,
    v_qty, p.price, p_delivery_method, v_delivery, v_total, v_address, nullif(btrim(coalesce(p_phone, '')), ''), p_payment_method, v_ip
  ) returning id, download_token into v_order_id, v_token;

  -- Cash à la livraison : le stock est réservé tout de suite (il n'y a pas de confirmation de paiement en ligne).
  if p_payment_method = 'cod' then
    update public.products set stock = stock - v_qty where id = p.id and stock >= v_qty;
    if not found then raise exception 'stock_insuffisant'; end if;
  end if;

  -- Code de suivi KDDF-XXXX pour chaque commande PHYSIQUE (unique : en cas de collision rarissime, on en tire un autre)
  loop
    v_try := v_try + 1;
    v_code := case when p.product_type = 'physical' then public.next_order_code() else null end;
    begin
      insert into public.transactions (order_id, product_id, buyer_id, seller_id, total_amount, order_code)
      values (v_order_id, p.id, p_buyer_id, p.seller_id, v_total, v_code)
      returning id into v_tx_id;
      exit;
    exception when unique_violation then
      if v_code is null or v_try >= 8 then raise; end if;
    end;
  end loop;

  return jsonb_build_object(
    'order_id', v_order_id,
    'transaction_id', v_tx_id,
    'download_token', v_token,
    'total', v_total,
    'title', p.title,
    'product_type', p.product_type,
    'payment_method', p_payment_method,
    'order_code', v_code,
    'guest', v_guest is not null
  );
end $$;


-- Confirme un paiement Fapshi (appelée par le webhook, APRÈS vérification auprès de Fapshi).
-- Tout se passe dans UNE seule transaction SQL : tout réussit ou rien ne change.
-- Idempotente : si Fapshi rejoue le webhook, rien n'est crédité deux fois.
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
  select * into s from public.compute_split_for(v_goods, v_has_aff, o.affiliate_percent, not v_digital);
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
         platform_fee_percent = s.platform_percent,
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


-- Échec ou expiration d'un paiement Fapshi.
-- FAILED : le client peut réessayer sur le même lien pendant 24 h -> la transaction reste utilisable.
create or replace function public.mark_fapshi_failed(p_trans_id text, p_fapshi_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.transactions%rowtype;
begin
  select * into t from public.transactions where fapshi_trans_id = p_trans_id for update;
  if not found or t.status not in ('pending', 'failed') then return; end if;

  if p_fapshi_status = 'EXPIRED' then
    update public.transactions set status = 'expired', fapshi_status = 'EXPIRED' where id = t.id;
    update public.orders set payment_status = 'expired' where id = t.order_id and payment_status <> 'paid';
  else
    update public.transactions set status = 'failed', fapshi_status = coalesce(p_fapshi_status, 'FAILED') where id = t.id;
    update public.orders set payment_status = 'failed' where id = t.order_id and payment_status <> 'paid';
  end if;
end $$;


-- Compte un clic sur un lien d'affiliation (ignore les clics du vendeur ou de l'affilié lui-même).
create or replace function public.record_affiliate_click(p_code text, p_product_id uuid, p_viewer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_aff uuid;
  v_seller uuid;
begin
  select id into v_aff from public.profiles where referral_code = upper(trim(p_code));
  select seller_id into v_seller from public.products where id = p_product_id and is_published and affiliate_enabled;
  if v_aff is null or v_seller is null or v_aff = v_seller or v_aff is not distinct from p_viewer then return; end if;

  insert into public.affiliate_links (user_id, product_id, code, clicks)
  values (v_aff, p_product_id, upper(trim(p_code)), 1)
  on conflict (user_id, product_id) do update set clicks = public.affiliate_links.clicks + 1;
end $$;


-- Libère les fonds arrivés à échéance : "en attente" -> "disponible".
--   digital  : 24 h après le paiement
--   physique : dès que le vendeur a marqué "Livrée" ET que l'acheteur a confirmé,
--              OU 7 jours après "Livrée" sans litige (digital : 24 h après le paiement).
--              (dès que l'acheteur clique "J'ai reçu mon produit", les fonds sont libérés immédiatement)
-- Appelée chaque jour par la tâche planifiée, et aussi à l'ouverture des portefeuilles.
create or replace function public.release_due_funds(p_user uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  t record;
  n integer := 0;
begin
  for t in
    select tr.id, tr.order_id, tr.seller_id, tr.seller_amount, tr.affiliate_id, tr.affiliate_fee
      from public.transactions tr
      join public.orders od on od.id = tr.order_id
     where tr.status = 'paid'
       and tr.released_at is null
       and tr.release_at is not null
       and tr.release_at <= now()
       and od.disputed = false
       and (p_user is null or tr.seller_id = p_user or tr.affiliate_id = p_user)
     order by tr.release_at
       for update of tr skip locked
  loop
    update public.wallets
       set balance_pending = balance_pending - t.seller_amount,
           balance_available = balance_available + t.seller_amount,
           updated_at = now()
     where user_id = t.seller_id;

    if t.affiliate_id is not null and t.affiliate_fee > 0 then
      update public.wallets
         set balance_pending = balance_pending - t.affiliate_fee,
             balance_available = balance_available + t.affiliate_fee,
             updated_at = now()
       where user_id = t.affiliate_id;
    end if;

    update public.transactions set released_at = now() where id = t.id;
    -- Livré -> Terminé : les fonds sont libérés, la vente est close
    update public.orders set status = 'completed' where id = t.order_id and status = 'delivered';
    n := n + 1;
  end loop;
  return n;
end $$;


-- =====================================================================
-- 13. FONCTIONS APPELÉES PAR LES UTILISATEURS CONNECTÉS
-- =====================================================================

-- Libère les fonds dus de l'utilisateur connecté (appelée à l'ouverture de son portefeuille).
create or replace function public.release_my_funds()
returns integer language sql security definer set search_path = public as $$
  select public.release_due_funds(auth.uid());
$$;

-- Le vendeur fait avancer sa commande physique :
-- En attente -> Confirmée -> Expédiée (ou Prête pour retrait) -> Livrée
create or replace function public.seller_update_order_status(p_order uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.seller_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  -- Commande payée en ligne, OU commande en paiement à la livraison pas encore encaissée.
  if o.delivery_method is null or not (o.payment_status = 'paid' or (o.payment_method = 'cod' and o.payment_status = 'pending' and o.status <> 'cancelled')) then
    raise exception 'commande_invalide';
  end if;
  -- Cash : "Livrée" passe uniquement par seller_confirm_cash (encaissement du cash + commission).
  if o.payment_method = 'cod' and o.payment_status = 'pending' and p_status = 'delivered' then raise exception 'encaissement_requis'; end if;

  if not (
       (o.status = 'pending'   and p_status = 'confirmed')
    or (o.status = 'confirmed' and p_status = 'shipped'          and o.delivery_method in ('delivery_douala', 'shipping_cameroon'))
    or (o.status = 'confirmed' and p_status = 'ready_for_pickup' and o.delivery_method = 'pickup_douala')
    or (o.status in ('shipped', 'ready_for_pickup') and p_status = 'delivered')
  ) then
    raise exception 'transition_invalide';
  end if;

  update public.orders
     set status = p_status,
         delivered_at = case when p_status = 'delivered' then now() else delivered_at end
   where id = o.id;

  if p_status = 'delivered' then
    -- Acheteur déjà confirmé => fonds libérés tout de suite ; sinon dans 7 jours (sans litige).
    update public.transactions
       set release_at = case when o.buyer_confirmed_at is not null then now() else now() + interval '7 days' end
     where order_id = o.id and status = 'paid' and released_at is null;
  end if;
end $$;

-- L'acheteur confirme avoir reçu sa commande.
create or replace function public.buyer_confirm_delivery(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.buyer_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  if o.payment_status <> 'paid' or o.delivery_method is null
     or o.status not in ('shipped', 'ready_for_pickup', 'delivered', 'completed') then
    raise exception 'commande_invalide';
  end if;
  if o.buyer_confirmed_at is not null then return; end if;

  -- "J'ai reçu mon produit" : la commande est livrée et les fonds du vendeur sont libérés tout de suite
  -- (sauf litige ouvert : l'admin tranche d'abord).
  update public.orders
     set buyer_confirmed_at = now(), status = case when status = 'completed' then status else 'delivered' end, delivered_at = coalesce(delivered_at, now())
   where id = o.id;

  update public.transactions set release_at = now()
   where order_id = o.id and status = 'paid' and released_at is null;
end $$;

-- L'acheteur signale un problème : les fonds restent bloqués jusqu'à décision de l'admin.
create or replace function public.buyer_open_dispute(p_order uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
  v_released timestamptz;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.buyer_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  if o.payment_status <> 'paid' or o.delivery_method is null then raise exception 'commande_invalide'; end if;
  if p_reason is null or char_length(trim(p_reason)) < 5 or char_length(p_reason) > 500 then
    raise exception 'motif_invalide';
  end if;
  select released_at into v_released from public.transactions where order_id = o.id;
  if v_released is not null then raise exception 'fonds_deja_liberes'; end if;

  update public.orders
     set disputed = true, disputed_at = now(), dispute_reason = trim(p_reason)
   where id = o.id;
end $$;

-- Demande de retrait : le montant est bloqué immédiatement (impossible de le demander deux fois).
-- L'argent n'est PAS envoyé automatiquement : vous validez et payez à la main depuis votre dashboard admin.
create or replace function public.request_withdrawal(p_amount bigint, p_method text, p_phone text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_id     uuid;
  v_deduct bigint := 0;
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

  insert into public.withdrawals (user_id, amount, method, phone_number, commission_deducted)
  values (v_uid, p_amount, p_method, p_phone, v_deduct)
  returning id into v_id;
  return v_id;
end $$;


-- =====================================================================
-- 14. FONCTIONS ADMIN (vérifient que l'appelant est admin)
-- =====================================================================

-- Valide un retrait : 'paid' (vous avez envoyé l'argent) ou 'failed' (refusé : le solde est rendu).
create or replace function public.admin_process_withdrawal(p_id uuid, p_result text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  w public.withdrawals%rowtype;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_result not in ('paid', 'failed') then raise exception 'resultat_invalide'; end if;

  select * into w from public.withdrawals where id = p_id for update;
  if not found or w.status <> 'pending' then raise exception 'retrait_deja_traite'; end if;

  if p_result = 'paid' then
    update public.wallets set total_withdrawn = total_withdrawn + w.amount, updated_at = now() where user_id = w.user_id;
  else
    -- Refusé : le solde est rendu, et la commission cash qui devait être prélevée redevient due.
    update public.wallets
       set balance_available = balance_available + w.amount, commission_due = commission_due + w.commission_deducted, updated_at = now()
     where user_id = w.user_id;
  end if;

  update public.withdrawals
     set status = p_result, note = p_note, processed_at = now(), processed_by = auth.uid()
   where id = w.id;
end $$;

-- Rembourse une transaction dont les fonds ne sont pas encore libérés.
-- (Le remboursement réel au client se fait à la main depuis votre compte Fapshi.)
create or replace function public.admin_refund_transaction(p_transaction uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.transactions%rowtype;
  o public.orders%rowtype;
  p public.products%rowtype;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;

  select * into t from public.transactions where id = p_transaction for update;
  if not found or t.status not in ('paid', 'review') then raise exception 'transaction_invalide'; end if;
  if t.released_at is not null then raise exception 'fonds_deja_liberes'; end if;

  select * into o from public.orders where id = t.order_id for update;
  select * into p from public.products where id = t.product_id for update;

  if t.status = 'paid' then
    -- on retire les montants "en attente" du vendeur et de l'affilié
    update public.wallets
       set balance_pending = balance_pending - t.seller_amount,
           total_earned = total_earned - t.seller_amount, updated_at = now()
     where user_id = t.seller_id;
    if t.affiliate_id is not null and t.affiliate_fee > 0 then
      update public.wallets
         set balance_pending = balance_pending - t.affiliate_fee,
             total_earned = total_earned - t.affiliate_fee, updated_at = now()
       where user_id = t.affiliate_id;
    end if;
    -- on remet le stock / la clé de licence
    if p.product_type = 'physical' then
      update public.products set stock = stock + o.quantity where id = p.id;
    end if;
    update public.license_keys set order_id = null, assigned_at = null where order_id = o.id;
  end if;

  update public.transactions
     set status = 'refunded', review_reason = coalesce(p_note, review_reason)
   where id = t.id;
  update public.orders set payment_status = 'refunded', status = 'cancelled', disputed = false where id = o.id;
end $$;

-- Litige tranché en faveur du vendeur : on lève le blocage (les fonds se libèrent à l'échéance prévue).
create or replace function public.admin_resolve_dispute(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found or not o.disputed then raise exception 'commande_invalide'; end if;

  update public.orders set disputed = false where id = o.id;
  if o.status in ('delivered', 'completed') then
    update public.transactions set release_at = now()
     where order_id = o.id and status = 'paid' and released_at is null;
  end if;
end $$;


-- =====================================================================
-- 15. VUES (tableaux de bord)
-- =====================================================================

-- Pour l'affilié : ses ventes et SA commission uniquement (pas la part du vendeur).
create or replace view public.affiliate_sales as
  select t.id, t.product_id, p.title as product_title, t.total_amount,
         t.affiliate_fee, t.affiliate_fee_percent, t.status, t.paid_at, t.released_at, t.affiliate_id
    from public.transactions t
    join public.products p on p.id = t.product_id
   where t.affiliate_id = auth.uid();
grant select on public.affiliate_sales to authenticated;
revoke all on public.affiliate_sales from anon;

-- Pour l'admin : frais de plateforme gagnés, séparés par taux (5 % avec affilié / 10 % sans affilié).
-- security_invoker : un non-admin ne verrait que ses propres lignes.
create or replace view public.admin_fee_summary with (security_invoker = true) as
  select platform_fee_percent,
         count(*)::bigint                       as sales,
         coalesce(sum(total_amount), 0)::bigint as volume,
         coalesce(sum(platform_fee), 0)::bigint as platform_fees,
         coalesce(sum(affiliate_fee), 0)::bigint as affiliate_fees,
         coalesce(sum(seller_amount), 0)::bigint as seller_amounts,
         coalesce(sum(fapshi_revenue), 0)::bigint as fapshi_received
    from public.transactions
   where status = 'paid'
   group by platform_fee_percent;
grant select on public.admin_fee_summary to authenticated;
revoke all on public.admin_fee_summary from anon;

-- Pour le vendeur : visites, ventes payées et conversion de SES produits (l'admin voit tout).
-- security_invoker : les règles RLS des tables sous-jacentes s'appliquent aussi.
create or replace view public.seller_product_stats with (security_invoker = true) as
  select p.id as product_id, p.seller_id, p.title, p.product_type,
         (select count(*) from public.product_views v where v.product_id = p.id)::bigint as views,
         (select count(*) from public.transactions t where t.product_id = p.id and t.status = 'paid')::bigint as sales
    from public.products p
   where p.seller_id = auth.uid() or public.is_admin();
grant select on public.seller_product_stats to authenticated;
revoke all on public.seller_product_stats from anon;


-- =====================================================================
-- 16. DROITS D'EXÉCUTION DES FONCTIONS
--     Par défaut Supabase autorise tout le monde : on referme tout, puis on ouvre au cas par cas.
-- =====================================================================

revoke all on function public.create_checkout_order(uuid, uuid, text, text, integer, text, text, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.confirm_fapshi_payment(text, bigint, text, bigint)    from public, anon, authenticated;
revoke all on function public.mark_fapshi_failed(text, text)                         from public, anon, authenticated;
revoke all on function public.record_affiliate_click(text, uuid, uuid)               from public, anon, authenticated;
revoke all on function public.release_due_funds(uuid)                                from public, anon, authenticated;
grant execute on function public.create_checkout_order(uuid, uuid, text, text, integer, text, text, text, text, text, text, text, text) to service_role;
grant execute on function public.confirm_fapshi_payment(text, bigint, text, bigint)  to service_role;
grant execute on function public.mark_fapshi_failed(text, text)                      to service_role;
grant execute on function public.record_affiliate_click(text, uuid, uuid)            to service_role;
grant execute on function public.release_due_funds(uuid)                             to service_role;

revoke all on function public.release_my_funds()                                     from public, anon;
revoke all on function public.seller_update_order_status(uuid, text)                 from public, anon;
revoke all on function public.buyer_confirm_delivery(uuid)                           from public, anon;
revoke all on function public.buyer_open_dispute(uuid, text)                         from public, anon;
revoke all on function public.request_withdrawal(bigint, text, text)                 from public, anon;
revoke all on function public.admin_process_withdrawal(uuid, text, text)             from public, anon;
revoke all on function public.admin_refund_transaction(uuid, text)                   from public, anon;
revoke all on function public.admin_resolve_dispute(uuid)                            from public, anon;
grant execute on function public.release_my_funds()                                  to authenticated;
grant execute on function public.seller_update_order_status(uuid, text)              to authenticated;
grant execute on function public.buyer_confirm_delivery(uuid)                        to authenticated;
grant execute on function public.buyer_open_dispute(uuid, text)                      to authenticated;
grant execute on function public.request_withdrawal(bigint, text, text)              to authenticated;
grant execute on function public.admin_process_withdrawal(uuid, text, text)          to authenticated;
grant execute on function public.admin_refund_transaction(uuid, text)                to authenticated;
grant execute on function public.admin_resolve_dispute(uuid)                         to authenticated;


-- =====================================================================
-- 17. STOCKAGE DES FICHIERS (Supabase Storage)
--   covers       : PUBLIC  — couvertures et photos des produits (images, 5 Mo max)
--   deliverables : PRIVÉ   — fichiers vendus (jamais publics, servis par lien signé de 60 s)
--   Chaque vendeur écrit uniquement dans son dossier <son_id>/...
-- =====================================================================

-- Ce bloc est protégé : si Supabase refuse une de ces étapes, le reste du script reste valide
-- et un message vous explique quoi créer à la main dans Storage.
do $storage$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('covers', 'covers', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update
    set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

  insert into storage.buckets (id, name, public)
  values ('deliverables', 'deliverables', false)
  on conflict (id) do nothing;

  drop policy if exists covers_read on storage.objects;
  create policy covers_read on storage.objects for select using (bucket_id = 'covers');
  drop policy if exists covers_insert on storage.objects;
  create policy covers_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'covers' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists covers_delete on storage.objects;
  create policy covers_delete on storage.objects for delete to authenticated
    using (bucket_id = 'covers' and (storage.foldername(name))[1] = auth.uid()::text);

  drop policy if exists deliverables_insert on storage.objects;
  create policy deliverables_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'deliverables' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists deliverables_select on storage.objects;
  create policy deliverables_select on storage.objects for select to authenticated
    using (bucket_id = 'deliverables' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists deliverables_delete on storage.objects;
  create policy deliverables_delete on storage.objects for delete to authenticated
    using (bucket_id = 'deliverables' and (storage.foldername(name))[1] = auth.uid()::text);
exception when others then
  raise notice 'STOCKAGE : configuration automatique impossible (%). Créez à la main, dans Storage : un bucket "covers" (public) et un bucket "deliverables" (privé).', sqlerrm;
end $storage$;


-- =====================================================================
-- 18. VOUS DEVENEZ ADMINISTRATEUR  (à faire UNE FOIS, après votre inscription sur le site)
--     Remplacez l'email ci-dessous par celui de votre compte, puis exécutez cette ligne seule :
--
--   update public.profiles set role = 'admin'
--    where id = (select id from auth.users where email = 'VOTRE_EMAIL@exemple.com');
-- =====================================================================


-- =====================================================================
-- 18. CONTACT VENDEUR PRIVÉ + PARTAGES + BOOST + ACTIVITÉ  (nouveautés)
-- =====================================================================

-- 18.1  Données du produit cachées au public : numéro WhatsApp du vendeur, lien de réservation et instructions
--       (ils ne sont montrés qu'APRÈS paiement, par le serveur). On remplace le droit de lecture "toute la table"
--       par une liste de colonnes autorisées.
alter table public.products add column if not exists last_inactivity_email_at timestamptz;

revoke select, insert, update on public.products from anon, authenticated;
grant select (id, seller_id, product_type, digital_kind, title, slug, description, cover_url, price, is_published,
              affiliate_enabled, affiliate_percent, duration_minutes, stock, images, weight, variant,
              delivery_options, created_at, updated_at, category, city, rating_avg, rating_count, moderation_status)
  on public.products to anon, authenticated;
grant select (moderation_note) on public.products to authenticated;
-- Le vendeur peut créer/modifier ses produits, mais JAMAIS se les approuver lui-même (moderation_status, notes, ville).
grant insert (id, seller_id, product_type, digital_kind, title, slug, description, cover_url, price, is_published,
              affiliate_enabled, affiliate_percent, booking_url, duration_minutes, delivery_notes, stock, images,
              weight, variant, delivery_options, whatsapp_seller, category)
  on public.products to authenticated;
grant update (digital_kind, title, slug, description, cover_url, price, is_published, affiliate_enabled, affiliate_percent,
              booking_url, duration_minutes, delivery_notes, stock, images, weight, variant, delivery_options,
              whatsapp_seller, category)
  on public.products to authenticated;

-- 18.2  Quand le vendeur change son numéro WhatsApp (profil), tous ses produits sont mis à jour automatiquement.
create or replace function public.sync_seller_whatsapp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.whatsapp is not null and new.whatsapp is distinct from old.whatsapp then
    update public.products set whatsapp_seller = new.whatsapp where seller_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists profiles_sync_whatsapp on public.profiles;
create trigger profiles_sync_whatsapp after update of whatsapp on public.profiles
  for each row execute function public.sync_seller_whatsapp();

-- 18.3  Partages (pour détecter un produit "endormi")
create table if not exists public.product_shares (
  id         bigint generated always as identity primary key,
  product_id uuid not null references public.products(id) on delete cascade,
  channel    text not null,
  created_at timestamptz not null default now()
);
create index if not exists product_shares_idx on public.product_shares (product_id, created_at);
alter table public.product_shares enable row level security;
drop policy if exists product_shares_select on public.product_shares;
create policy product_shares_select on public.product_shares for select
  using (
    exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid())
    or public.is_admin()
  );
revoke insert, update, delete, truncate on public.product_shares from anon, authenticated;
revoke all on public.product_shares from anon;

-- 18.4  Boost payant (payé via Fapshi)
--       3 jours : 1 000 FCFA -> en haut de sa catégorie, badge "À la une"
--       7 jours : 2 500 FCFA -> en haut de l'accueil,   badge "Populaire"
create table if not exists public.product_boosts (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references public.products(id) on delete cascade,
  seller_id       uuid not null references public.profiles(id) on delete cascade,
  plan            text not null check (plan in ('3d', '7d')),
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
create index if not exists product_boosts_product_idx on public.product_boosts (product_id, status, ends_at);
create index if not exists product_boosts_seller_idx on public.product_boosts (seller_id, created_at desc);
alter table public.product_boosts enable row level security;
drop policy if exists product_boosts_select on public.product_boosts;
create policy product_boosts_select on public.product_boosts for select
  using (seller_id = auth.uid() or public.is_admin());
revoke insert, update, delete, truncate on public.product_boosts from anon, authenticated;
revoke all on public.product_boosts from anon;

-- Boosts actifs : visibles par tout le monde (sert aux badges et à la section "À la une").
create or replace view public.active_boosts as
  select product_id, plan, ends_at
    from public.product_boosts
   where status = 'paid' and starts_at <= now() and ends_at > now();
grant select on public.active_boosts to anon, authenticated;

-- Confirme le paiement d'un boost (appelée par le serveur APRÈS vérification chez Fapshi).
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

  v_days := case b.plan when '3d' then 3 else 7 end;
  -- Si le produit est déjà boosté, le nouveau boost commence à la fin du précédent.
  select greatest(now(), coalesce(max(ends_at), now())) into v_start
    from public.product_boosts where product_id = b.product_id and status = 'paid' and ends_at > now();

  update public.product_boosts
     set status = 'paid', fapshi_status = 'SUCCESSFUL', paid_at = now(),
         starts_at = v_start, ends_at = v_start + make_interval(days => v_days)
   where id = b.id;
  return jsonb_build_object('status', 'paid', 'boost_id', b.id);
end $$;

create or replace function public.mark_boost_failed(p_trans_id text, p_fapshi_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.product_boosts
     set status = case when p_fapshi_status = 'EXPIRED' then 'expired' else 'failed' end, fapshi_status = p_fapshi_status
   where fapshi_trans_id = p_trans_id and status = 'pending';
end $$;

-- 18.5  Activité des produits (vues / ventes / partages sur 3 jours) : sert aux alertes "produit invisible".
create or replace view public.seller_product_activity with (security_invoker = true) as
  select p.id as product_id, p.seller_id, p.title, p.created_at, p.is_published,
         (select count(*) from public.product_views v where v.product_id = p.id)::bigint as views_total,
         (select count(*) from public.product_views v where v.product_id = p.id and v.created_at > now() - interval '3 days')::bigint as views_3d,
         (select count(*) from public.transactions t where t.product_id = p.id and t.status = 'paid' and t.paid_at > now() - interval '3 days')::bigint as sales_3d,
         (select count(*) from public.product_shares s where s.product_id = p.id and s.created_at > now() - interval '3 days')::bigint as shares_3d,
         greatest(
           p.created_at,
           (select max(v.created_at) from public.product_views v where v.product_id = p.id),
           (select max(t.paid_at) from public.transactions t where t.product_id = p.id and t.status = 'paid'),
           (select max(s.created_at) from public.product_shares s where s.product_id = p.id)
         ) as last_activity,
         p.price
    from public.products p
   where p.seller_id = auth.uid() or public.is_admin();
grant select on public.seller_product_activity to authenticated;
revoke all on public.seller_product_activity from anon;

-- Produits "endormis" à qui envoyer l'email (0 vente, 0 partage et moins de 10 vues en 3 jours ; 1 email / 7 jours).
create or replace function public.inactive_products_to_notify()
returns table (product_id uuid, seller_id uuid, title text, views_3d bigint)
language sql security definer set search_path = public as $$
  select p.id, p.seller_id, p.title,
         (select count(*) from public.product_views v where v.product_id = p.id and v.created_at > now() - interval '3 days')
    from public.products p
   where p.is_published
     and p.created_at < now() - interval '3 days'
     and (p.last_inactivity_email_at is null or p.last_inactivity_email_at < now() - interval '7 days')
     and not exists (select 1 from public.transactions t where t.product_id = p.id and t.status = 'paid' and t.paid_at > now() - interval '3 days')
     and not exists (select 1 from public.product_shares s where s.product_id = p.id and s.created_at > now() - interval '3 days')
     and (select count(*) from public.product_views v where v.product_id = p.id and v.created_at > now() - interval '3 days') < 10
   limit 50;
$$;

-- 18.6  Droits d'exécution
revoke all on function public.confirm_boost_payment(text, bigint)   from public, anon, authenticated;
revoke all on function public.mark_boost_failed(text, text)         from public, anon, authenticated;
revoke all on function public.inactive_products_to_notify()         from public, anon, authenticated;
revoke all on function public.sync_seller_whatsapp()                from public, anon, authenticated;
grant execute on function public.confirm_boost_payment(text, bigint) to service_role;
grant execute on function public.mark_boost_failed(text, text)       to service_role;
grant execute on function public.inactive_products_to_notify()       to service_role;



-- =====================================================================
-- 19. AVIS, VENDEUR VÉRIFIÉ, RECHERCHE, PAIEMENT À LA LIVRAISON, ADMIN
-- =====================================================================

-- 19.1  Catégories des produits existants (d'après leur type), et ville du vendeur sur chaque produit
update public.products set category = case digital_kind
    when 'file' then 'Ebooks' when 'course' then 'Formations' when 'license' then 'Licences'
    when 'coaching' then 'Coaching' when 'service' then 'Services' else 'Autres' end
 where category is null;

update public.products p set city = pr.city from public.profiles pr where pr.id = p.seller_id and p.city is null and pr.city is not null;

create or replace function public.set_product_city()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.city := (select city from public.profiles where id = new.seller_id);
  return new;
end $$;
drop trigger if exists products_set_city on public.products;
create trigger products_set_city before insert on public.products for each row execute function public.set_product_city();

-- Quand le vendeur change de ville ou de prix de livraison (profil), ses produits suivent automatiquement.
create or replace function public.sync_seller_profile_to_products()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.city is distinct from old.city then
    update public.products set city = new.city where seller_id = new.id;
  end if;
  if new.delivery_douala_price is distinct from old.delivery_douala_price
     or new.delivery_shipping_price is distinct from old.delivery_shipping_price then
    update public.products
       set delivery_options = jsonb_set(jsonb_set(delivery_options,
             '{delivery_douala,price}', to_jsonb(new.delivery_douala_price)),
             '{shipping_cameroon,price}', to_jsonb(new.delivery_shipping_price))
     where seller_id = new.id and product_type = 'physical' and delivery_options is not null;
  end if;
  return new;
end $$;
drop trigger if exists profiles_sync_products on public.profiles;
create trigger profiles_sync_products after update of city, delivery_douala_price, delivery_shipping_price on public.profiles
  for each row execute function public.sync_seller_profile_to_products();

-- 19.2  Avis (1 à 5 étoiles + commentaire), uniquement après "J'ai reçu mon produit"
create table if not exists public.reviews (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null unique references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  seller_id  uuid not null references public.profiles(id) on delete cascade,
  buyer_id   uuid not null references public.profiles(id) on delete cascade,
  rating     smallint not null check (rating between 1 and 5),
  comment    text check (comment is null or char_length(comment) <= 1000),
  created_at timestamptz not null default now()
);
create index if not exists reviews_product_idx on public.reviews (product_id, created_at desc);
create index if not exists reviews_seller_idx on public.reviews (seller_id);
alter table public.reviews enable row level security;
drop policy if exists reviews_select on public.reviews;
create policy reviews_select on public.reviews for select using (buyer_id = auth.uid() or public.is_admin());
revoke insert, update, delete, truncate on public.reviews from anon, authenticated;
revoke all on public.reviews from anon;

create or replace function public.submit_review(p_order uuid, p_rating integer, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
begin
  select * into o from public.orders where id = p_order;
  if not found or o.buyer_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  if o.delivery_method is null or o.payment_status <> 'paid' or o.buyer_confirmed_at is null then
    raise exception 'avis_non_autorise';           -- il faut d'abord cliquer "J'ai reçu mon produit"
  end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'note_invalide'; end if;
  if exists (select 1 from public.reviews where order_id = o.id) then raise exception 'avis_deja_envoye'; end if;

  insert into public.reviews (order_id, product_id, seller_id, buyer_id, rating, comment)
  values (o.id, o.product_id, o.seller_id, o.buyer_id, p_rating, nullif(left(trim(coalesce(p_comment, '')), 1000), ''));

  update public.products p
     set rating_avg = coalesce((select round(avg(r.rating)::numeric, 2) from public.reviews r where r.product_id = p.id), 0),
         rating_count = (select count(*) from public.reviews r where r.product_id = p.id)
   where p.id = o.product_id;
end $$;

-- Notes par vendeur (publiques)
create or replace view public.seller_ratings as
  select seller_id, round(avg(rating)::numeric, 2) as avg_rating, count(*)::bigint as review_count
    from public.reviews group by seller_id;
grant select on public.seller_ratings to anon, authenticated;

-- Avis affichés sur les pages (prénom seulement, pas d'identifiant)
create or replace view public.public_reviews as
  select r.id, r.product_id, r.seller_id, r.rating, r.comment, r.created_at,
         coalesce(nullif(split_part(coalesce(pr.full_name, ''), ' ', 1), ''), 'Client') as reviewer_name
    from public.reviews r
    left join public.profiles pr on pr.id = r.buyer_id;
grant select on public.public_reviews to anon, authenticated;

-- 19.3  Paiement à la livraison : le vendeur encaisse le cash -> commission 8 % due à KDDF Market
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
  select * into s from public.compute_split_for(v_goods, false, 0, true);

  update public.orders set payment_status = 'paid', paid_at = now() where id = o.id;                 -- En attente -> Payé (cash encaissé)
  update public.orders set status = 'delivered', delivered_at = now() where id = o.id;               -- Payé -> Livré

  update public.transactions
     set status = 'paid', paid_at = now(), goods_amount = v_goods,
         platform_fee = s.platform_fee, platform_fee_percent = s.platform_percent,
         affiliate_fee = 0, affiliate_fee_percent = 0, seller_amount = total_amount - s.platform_fee,
         release_at = now(), released_at = now()                -- le cash est déjà chez le vendeur : rien à libérer
   where order_id = o.id;

  update public.orders set status = 'completed' where id = o.id;                                    -- Livré -> Terminé (le cash est déjà chez le vendeur)
  update public.wallets set commission_due = commission_due + s.platform_fee, updated_at = now() where user_id = o.seller_id;
end $$;

create or replace function public.seller_cancel_cod(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.seller_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  if o.payment_method <> 'cod' or o.payment_status <> 'pending' or o.status = 'cancelled' then raise exception 'commande_invalide'; end if;

  update public.orders set status = 'cancelled', payment_status = 'failed' where id = o.id;
  update public.transactions set status = 'failed' where order_id = o.id;
  update public.products set stock = stock + o.quantity where id = o.product_id;   -- le stock réservé est rendu
end $$;

-- 19.4  Administration : badge vérifié, blocage, modération des produits
create or replace function public.admin_set_verified(p_user uuid, p_value boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  update public.profiles set is_verified = coalesce(p_value, false) where id = p_user;
end $$;

create or replace function public.admin_set_blocked(p_user uuid, p_value boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_user = auth.uid() then raise exception 'action_interdite'; end if;
  update public.profiles set is_blocked = coalesce(p_value, false) where id = p_user;
  if coalesce(p_value, false) then
    update public.products set is_published = false where seller_id = p_user;   -- ses produits disparaissent du site
  end if;
end $$;

create or replace function public.admin_moderate_product(p_product uuid, p_decision text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_decision not in ('approved', 'rejected') then raise exception 'decision_invalide'; end if;
  update public.products
     set moderation_status = p_decision,
         moderation_note = case when p_decision = 'rejected' then nullif(left(trim(coalesce(p_note, '')), 300), '') else null end
   where id = p_product;
  if not found then raise exception 'produit_introuvable'; end if;
end $$;

-- 19.5  Chiffres du tableau de bord admin (une seule ligne ; vide pour un non-admin)
create or replace view public.admin_stats with (security_invoker = true) as
  select
    (select count(distinct seller_id) from public.products)::bigint                                    as total_sellers,
    (select count(*) from public.profiles)::bigint                                                      as total_users,
    (select count(*) from public.orders where payment_status = 'paid' or (payment_method = 'cod' and status <> 'cancelled'))::bigint as total_orders,
    (select coalesce(sum(platform_fee), 0) from public.transactions
      where status = 'paid' and paid_at >= date_trunc('day', now() at time zone 'Africa/Douala') at time zone 'Africa/Douala')::bigint   as commissions_today,
    (select coalesce(sum(platform_fee), 0) from public.transactions
      where status = 'paid' and paid_at >= date_trunc('month', now() at time zone 'Africa/Douala') at time zone 'Africa/Douala')::bigint as commissions_month,
    (select coalesce(sum(commission_due), 0) from public.wallets)::bigint                               as commissions_due,
    (select count(*) from public.products where moderation_status = 'pending')::bigint                  as products_pending,
    (select count(*) from public.withdrawals where status = 'pending')::bigint                          as withdrawals_pending
  where public.is_admin();
grant select on public.admin_stats to authenticated;
revoke all on public.admin_stats from anon;

-- 19.6  Droits d'exécution
revoke all on function public.submit_review(uuid, integer, text)           from public, anon;
revoke all on function public.seller_confirm_cash(uuid)                    from public, anon;
revoke all on function public.seller_cancel_cod(uuid)                      from public, anon;
revoke all on function public.admin_set_verified(uuid, boolean)            from public, anon;
revoke all on function public.admin_set_blocked(uuid, boolean)             from public, anon;
revoke all on function public.admin_moderate_product(uuid, text, text)     from public, anon;
revoke all on function public.set_product_city()                           from public, anon, authenticated;
revoke all on function public.sync_seller_profile_to_products()            from public, anon, authenticated;
grant execute on function public.submit_review(uuid, integer, text)        to authenticated;
grant execute on function public.seller_confirm_cash(uuid)                 to authenticated;
grant execute on function public.seller_cancel_cod(uuid)                   to authenticated;
grant execute on function public.admin_set_verified(uuid, boolean)         to authenticated;
grant execute on function public.admin_set_blocked(uuid, boolean)          to authenticated;
grant execute on function public.admin_moderate_product(uuid, text, text)  to authenticated;


-- =====================================================================
-- 21. DURCISSEMENT (avertissements du Conseiller de sécurité Supabase)
--   * handle_new_user() est un déclencheur : personne n'a besoin de pouvoir l'appeler directement.
--   * search_path figé sur les fonctions de calcul (évite le détournement par un schéma piégé).
-- =====================================================================
revoke execute on function public.handle_new_user() from public, anon, authenticated;
alter function public.valid_delivery_options(jsonb) set search_path = public;

-- =====================================================================
-- 20. RECHARGEMENT DU CACHE DE L'API
--     Sans cela, Supabase peut répondre "Could not find the table ... in the schema cache"
--     juste après la création des tables.
-- =====================================================================
notify pgrst, 'reload schema';


-- =====================================================================
-- 22. AVIS (photo, ville) + SUIVI DE COMMANDE + garantie
-- =====================================================================
-- =====================================================================
-- KDDF Market : AVIS CLIENTS (photo, ville) + SUIVI DE COMMANDE (4 étapes) + garantie
-- Script AUTONOME et idempotent : à exécuter UNE FOIS dans Supabase > SQL Editor (après schema.sql).
-- Il CRÉE seulement de nouvelles tables / vues / fonctions. Aucune table existante n'est modifiée
-- et la logique des portefeuilles (wallets) n'est pas touchée.
--
-- Note : la table "reviews" existe déjà (avis liés à une commande). Elle est réutilisée telle quelle ;
-- la photo de l'avis est stockée dans la NOUVELLE table review_extras.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. SUIVI DE COMMANDE : nouvelle table order_tracking (dates de chaque étape)
-- ---------------------------------------------------------------------
create table if not exists public.order_tracking (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.orders(id) on delete cascade,
  status     text not null check (status in ('confirmed', 'shipped', 'ready_for_pickup', 'out_for_delivery', 'delivered')),
  updated_at timestamptz not null default now(),
  unique (order_id, status)
);
create index if not exists order_tracking_order_idx on public.order_tracking (order_id);

alter table public.order_tracking enable row level security;
drop policy if exists order_tracking_select on public.order_tracking;
create policy order_tracking_select on public.order_tracking for select
  using (
    public.is_admin()
    or exists (select 1 from public.orders o where o.id = order_id and (o.buyer_id = auth.uid() or o.seller_id = auth.uid()))
  );
revoke insert, update, delete, truncate on public.order_tracking from anon, authenticated;
revoke all on public.order_tracking from anon;

-- Journal automatique : chaque changement de statut d'une commande est daté dans order_tracking.
-- Ne modifie jamais la commande et ne peut JAMAIS la bloquer (toute erreur est ignorée).
create or replace function public.log_order_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.status in ('confirmed', 'shipped', 'ready_for_pickup', 'delivered') then
      insert into public.order_tracking (order_id, status) values (new.id, new.status) on conflict (order_id, status) do nothing;
    end if;
  exception when others then
    null;
  end;
  return null;
end $$;
revoke execute on function public.log_order_status() from public, anon, authenticated;

drop trigger if exists orders_log_tracking on public.orders;
create trigger orders_log_tracking after update of status on public.orders
  for each row when (old.status is distinct from new.status) execute function public.log_order_status();

-- Étape 3 « En cours de livraison » (n'existe pas dans les statuts de commande) : le vendeur la marque.
-- Elle n'a AUCUN effet sur l'argent : les fonds restent bloqués jusqu'à « Livrée ».
create or replace function public.seller_mark_out_for_delivery(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.seller_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  if o.status <> 'shipped' or o.delivery_method not in ('delivery_douala', 'shipping_cameroon') then
    raise exception 'transition_invalide';
  end if;
  insert into public.order_tracking (order_id, status) values (o.id, 'out_for_delivery') on conflict (order_id, status) do nothing;
end $$;
revoke all on function public.seller_mark_out_for_delivery(uuid) from public, anon;
grant execute on function public.seller_mark_out_for_delivery(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- B. AVIS CLIENTS : photo de l'avis (nouvelle table) + vues publiques + répartition des notes
-- ---------------------------------------------------------------------
create table if not exists public.review_extras (
  review_id  uuid primary key references public.reviews(id) on delete cascade,
  photo_url  text check (photo_url is null or (photo_url ~ '^https://' and char_length(photo_url) <= 500)),
  created_at timestamptz not null default now()
);
alter table public.review_extras enable row level security;
revoke all on public.review_extras from anon, authenticated;   -- lecture via la vue, écriture via la fonction

-- Avis affichés sur la page produit : prénom + ville, sans identifiant ni email.
create or replace view public.product_reviews_public as
  select r.id, r.product_id, r.rating, r.comment, r.created_at,
         coalesce(nullif(split_part(coalesce(pr.full_name, ''), ' ', 1), ''), 'Client') as reviewer_name,
         nullif(trim(coalesce(pr.city, '')), '') as reviewer_city,
         pr.avatar_url as reviewer_avatar,
         x.photo_url
    from public.reviews r
    left join public.profiles pr on pr.id = r.buyer_id
    left join public.review_extras x on x.review_id = r.id;
grant select on public.product_reviews_public to anon, authenticated;

-- Nombre d'avis par note (pour la répartition 5 étoiles 70 %, 4 étoiles 20 %...)
create or replace view public.product_review_stats as
  select product_id, rating::int as rating, count(*)::bigint as n
    from public.reviews group by product_id, rating;
grant select on public.product_review_stats to anon, authenticated;

-- Publier un avis : acheteur du produit, commande payée ET livrée (produit digital : payé = livré).
-- Un client = un seul avis par produit.
create or replace function public.submit_product_review(p_order uuid, p_rating integer, p_comment text default null, p_photo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  o    public.orders%rowtype;
  v_id uuid;
begin
  select * into o from public.orders where id = p_order;
  if not found or o.buyer_id is distinct from auth.uid() then raise exception 'acces_refuse'; end if;
  if o.payment_status <> 'paid' or (o.delivery_method is not null and o.status not in ('delivered', 'completed')) then
    raise exception 'avis_non_autorise';
  end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'note_invalide'; end if;
  if exists (select 1 from public.reviews where buyer_id = o.buyer_id and product_id = o.product_id) then
    raise exception 'avis_deja_envoye';
  end if;
  if p_photo is not null and (p_photo !~ '^https://' or char_length(p_photo) > 500) then raise exception 'photo_invalide'; end if;

  insert into public.reviews (order_id, product_id, seller_id, buyer_id, rating, comment)
  values (o.id, o.product_id, o.seller_id, o.buyer_id, p_rating, nullif(left(trim(coalesce(p_comment, '')), 1000), ''))
  returning id into v_id;

  if p_photo is not null then
    insert into public.review_extras (review_id, photo_url) values (v_id, p_photo);
  end if;

  update public.products p
     set rating_avg = coalesce((select round(avg(r.rating)::numeric, 2) from public.reviews r where r.product_id = p.id), 0),
         rating_count = (select count(*) from public.reviews r where r.product_id = p.id)
   where p.id = o.product_id;
end $$;
revoke all on function public.submit_product_review(uuid, integer, text, text) from public, anon;
grant execute on function public.submit_product_review(uuid, integer, text, text) to authenticated;

notify pgrst, 'reload schema';


-- =====================================================================
-- 23. SUPPORT : messages des utilisateurs + captures d'écran
-- =====================================================================
-- =====================================================================
-- KDDF Market : SUPPORT (messages des utilisateurs + captures d'écran)
-- Script autonome et idempotent. Déjà inclus à la fin de schema.sql (section 23) :
-- ne l'exécutez seul que si schema.sql a déjà été exécuté avant cette fonctionnalité.
-- Aucune table existante n'est modifiée.
-- =====================================================================
create table if not exists public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  name        text not null check (char_length(name) between 1 and 100),
  email       text not null check (char_length(email) between 5 and 254),
  category    text not null default 'autre' check (category in ('paiement', 'commande', 'compte', 'bug', 'autre')),
  message     text not null check (char_length(message) between 10 and 3000),
  page_url    text check (page_url is null or char_length(page_url) <= 500),
  images      text[] not null default '{}' check (coalesce(array_length(images, 1), 0) <= 3),
  status      text not null default 'open' check (status in ('open', 'resolved')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists support_messages_status_idx on public.support_messages (status, created_at desc);
create index if not exists support_messages_email_idx on public.support_messages (email, created_at desc);

alter table public.support_messages enable row level security;
drop policy if exists support_select on public.support_messages;
create policy support_select on public.support_messages for select using (public.is_admin());
drop policy if exists support_update on public.support_messages;
create policy support_update on public.support_messages for update using (public.is_admin()) with check (public.is_admin());
-- L'envoi d'un message passe UNIQUEMENT par le serveur du site (clé service_role) : jamais d'écriture directe depuis le navigateur.
revoke all on public.support_messages from anon, authenticated;
grant select on public.support_messages to authenticated;
grant update (status, resolved_at) on public.support_messages to authenticated;

-- Bucket PRIVÉ pour les captures d'écran (lues par l'admin via des liens signés temporaires)
do $support$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('support', 'support', false, 4194304, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = false, file_size_limit = 4194304, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
exception when others then
  raise notice 'STOCKAGE : créez à la main, dans Storage, un bucket "support" (privé). Détail : %', sqlerrm;
end $support$;

notify pgrst, 'reload schema';


-- =====================================================================
-- 24. COMMISSIONS FLEXIBLES — ACTIVÉES PAR DÉFAUT (V3)
-- =====================================================================
-- Règle unique (l'ancien calcul 5 % / 8 % / 10 % est SUPPRIMÉ) :
--   * 0 % pendant les 30 jours de lancement (launch_start_date -> launch_end_date) ;
--   * puis le taux "après lancement" choisi par l'admin dans /admin/commissions (3 % par défaut ; 3, 4 ou 5 %) ;
--   * affilié : 1 % à 50 % du prix, choisi par le vendeur sur chaque produit (20 % par défaut).
-- Sécurité imposée par la base : plateforme <= 10 %, affilié <= 50 % => le vendeur garde toujours >= 40 %.
-- Tous les montants sont des ENTIERS en FCFA, calculés dans la base (jamais dans le navigateur).
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Paramètres de commission (UNE seule ligne, modifiable par l'admin uniquement)
-- ---------------------------------------------------------------------
create table if not exists public.commission_settings (
  id                   integer primary key default 1 check (id = 1),
  platform_fee_percent numeric(4, 2) not null default 0 check (platform_fee_percent between 0 and 10),   -- taux affiché "en cours" (0 pendant le lancement)
  after_launch_percent numeric(4, 2) not null default 3 check (after_launch_percent between 0 and 10),   -- taux appliqué automatiquement à la fin du lancement
  launch_start_date    date not null default current_date,
  launch_end_date      date not null default (current_date + 30),
  is_launch_mode       boolean not null default true,
  updated_at           timestamptz not null default now(),
  updated_by_admin_id  uuid references public.profiles(id) on delete set null,
  check (launch_end_date >= launch_start_date)
);
-- Bases déjà installées : on ajoute le nouveau taux et on SUPPRIME l'ancien interrupteur "ancien système".
alter table public.commission_settings add column if not exists after_launch_percent numeric(4, 2) not null default 3;
do $cs$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.commission_settings'::regclass and conname = 'commission_settings_after_launch_range') then
    alter table public.commission_settings add constraint commission_settings_after_launch_range check (after_launch_percent between 0 and 10);
  end if;
end $cs$;
alter table public.commission_settings drop column if exists is_active;
insert into public.commission_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.commission_history (
  id             uuid primary key default gen_random_uuid(),
  changed_at     timestamptz not null default now(),
  old_percent    numeric(4, 2),
  new_percent    numeric(4, 2),
  old_active     boolean,
  new_active     boolean,
  changed_by     uuid references public.profiles(id) on delete set null,
  notified_count integer not null default 0
);
create index if not exists commission_history_date_idx on public.commission_history (changed_at desc);

alter table public.commission_settings enable row level security;
alter table public.commission_history enable row level security;

-- Lecture publique du taux (les vendeurs doivent le voir) ; jamais l'identité de l'admin. Aucune écriture directe.
drop policy if exists commission_settings_read on public.commission_settings;
create policy commission_settings_read on public.commission_settings for select using (true);
drop policy if exists commission_history_read on public.commission_history;
create policy commission_history_read on public.commission_history for select using (public.is_admin());
revoke all on public.commission_settings from anon, authenticated;
revoke all on public.commission_history from anon, authenticated;
grant select (id, platform_fee_percent, after_launch_percent, launch_start_date, launch_end_date, is_launch_mode, updated_at) on public.commission_settings to anon, authenticated;
grant select on public.commission_history to authenticated;

-- ---------------------------------------------------------------------
-- B. Produits : commission d'affilié de 1 % à 50 % (par défaut 20 % pour les NOUVEAUX produits)
-- ---------------------------------------------------------------------
do $aff$
declare c text;
begin
  for c in
    select conname from pg_constraint
     where conrelid = 'public.products'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%affiliate_percent%'
  loop
    execute format('alter table public.products drop constraint %I', c);
  end loop;
end $aff$;
alter table public.products add constraint products_affiliate_percent_range check (affiliate_percent between 1 and 50);
alter table public.products alter column affiliate_percent set default 20;

-- ---------------------------------------------------------------------
-- C. Calcul de la répartition (côté base, jamais côté navigateur)
-- ---------------------------------------------------------------------
-- Ancien calcul supprimé (bases déjà installées)
drop function if exists public.compute_split_legacy(bigint, boolean, integer, boolean);
drop function if exists public.admin_set_commission_active(boolean);

-- Taux de plateforme réellement appliqué AUJOURD'HUI : 0 pendant le lancement, puis after_launch_percent.
create or replace function public.effective_platform_percent()
returns numeric language plpgsql stable security definer set search_path = public as $$
declare s public.commission_settings%rowtype;
begin
  select * into s from public.commission_settings where id = 1;
  if not found then return 3; end if;
  if s.is_launch_mode and current_date <= s.launch_end_date then return 0; end if;
  if s.is_launch_mode then return least(greatest(s.after_launch_percent, 0), 10); end if;   -- lancement terminé : bascule AUTOMATIQUE
  return least(greatest(s.platform_fee_percent, 0), 10);
end $$;

-- Fonction appelée par toutes les ventes (mêmes paramètres qu'avant)
create or replace function public.compute_split_for(p_goods bigint, p_has_affiliate boolean, p_affiliate_percent integer, p_physical boolean)
returns table (platform_percent integer, platform_fee bigint, affiliate_percent integer, affiliate_fee bigint)
language plpgsql stable security definer set search_path = public as $$
declare
  v_pct numeric;
  v_aff integer;
begin
  v_pct := public.effective_platform_percent();
  v_aff := case when p_has_affiliate then least(greatest(coalesce(p_affiliate_percent, 0), 0), 50) else 0 end;
  return query select
    round(v_pct)::integer,
    floor(p_goods * v_pct / 100)::bigint,
    v_aff,
    case when p_has_affiliate then (p_goods * v_aff) / 100 else 0 end;   -- division entière = arrondi à l'entier inférieur
end $$;

-- ---------------------------------------------------------------------
-- D. Actions de l'admin (seules portes d'écriture) : tout est historisé
-- ---------------------------------------------------------------------
-- p_percent = 0  -> (re)lance 30 jours à 0 %, puis le taux "après lancement" s'applique tout seul
-- p_percent > 0  -> fixe ce taux tout de suite (3, 4, 5 % ... jusqu'à 10 %) et le garde comme taux "après lancement"
create or replace function public.admin_set_commission(p_percent numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s     public.commission_settings%rowtype;
  v_new numeric(4, 2);
  v_hid uuid;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_percent is null or p_percent < 0 or p_percent > 10 then raise exception 'commission_invalide'; end if;
  v_new := round(p_percent, 2);

  select * into s from public.commission_settings where id = 1 for update;
  update public.commission_settings
     set platform_fee_percent = v_new,
         after_launch_percent = case when v_new = 0 then after_launch_percent else v_new end,
         is_launch_mode = (v_new = 0),
         launch_start_date = case when v_new = 0 and (not s.is_launch_mode or current_date > s.launch_end_date) then current_date else launch_start_date end,
         launch_end_date   = case when v_new = 0 and (not s.is_launch_mode or current_date > s.launch_end_date) then current_date + 30 else launch_end_date end,
         updated_at = now(), updated_by_admin_id = auth.uid()
   where id = 1;

  insert into public.commission_history (old_percent, new_percent, old_active, new_active, changed_by)
  values (s.platform_fee_percent, v_new, true, true, auth.uid())
  returning id into v_hid;
  return jsonb_build_object('history_id', v_hid, 'old', s.platform_fee_percent, 'new', v_new, 'active', true);
end $$;

-- Choisit le taux appliqué automatiquement APRÈS les 30 jours de lancement (3, 4 ou 5 % ...)
create or replace function public.admin_set_after_launch_percent(p_percent numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s     public.commission_settings%rowtype;
  v_new numeric(4, 2);
  v_hid uuid;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_percent is null or p_percent < 0 or p_percent > 10 then raise exception 'commission_invalide'; end if;
  v_new := round(p_percent, 2);
  select * into s from public.commission_settings where id = 1 for update;
  update public.commission_settings
     set after_launch_percent = v_new,
         platform_fee_percent = case when is_launch_mode then platform_fee_percent else v_new end,
         updated_at = now(), updated_by_admin_id = auth.uid()
   where id = 1;
  insert into public.commission_history (old_percent, new_percent, old_active, new_active, changed_by)
  values (s.after_launch_percent, v_new, true, true, auth.uid())
  returning id into v_hid;
  return jsonb_build_object('history_id', v_hid, 'old', s.after_launch_percent, 'new', v_new, 'active', true);
end $$;

create or replace function public.admin_note_notification(p_history uuid, p_count integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  update public.commission_history set notified_count = greatest(coalesce(p_count, 0), 0) where id = p_history;
end $$;

revoke all on function public.admin_set_commission(numeric) from public, anon;
revoke all on function public.admin_set_after_launch_percent(numeric) from public, anon;
revoke all on function public.admin_note_notification(uuid, integer) from public, anon;
grant execute on function public.admin_set_commission(numeric) to authenticated;
grant execute on function public.admin_set_after_launch_percent(numeric) to authenticated;
grant execute on function public.admin_note_notification(uuid, integer) to authenticated;
grant execute on function public.effective_platform_percent() to anon, authenticated;

notify pgrst, 'reload schema';


-- =====================================================================
-- 25. ANTI-FRAUDE AFFILIATION
-- =====================================================================
-- =====================================================================
-- ANTI-FRAUDE AFFILIATION  (nouveau — n'ajoute que des tables, fonctions et triggers)
-- Rejouable sans risque. Aucun code existant n'est modifié : les règles s'accrochent par triggers.
-- Principe : EN CAS DE DOUTE OU D'ERREUR, la vente passe (mieux vaut laisser passer un fraudeur que bloquer un vrai client).
-- Tous les montants sont des entiers FCFA. Tout le calcul est fait ici, côté serveur.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Réglages (une seule ligne) — interrupteur général + délai de protection
-- ---------------------------------------------------------------------
create table if not exists public.fraud_settings (
  id         integer primary key default 1 check (id = 1),
  is_active  boolean not null default true,
  hold_days  integer not null default 7 check (hold_days between 0 and 60),
  updated_at timestamptz not null default now()
);
insert into public.fraud_settings (id) values (1) on conflict (id) do nothing;

-- Compte « en cours de vérification » : retraits suspendus jusqu'au déblocage manuel par l'admin
alter table public.profiles add column if not exists fraud_review boolean not null default false;

-- ---------------------------------------------------------------------
-- 2. Journal fraud_logs
-- ---------------------------------------------------------------------
create table if not exists public.fraud_logs (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references public.profiles(id) on delete set null,   -- l'acheteur
  order_id       uuid references public.orders(id) on delete cascade deferrable initially deferred,
  affiliate_id   uuid references public.profiles(id) on delete set null,
  seller_id      uuid references public.profiles(id) on delete set null,
  reason         text not null,                                             -- visible de l'admin SEULEMENT
  risk_score     integer not null check (risk_score between 0 and 100),
  action         text not null check (action in ('blocked', 'flagged', 'allowed')),
  created_at     timestamptz not null default now(),
  -- suivi admin
  transaction_id uuid references public.transactions(id) on delete cascade,
  amount         bigint not null default 0 check (amount >= 0),            -- commission concernée (FCFA)
  status         text not null default 'closed' check (status in ('open', 'validated', 'blocked', 'closed')),
  resolved_at    timestamptz,
  resolved_by    uuid references public.profiles(id) on delete set null
);
create index if not exists fraud_logs_open_idx on public.fraud_logs (created_at desc) where status = 'open';
create index if not exists fraud_logs_aff_idx  on public.fraud_logs (affiliate_id, created_at desc);
create index if not exists fraud_logs_tx_idx   on public.fraud_logs (transaction_id) where transaction_id is not null;

-- Adresses IP vues par compte (sert à la règle « plusieurs comptes, même IP en 24 h »)
create table if not exists public.account_ips (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  ip         text not null check (length(ip) between 3 and 64),
  first_seen timestamptz not null default now(),
  primary key (user_id, ip)
);
create index if not exists account_ips_ip_idx on public.account_ips (ip, first_seen);

-- RLS : personne ne lit ni n'écrit directement ; tout passe par les fonctions ci-dessous.
alter table public.fraud_settings enable row level security;
alter table public.fraud_logs     enable row level security;
alter table public.account_ips    enable row level security;
revoke all on public.fraud_settings, public.fraud_logs, public.account_ips from anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Petits outils de normalisation
-- ---------------------------------------------------------------------
-- Téléphone : on garde les 9 derniers chiffres (+237 6xx..., 6xx... et 00237... deviennent identiques). Trop court = ignoré.
create or replace function public.fraud_phone_key(p text)
returns text language sql immutable as $$
  select case when length(regexp_replace(coalesce(p, ''), '\D', '', 'g')) >= 8
              then right(regexp_replace(p, '\D', '', 'g'), 9) end
$$;

-- Email : minuscules ; pour Gmail on ignore les points et le "+alias" (a.b+x@gmail.com = ab@gmail.com).
create or replace function public.fraud_email_key(p text)
returns text language sql immutable as $$
  select case
    when p is null or position('@' in p) = 0 then null
    when lower(split_part(p, '@', 2)) in ('gmail.com', 'googlemail.com')
      then replace(split_part(split_part(lower(btrim(p)), '@', 1), '+', 1), '.', '') || '@gmail.com'
    else lower(btrim(p))
  end
$$;

create or replace function public.fraud_active()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_active from public.fraud_settings where id = 1), false)
$$;

create or replace function public.fraud_hold_days()
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((select hold_days from public.fraud_settings where id = 1), 7)
$$;

-- ---------------------------------------------------------------------
-- 4. Évaluation des règles 1 à 4 (lecture seule, aucune écriture)
--    Retour : { allowed, risk_score 0-100, reason, rules[], commission: normal|zero|hold, hold_days }
-- ---------------------------------------------------------------------
create or replace function public.fraud_assess(
  p_buyer_id    uuid,
  p_buyer_email text,
  p_buyer_phone text,
  p_seller_id   uuid,
  p_affiliate_id uuid,
  p_order_id    uuid default null,
  p_payer_phone text default null
) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_score  integer := 0;
  v_rules  text[] := '{}';
  v_reason text := '';
  v_hold   boolean := false;
  a_phone  text; a_wa text; a_email text; a_name text;
  s_phone  text; s_wa text;
  b_phone  text; b_phone2 text;
  n        integer; n24 integer; tot integer; nn integer;
begin
  -- Pas d'affilié = rien à vérifier : l'ancien calcul continue tel quel.
  if p_affiliate_id is null then
    return jsonb_build_object('allowed', true, 'risk_score', 0, 'reason', '', 'rules', '[]'::jsonb, 'commission', 'normal', 'hold_days', public.fraud_hold_days());
  end if;

  select public.fraud_phone_key(phone), public.fraud_phone_key(whatsapp), coalesce(full_name, store_name, 'Affilié')
    into a_phone, a_wa, a_name from public.profiles where id = p_affiliate_id;
  select public.fraud_email_key(email) into a_email from auth.users where id = p_affiliate_id;
  select public.fraud_phone_key(phone), public.fraud_phone_key(whatsapp) into s_phone, s_wa from public.profiles where id = p_seller_id;
  b_phone  := public.fraud_phone_key(p_buyer_phone);
  select public.fraud_phone_key(phone) into b_phone2 from public.profiles where id = p_buyer_id;

  -- RÈGLE 1 : l'affilié ne peut pas s'acheter lui-même
  if p_buyer_id is not null and p_buyer_id = p_affiliate_id then
    return jsonb_build_object('allowed', false, 'risk_score', 100, 'reason', 'Affilié = Acheteur', 'rules', '["self_buy"]'::jsonb, 'commission', 'zero', 'hold_days', public.fraud_hold_days());
  end if;
  if a_email is not null and public.fraud_email_key(p_buyer_email) = a_email then
    return jsonb_build_object('allowed', false, 'risk_score', 100, 'reason', 'Affilié = Acheteur (même email)', 'rules', '["self_buy"]'::jsonb, 'commission', 'zero', 'hold_days', public.fraud_hold_days());
  end if;
  if (a_phone is not null or a_wa is not null)
     and (b_phone in (a_phone, a_wa) or b_phone2 in (a_phone, a_wa)) then
    return jsonb_build_object('allowed', false, 'risk_score', 100, 'reason', 'Affilié = Acheteur (même téléphone)', 'rules', '["self_buy"]'::jsonb, 'commission', 'zero', 'hold_days', public.fraud_hold_days());
  end if;
  -- Numéro Mobile Money du payeur (seulement si la passerelle le fournit : Fapshi ne le donne pas aujourd'hui)
  if public.fraud_phone_key(p_payer_phone) is not null and public.fraud_phone_key(p_payer_phone) in (a_phone, a_wa) then
    return jsonb_build_object('allowed', false, 'risk_score', 100, 'reason', 'Affilié = Acheteur (même compte MoMo)', 'rules', '["self_buy"]'::jsonb, 'commission', 'zero', 'hold_days', public.fraud_hold_days());
  end if;

  -- RÈGLE 2 : le vendeur et l'affilié ne sont pas la même personne
  if p_seller_id is not null and p_seller_id = p_affiliate_id then
    return jsonb_build_object('allowed', false, 'risk_score', 100, 'reason', 'Vendeur = Affilié', 'rules', '["seller_is_affiliate"]'::jsonb, 'commission', 'zero', 'hold_days', public.fraud_hold_days());
  end if;
  if (a_phone is not null or a_wa is not null) and (s_wa in (a_phone, a_wa) or s_phone in (a_phone, a_wa)) then
    return jsonb_build_object('allowed', false, 'risk_score', 100, 'reason', 'Vendeur = Affilié (même numéro)', 'rules', '["seller_is_affiliate"]'::jsonb, 'commission', 'zero', 'hold_days', public.fraud_hold_days());
  end if;

  -- RÈGLE 3 : faux comptes / comptes multiples
  -- 3a. plus de 2 comptes avec le même numéro (celui de l'affilié ou celui de l'acheteur)
  select greatest(
           coalesce((select count(*) from public.profiles where a_phone is not null and public.fraud_phone_key(phone) = a_phone), 0),
           coalesce((select count(*) from public.profiles where coalesce(b_phone, b_phone2) is not null and public.fraud_phone_key(phone) = coalesce(b_phone, b_phone2)), 0))
    into n;
  if n > 2 then v_score := v_score + 40; v_rules := array_append(v_rules, 'same_phone'); v_reason := v_reason || format('%s comptes avec le même téléphone; ', n); end if;

  -- 3b. plus de 3 comptes vus sur la même IP en 24 h (IP de l'affilié ou de l'acheteur)
  select coalesce(max(c), 0) into n from (
    select count(distinct x.user_id) as c
      from public.account_ips mine
      join public.account_ips x on x.ip = mine.ip and x.first_seen > now() - interval '24 hours'
     where mine.user_id in (p_affiliate_id, p_buyer_id)
     group by mine.ip) q;
  if n > 3 then v_score := v_score + 30; v_rules := array_append(v_rules, 'same_ip'); v_reason := v_reason || format('%s comptes sur la même IP en 24 h; ', n); end if;

  -- 3b-bis. acheteurs SANS compte : plus de 3 numéros différents depuis le même appareil/IP en 24 h (appareil suspect)
  if p_order_id is not null then
    select count(distinct public.fraud_phone_key(o2.phone)) into n
      from public.orders o1 join public.orders o2 on o2.client_ip = o1.client_ip and o2.created_at > now() - interval '24 hours'
     where o1.id = p_order_id and o1.client_ip is not null and o2.phone is not null;
    if coalesce(n, 0) > 3 then v_score := v_score + 30; v_rules := array_append(v_rules, 'same_device'); v_reason := v_reason || format('%s numéros différents depuis le même appareil en 24 h; ', n); end if;
  end if;

  -- 3c. plus de 5 commandes du même acheteur vers le même vendeur en 24 h
  select count(*) into n from public.orders
   where seller_id = p_seller_id and created_at > now() - interval '24 hours'
     and id is distinct from p_order_id
     and ((p_buyer_id is not null and buyer_id = p_buyer_id) or lower(buyer_email) = lower(coalesce(p_buyer_email, ''))
          or (b_phone is not null and public.fraud_phone_key(phone) = b_phone));
  if n + 1 > 5 then v_score := v_score + 30; v_rules := array_append(v_rules, 'repeat_orders'); v_reason := v_reason || format('%s commandes même acheteur/vendeur en 24 h; ', n + 1); end if;

  -- RÈGLE 4 : vélocité suspecte (sur les ventes déjà PAYÉES de cet affilié)
  select count(*) into n from public.transactions
   where affiliate_id = p_affiliate_id and status = 'paid' and paid_at > now() - interval '1 hour';
  if n > 10 then
    v_score := v_score + 50; v_hold := true; v_rules := array_append(v_rules, 'velocity_1h');
    v_reason := format('Activité suspecte : Affilié %s - %s ventes en 1h; ', a_name, n) || v_reason;
  end if;

  select count(*) into n24 from public.transactions
   where affiliate_id = p_affiliate_id and status = 'paid' and paid_at > now() - interval '24 hours';
  if n24 > 30 then
    select count(*) filter (where p.created_at > now() - interval '24 hours'), count(*)
      into nn, tot
      from public.transactions t join public.orders o on o.id = t.order_id left join public.profiles p on p.id = o.buyer_id
     where t.affiliate_id = p_affiliate_id and t.status = 'paid' and t.paid_at > now() - interval '24 hours';
    if tot > 0 and nn * 100 >= tot * 80 then
      v_score := v_score + 50; v_hold := true; v_rules := array_append(v_rules, 'velocity_24h_new_accounts');
      v_reason := v_reason || format('%s ventes en 24h dont %s%% de comptes neufs; ', n24, (nn * 100) / tot);
    end if;
  end if;

  select count(*) into n from public.transactions
   where seller_id = p_seller_id and affiliate_id = p_affiliate_id and status = 'paid' and paid_at > now() - interval '24 hours';
  if n >= 50 and not exists (select 1 from public.transactions where seller_id = p_seller_id and status = 'paid' and paid_at <= now() - interval '24 hours') then
    v_score := v_score + 50; v_hold := true; v_rules := array_append(v_rules, 'seller_burst');
    v_reason := v_reason || format('vendeur passé de 0 à %s ventes en 1 jour avec le même affilié; ', n);
  end if;

  v_score := least(v_score, 100);
  if v_score >= 70 then v_hold := true; end if;

  return jsonb_build_object(
    'allowed', true,
    'risk_score', v_score,
    'reason', rtrim(v_reason, '; '),
    'rules', to_jsonb(v_rules),
    'commission', case when v_hold then 'hold' else 'normal' end,
    'hold_days', public.fraud_hold_days());
end $$;

-- ---------------------------------------------------------------------
-- 5. Accroche n°1 : à la création d'une commande (règles 1 et 2)
--    Affilié = acheteur ou vendeur  =>  on retire l'affilié de la commande : commission 0, la vente continue normalement.
-- ---------------------------------------------------------------------
create or replace function public.fraud_on_order_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  begin
    if new.affiliate_id is null or not public.fraud_active() then return new; end if;
    r := public.fraud_assess(new.buyer_id, new.buyer_email, new.phone, new.seller_id, new.affiliate_id, new.id, null);
    if r->>'commission' = 'zero' then
      insert into public.fraud_logs (user_id, order_id, affiliate_id, seller_id, reason, risk_score, action, amount, status)
      values (new.buyer_id, new.id, new.affiliate_id, new.seller_id, r->>'reason', (r->>'risk_score')::int, 'blocked',
              coalesce(new.unit_price * new.quantity * coalesce(new.affiliate_percent, 0) / 100, 0), 'closed');
      new.affiliate_id := null;
      new.affiliate_percent := null;
    end if;
  exception when others then
    -- Panne de l'anti-fraude : on laisse passer, on ne bloque jamais un vrai client.
    raise warning 'anti-fraude (commande) ignoré : %', sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists fraud_orders_before_insert on public.orders;
create trigger fraud_orders_before_insert before insert on public.orders
  for each row execute function public.fraud_on_order_insert();

-- ---------------------------------------------------------------------
-- 6. Accroche n°2 : quand le paiement est confirmé (règles 3 et 4) — mise en attente manuelle
--    On ne touche pas aux portefeuilles : on repousse seulement la libération (release_at = « jamais »)
--    jusqu'à la décision de l'admin.
-- ---------------------------------------------------------------------
create or replace function public.fraud_on_payment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r jsonb; o public.orders%rowtype; v_name text; v_flags integer;
begin
  begin
    if not public.fraud_active() or new.affiliate_id is null or coalesce(new.affiliate_fee, 0) <= 0 then return new; end if;
    select * into o from public.orders where id = new.order_id;
    r := public.fraud_assess(o.buyer_id, o.buyer_email, o.phone, new.seller_id, new.affiliate_id, o.id, null);
    if (r->>'risk_score')::int = 0 then return new; end if;

    if r->>'commission' = 'hold' then
      insert into public.fraud_logs (user_id, order_id, affiliate_id, seller_id, reason, risk_score, action, transaction_id, amount, status)
      values (o.buyer_id, o.id, new.affiliate_id, new.seller_id,
              coalesce(nullif(r->>'reason', ''), 'Activité suspecte'), (r->>'risk_score')::int, 'flagged', new.id, new.affiliate_fee, 'open');
      update public.transactions set release_at = 'infinity' where id = new.id;
      -- 3 alertes en 30 jours => retraits suspendus, compte « en cours de vérification »
      select count(*) into v_flags from public.fraud_logs
       where affiliate_id = new.affiliate_id and action = 'flagged' and created_at > now() - interval '30 days';
      if v_flags >= 3 then update public.profiles set fraud_review = true where id = new.affiliate_id; end if;
    else
      insert into public.fraud_logs (user_id, order_id, affiliate_id, seller_id, reason, risk_score, action, transaction_id, amount, status)
      values (o.buyer_id, o.id, new.affiliate_id, new.seller_id,
              coalesce(nullif(r->>'reason', ''), 'Signal faible'), (r->>'risk_score')::int, 'allowed', new.id, new.affiliate_fee, 'closed');
    end if;
  exception when others then
    raise warning 'anti-fraude (paiement) ignoré : %', sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists fraud_tx_after_paid on public.transactions;
create trigger fraud_tx_after_paid after update of status on public.transactions
  for each row when (old.status is distinct from 'paid' and new.status = 'paid')
  execute function public.fraud_on_payment();

-- ---------------------------------------------------------------------
-- 7. RÈGLE 5 : délai de protection obligatoire avant libération des fonds
--    PHYSIQUE : aucune libération avant payé_le + 7 jours (réglable). DIGITAL : 24 h (sauf vente suspecte : bloquée jusqu'à décision de l'admin). Un remboursement / litige dans ce délai
--    annule la commission (fonctions existantes : les fonds sont encore « en attente »).
--    Les ventes déjà libérées, et le paiement à la livraison (cash), ne sont pas concernés.
-- ---------------------------------------------------------------------
create or replace function public.fraud_clamp_release()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_physical boolean;
begin
  begin
    if new.status = 'paid' and new.released_at is null and new.release_at is not null
       and new.release_at <> 'infinity' and public.fraud_active() then
      if exists (select 1 from public.fraud_logs where transaction_id = new.id and status = 'open') then
        new.release_at := 'infinity';                 -- vente suspecte : en attente de décision de l'admin (digital ou physique)
      else
        -- Délais V3 : DIGITAL = 24 h (déjà posé par la vente) ; PHYSIQUE = jamais avant payé_le + 7 jours.
        select p.product_type = 'physical' into v_physical from public.products p where p.id = new.product_id;
        if coalesce(v_physical, false) then
          new.release_at := greatest(new.release_at, coalesce(new.paid_at, now()) + make_interval(days => public.fraud_hold_days()));
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'anti-fraude (délai) ignoré : %', sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists fraud_tx_before_release on public.transactions;
create trigger fraud_tx_before_release before update of release_at, status on public.transactions
  for each row when (new.release_at is distinct from old.release_at or old.status is distinct from new.status)
  execute function public.fraud_clamp_release();

-- Retraits : refusés tant que le compte est « en cours de vérification »
create or replace function public.fraud_block_withdrawal()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.profiles where id = new.user_id and fraud_review) then
    raise exception 'compte_en_verification';
  end if;
  return new;
end $$;

drop trigger if exists fraud_withdrawals_before_insert on public.withdrawals;
create trigger fraud_withdrawals_before_insert before insert on public.withdrawals
  for each row execute function public.fraud_block_withdrawal();

-- ---------------------------------------------------------------------
-- 8. Enregistrer l'IP d'un compte (appelée côté serveur, une fois par compte et par IP)
-- ---------------------------------------------------------------------
create or replace function public.fraud_record_ip(p_ip text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_ip is null or length(btrim(p_ip)) < 3 then return; end if;
  insert into public.account_ips (user_id, ip) values (auth.uid(), left(btrim(p_ip), 64)) on conflict do nothing;
end $$;

-- ---------------------------------------------------------------------
-- 9. Ce que voit l'utilisateur (jamais la règle exacte)
-- ---------------------------------------------------------------------
create or replace function public.my_fraud_notice()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_held integer; v_amt bigint; v_cancel integer; v_days integer; v_review boolean;
begin
  if v_uid is null then return jsonb_build_object('held', 0, 'cancelled', false, 'review', false, 'days_left', null); end if;
  select coalesce(fraud_review, false) into v_review from public.profiles where id = v_uid;
  select count(*), coalesce(sum(l.amount), 0) into v_held, v_amt
    from public.fraud_logs l where l.status = 'open' and (l.affiliate_id = v_uid or l.seller_id = v_uid);
  select count(*) into v_cancel from public.fraud_logs l
   where l.status = 'blocked' and l.affiliate_id = v_uid and l.resolved_at > now() - interval '30 days';
  -- jours restants avant la première libération (utile pour griser « Demander un retrait »)
  select ceil(extract(epoch from (min(t.release_at) - now())) / 86400)::int into v_days
    from public.transactions t
   where t.status = 'paid' and t.released_at is null and t.release_at is not null and t.release_at <> 'infinity'
     and (t.seller_id = v_uid or t.affiliate_id = v_uid);
  return jsonb_build_object(
    'held', v_held, 'held_amount', v_amt, 'cancelled', v_cancel > 0, 'review', coalesce(v_review, false),
    'days_left', case when public.fraud_active() and v_days is not null then greatest(v_days, 1) end,
    'hold_days', public.fraud_hold_days());
end $$;

-- ---------------------------------------------------------------------
-- 10. Fonctions ADMIN (is_admin() obligatoire)
-- ---------------------------------------------------------------------
create or replace function public.admin_fraud_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  return jsonb_build_object(
    'active', public.fraud_active(),
    'hold_days', public.fraud_hold_days(),
    'blocked_today', (select count(*) from public.fraud_logs
                       where (action = 'blocked' or status = 'blocked') and coalesce(resolved_at, created_at) >= date_trunc('day', now())),
    'pending', (select count(*) from public.fraud_logs where status = 'open'),
    'saved_total', (select coalesce(sum(amount), 0) from public.fraud_logs where action = 'blocked' or status = 'blocked'),
    'under_review', (select count(*) from public.profiles where fraud_review));
end $$;

create or replace function public.admin_fraud_alerts(p_limit integer default 100)
returns table (id uuid, created_at timestamptz, affiliate_id uuid, affiliate_name text, seller_name text, reason text,
               risk_score integer, amount bigint, action text, status text, transaction_id uuid, affiliate_review boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  return query
    select l.id, l.created_at, l.affiliate_id,
           coalesce(a.full_name, a.store_name, '—'), coalesce(s.full_name, s.store_name, '—'),
           l.reason, l.risk_score, l.amount, l.action, l.status, l.transaction_id, coalesce(a.fraud_review, false)
      from public.fraud_logs l
      left join public.profiles a on a.id = l.affiliate_id
      left join public.profiles s on s.id = l.seller_id
     where l.action <> 'allowed' or l.risk_score >= 40
     order by (l.status = 'open') desc, l.created_at desc
     limit least(greatest(p_limit, 1), 300);
end $$;

-- Remet la libération d'une vente dans l'état normal (7 jours après le paiement ; physique non livré : à la livraison)
create or replace function public.fraud_restore_release(p_tx uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t public.transactions%rowtype; v_physical boolean; v_delivered boolean;
begin
  select * into t from public.transactions where id = p_tx for update;
  if not found or t.released_at is not null then return; end if;
  select p.product_type = 'physical' into v_physical from public.products p where p.id = t.product_id;
  select (o.status in ('delivered', 'completed') or o.buyer_confirmed_at is not null) into v_delivered from public.orders o where o.id = t.order_id;
  update public.transactions
     set release_at = case when coalesce(v_physical, false) and not coalesce(v_delivered, false) then null
                           when coalesce(v_physical, false) then coalesce(t.paid_at, now()) + make_interval(days => public.fraud_hold_days())
                           else coalesce(t.paid_at, now()) + interval '24 hours' end
   where id = p_tx;
end $$;

-- p_decision : 'validate' (commission normale, 7 jours) | 'block' (commission = 0) | 'ban' (block + compte bloqué)
create or replace function public.admin_fraud_resolve(p_log uuid, p_decision text)
returns void language plpgsql security definer set search_path = public as $$
declare l public.fraud_logs%rowtype; t public.transactions%rowtype; v_fee bigint;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_decision not in ('validate', 'block', 'ban') then raise exception 'decision_invalide'; end if;
  select * into l from public.fraud_logs where id = p_log for update;
  if not found then raise exception 'alerte_introuvable'; end if;

  if l.status = 'open' then
    if p_decision = 'validate' then
      update public.fraud_logs set status = 'validated', resolved_at = now(), resolved_by = auth.uid() where id = l.id;
    else
      -- Commission affilié annulée : elle revient au vendeur, les portefeuilles restent cohérents.
      select * into t from public.transactions where id = l.transaction_id for update;
      if found and t.status = 'paid' and t.released_at is null and coalesce(t.affiliate_fee, 0) > 0 and t.affiliate_id is not null then
        v_fee := t.affiliate_fee;
        update public.wallets set balance_pending = balance_pending - v_fee, total_earned = total_earned - v_fee, updated_at = now()
         where user_id = t.affiliate_id and balance_pending >= v_fee;
        if not found then raise exception 'portefeuille_incoherent'; end if;
        update public.wallets set balance_pending = balance_pending + v_fee, total_earned = total_earned + v_fee, updated_at = now()
         where user_id = t.seller_id;
        update public.transactions set affiliate_fee = 0, seller_amount = seller_amount + v_fee where id = t.id;
      end if;
      update public.fraud_logs set status = 'blocked', action = 'blocked', resolved_at = now(), resolved_by = auth.uid() where id = l.id;
    end if;
    if l.transaction_id is not null then perform public.fraud_restore_release(l.transaction_id); end if;
  end if;

  if p_decision = 'ban' and l.affiliate_id is not null then
    update public.profiles set is_blocked = true, fraud_review = true where id = l.affiliate_id;
  end if;
end $$;

create or replace function public.admin_fraud_unblock(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  update public.profiles set fraud_review = false where id = p_user;
end $$;

create or replace function public.admin_fraud_set_active(p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  update public.fraud_settings set is_active = p_active, updated_at = now() where id = 1;
end $$;

-- ---------------------------------------------------------------------
-- 11. Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function public.fraud_assess(uuid, text, text, uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.fraud_restore_release(uuid)                           from public, anon, authenticated;
revoke all on function public.fraud_record_ip(text)                                 from public, anon;
revoke all on function public.my_fraud_notice()                                     from public, anon;
revoke all on function public.admin_fraud_overview()                                from public, anon;
revoke all on function public.admin_fraud_alerts(integer)                           from public, anon;
revoke all on function public.admin_fraud_resolve(uuid, text)                       from public, anon;
revoke all on function public.admin_fraud_unblock(uuid)                             from public, anon;
revoke all on function public.admin_fraud_set_active(boolean)                       from public, anon;
grant execute on function public.fraud_assess(uuid, text, text, uuid, uuid, uuid, text) to service_role;
grant execute on function public.fraud_record_ip(text)             to authenticated;
grant execute on function public.my_fraud_notice()                 to authenticated;
grant execute on function public.admin_fraud_overview()            to authenticated;
grant execute on function public.admin_fraud_alerts(integer)       to authenticated;
grant execute on function public.admin_fraud_resolve(uuid, text)   to authenticated;
grant execute on function public.admin_fraud_unblock(uuid)         to authenticated;
grant execute on function public.admin_fraud_set_active(boolean)   to authenticated;

notify pgrst, 'reload schema';


-- =====================================================================
-- 26. GROSSISTES, INTERNATIONAL, LITIGES
-- =====================================================================
-- =====================================================================
-- MODULES 7, 8, 10 : GROSSISTES, INTERNATIONAL, LITIGES (+ vue payouts, product_locations)
-- Rejouable sans risque. N'efface ni ne modifie aucune donnée existante.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. GROSSISTES
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists wholesale_verified boolean not null default false;   -- badge « Grossiste Vérifié » (jamais modifiable par l'utilisateur)

create table if not exists public.wholesale_applications (
  user_id         uuid primary key references public.profiles(id) on delete cascade,
  cni_path        text not null,            -- bucket privé "wholesale"
  shop_photo_path text not null,
  whatsapp        text not null,
  status          text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at      timestamptz not null default now(),
  reviewed_at     timestamptz,
  reviewed_by     uuid references public.profiles(id) on delete set null
);

create table if not exists public.wholesale_products (
  product_id            uuid primary key references public.products(id) on delete cascade,
  seller_id             uuid not null references public.profiles(id) on delete cascade,
  min_quantity_10_price bigint not null check (min_quantity_10_price >= 100),   -- prix unitaire à partir de 10 pièces
  min_quantity_50_price bigint not null check (min_quantity_50_price >= 100),   -- prix unitaire à partir de 50 pièces
  stock_wholesale       integer not null default 0 check (stock_wholesale >= 0),
  city                  text,
  is_active             boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint wholesale_prices_decrease check (min_quantity_50_price <= min_quantity_10_price)
);
create index if not exists wholesale_products_city_idx on public.wholesale_products (city) where is_active;

create table if not exists public.wholesale_requests (
  id         uuid primary key default gen_random_uuid(),
  buyer_id   uuid references public.profiles(id) on delete set null,
  seller_id  uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity   integer not null check (quantity between 10 and 100000),
  status     text not null default 'nouveau' check (status in ('nouveau', 'contacté', 'conclu', 'annulé')),
  created_at timestamptz not null default now()
);
create index if not exists wholesale_requests_seller_idx on public.wholesale_requests (seller_id, created_at desc);

alter table public.wholesale_applications enable row level security;
alter table public.wholesale_products     enable row level security;
alter table public.wholesale_requests     enable row level security;
revoke all on public.wholesale_applications, public.wholesale_products, public.wholesale_requests from anon, authenticated;
grant select on public.wholesale_applications, public.wholesale_requests to authenticated;
grant select on public.wholesale_products to anon, authenticated;

drop policy if exists wholesale_apps_select on public.wholesale_applications;
create policy wholesale_apps_select on public.wholesale_applications for select using (user_id = auth.uid() or public.is_admin());
-- (les visiteurs ne peuvent pas lire profiles : on passe par une petite fonction sécurisée)
create or replace function public.is_verified_wholesaler(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select wholesale_verified and not is_blocked from public.profiles where id = p_user), false)
$$;
grant execute on function public.is_verified_wholesaler(uuid) to anon, authenticated;
drop policy if exists wholesale_products_select on public.wholesale_products;
create policy wholesale_products_select on public.wholesale_products for select using (
  seller_id = auth.uid() or (is_active and public.is_verified_wholesaler(seller_id)));
drop policy if exists wholesale_requests_select on public.wholesale_requests;
create policy wholesale_requests_select on public.wholesale_requests for select using (seller_id = auth.uid() or buyer_id = auth.uid() or public.is_admin());

-- Répartition d'une vente en gros : plateforme 3 %, affilié 5 % (s'il y en a un), vendeur le reste (92 % avec affilié). Entiers FCFA.
create or replace function public.wholesale_split(p_total bigint, p_has_affiliate boolean)
returns table (platform_fee bigint, affiliate_fee bigint, seller_amount bigint)
language sql immutable as $$
  select (p_total * 3) / 100,
         case when p_has_affiliate then (p_total * 5) / 100 else 0::bigint end,
         p_total - (p_total * 3) / 100 - case when p_has_affiliate then (p_total * 5) / 100 else 0::bigint end
$$;

-- Candidature « Devenir Grossiste » : CNI + photo de la boutique + WhatsApp, validée ensuite par l'admin.
create or replace function public.wholesale_apply(p_cni text, p_shop text, p_whatsapp text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_wa text := regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+]', '', 'g');
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if v_wa !~ '^\+?[0-9]{8,15}$' then raise exception 'telephone_invalide'; end if;
  if p_cni is null or p_shop is null or split_part(p_cni, '/', 1) <> v_uid::text or split_part(p_shop, '/', 1) <> v_uid::text then raise exception 'fichier_invalide'; end if;
  if exists (select 1 from public.wholesale_applications where user_id = v_uid and status = 'approved') then raise exception 'deja_grossiste'; end if;
  insert into public.wholesale_applications (user_id, cni_path, shop_photo_path, whatsapp, status)
  values (v_uid, p_cni, p_shop, v_wa, 'pending')
  on conflict (user_id) do update
    set cni_path = excluded.cni_path, shop_photo_path = excluded.shop_photo_path, whatsapp = excluded.whatsapp,
        status = 'pending', created_at = now(), reviewed_at = null, reviewed_by = null;
end $$;

create or replace function public.admin_wholesale_decide(p_user uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  update public.wholesale_applications
     set status = case when p_approve then 'approved' else 'rejected' end, reviewed_at = now(), reviewed_by = auth.uid()
   where user_id = p_user and status = 'pending';
  if not found then raise exception 'candidature_introuvable'; end if;
  update public.profiles set wholesale_verified = p_approve where id = p_user;
end $$;

-- Un grossiste vérifié met l'un de ses produits PHYSIQUES en vente en gros.
create or replace function public.wholesale_save(p_product uuid, p_p10 bigint, p_p50 bigint, p_stock integer, p_city text, p_active boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); pr public.products%rowtype;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if not coalesce((select wholesale_verified from public.profiles where id = v_uid), false) then raise exception 'grossiste_requis'; end if;
  select * into pr from public.products where id = p_product and seller_id = v_uid;
  if not found or pr.product_type <> 'physical' then raise exception 'produit_invalide'; end if;
  if p_p10 is null or p_p50 is null or p_p50 > p_p10 or p_p10 >= pr.price or p_p50 < 100 then raise exception 'prix_gros_invalide'; end if;
  if p_stock is null or p_stock < 0 then raise exception 'stock_invalide'; end if;
  insert into public.wholesale_products (product_id, seller_id, min_quantity_10_price, min_quantity_50_price, stock_wholesale, city, is_active)
  values (p_product, v_uid, p_p10, p_p50, p_stock, nullif(btrim(coalesce(p_city, '')), ''), coalesce(p_active, true))
  on conflict (product_id) do update
    set min_quantity_10_price = excluded.min_quantity_10_price, min_quantity_50_price = excluded.min_quantity_50_price,
        stock_wholesale = excluded.stock_wholesale, city = excluded.city, is_active = excluded.is_active, updated_at = now();
end $$;

-- « Demander un devis grossiste » : enregistre la demande et renvoie le WhatsApp du vendeur (connexion obligatoire : le numéro n'est pas public).
create or replace function public.wholesale_request(p_product uuid, p_quantity integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); w public.wholesale_products%rowtype; pr public.products%rowtype; v_wa text; v_unit bigint;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if p_quantity is null or p_quantity < 10 then raise exception 'quantite_invalide'; end if;
  select * into w from public.wholesale_products where product_id = p_product and is_active;
  if not found then raise exception 'produit_invalide'; end if;
  if not exists (select 1 from public.profiles where id = w.seller_id and wholesale_verified and not is_blocked) then raise exception 'produit_invalide'; end if;
  select * into pr from public.products where id = p_product;
  select coalesce(a.whatsapp, nullif(pr.whatsapp_seller, ''), p.whatsapp, p.phone) into v_wa
    from public.profiles p left join public.wholesale_applications a on a.user_id = p.id and a.status = 'approved' where p.id = w.seller_id;
  v_unit := case when p_quantity >= 50 then w.min_quantity_50_price else w.min_quantity_10_price end;
  -- anti-spam : 20 demandes par jour et par acheteur
  if (select count(*) from public.wholesale_requests where buyer_id = v_uid and created_at > now() - interval '24 hours') >= 20 then raise exception 'trop_de_demandes'; end if;
  insert into public.wholesale_requests (buyer_id, seller_id, product_id, quantity) values (v_uid, w.seller_id, p_product, p_quantity);
  return jsonb_build_object('whatsapp', v_wa, 'unit_price', v_unit, 'title', pr.title);
end $$;

create or replace function public.wholesale_set_request_status(p_request uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_status not in ('nouveau', 'contacté', 'conclu', 'annulé') then raise exception 'decision_invalide'; end if;
  update public.wholesale_requests set status = p_status where id = p_request and seller_id = auth.uid();
  if not found then raise exception 'acces_refuse'; end if;
end $$;

-- ---------------------------------------------------------------------
-- B. INTERNATIONAL : liste d'attente par pays
-- ---------------------------------------------------------------------
create table if not exists public.waitlist_international (
  id         uuid primary key default gen_random_uuid(),
  country    text not null check (country in ('GA', 'CG', 'TD', 'CI', 'SN', 'BJ', 'TG', 'BF', 'ML', 'NE', 'CF')),
  phone      text not null check (phone ~ '^\+?[0-9]{8,15}$'),
  created_at timestamptz not null default now(),
  unique (country, phone)
);
alter table public.waitlist_international enable row level security;
revoke all on public.waitlist_international from anon, authenticated;
drop policy if exists waitlist_admin_select on public.waitlist_international;
create policy waitlist_admin_select on public.waitlist_international for select using (public.is_admin());
grant select on public.waitlist_international to authenticated;

create or replace function public.join_waitlist(p_country text, p_phone text)
returns integer language plpgsql security definer set search_path = public as $$
declare v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'); v_pos integer;
begin
  if p_country is null or p_country not in ('GA', 'CG', 'TD', 'CI', 'SN', 'BJ', 'TG', 'BF', 'ML', 'NE', 'CF') then raise exception 'pays_invalide'; end if;
  if v_phone !~ '^\+?[0-9]{8,15}$' then raise exception 'telephone_invalide'; end if;
  insert into public.waitlist_international (country, phone) values (p_country, v_phone) on conflict (country, phone) do nothing;
  select count(*) into v_pos from public.waitlist_international where country = p_country;
  return v_pos;
end $$;

-- ---------------------------------------------------------------------
-- C. product_locations (ville + pays de chaque produit, tenue à jour automatiquement)
-- ---------------------------------------------------------------------
create table if not exists public.product_locations (
  product_id   uuid primary key references public.products(id) on delete cascade,
  city         text,
  country_code text not null default 'CM'
);
create index if not exists product_locations_city_idx on public.product_locations (city);
alter table public.product_locations enable row level security;
revoke all on public.product_locations from anon, authenticated;
grant select on public.product_locations to anon, authenticated;
drop policy if exists product_locations_select on public.product_locations;
create policy product_locations_select on public.product_locations for select using (true);

create or replace function public.sync_product_location()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    insert into public.product_locations (product_id, city) values (new.id, new.city)
    on conflict (product_id) do update set city = excluded.city;
  exception when others then
    raise warning 'product_locations ignoré : %', sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists products_sync_location on public.products;
create trigger products_sync_location after insert or update of city on public.products
  for each row execute function public.sync_product_location();
insert into public.product_locations (product_id, city) select id, city from public.products on conflict (product_id) do nothing;

-- ---------------------------------------------------------------------
-- D. payouts : nom demandé pour la liste des retraits (vue en lecture sur withdrawals, mêmes droits RLS)
-- ---------------------------------------------------------------------
create or replace view public.payouts with (security_invoker = true) as select * from public.withdrawals;
grant select on public.payouts to authenticated;

-- ---------------------------------------------------------------------
-- E. LITIGES (disputes)
-- ---------------------------------------------------------------------
create table if not exists public.disputes (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  buyer_id     uuid references public.profiles(id) on delete set null,
  seller_id    uuid references public.profiles(id) on delete set null,
  reason       text not null,
  photo_buyer  text,                  -- chemin dans le bucket privé "disputes"
  photo_seller text,
  status       text not null default 'en_attente' check (status in ('en_attente', 'remboursé', 'refusé')),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references public.profiles(id) on delete set null
);
create unique index if not exists disputes_one_open_per_order on public.disputes (order_id) where status = 'en_attente';
alter table public.disputes enable row level security;
revoke all on public.disputes from anon, authenticated;
grant select on public.disputes to authenticated;
drop policy if exists disputes_select on public.disputes;
create policy disputes_select on public.disputes for select using (buyer_id = auth.uid() or seller_id = auth.uid() or public.is_admin());

-- Photos de preuve d'une commande physique : le vendeur photographie le colis AVANT l'envoi, l'acheteur le produit APRÈS réception.
-- Fichiers dans le bucket privé "disputes" (dossier = id de la commande). Écriture uniquement par la fonction order_add_photo().
create table if not exists public.order_photos (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.orders(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('before_shipping', 'after_receipt')),
  path       text not null check (char_length(path) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists order_photos_order_idx on public.order_photos (order_id, kind, created_at desc);
alter table public.order_photos enable row level security;
revoke all on public.order_photos from anon, authenticated;
grant select on public.order_photos to authenticated;
drop policy if exists order_photos_select on public.order_photos;
create policy order_photos_select on public.order_photos for select
  using (exists (select 1 from public.orders o where o.id = order_id and (o.buyer_id = auth.uid() or o.seller_id = auth.uid())) or public.is_admin());

-- Quand l'acheteur ouvre un litige (fonction existante), la fiche est créée toute seule. Une erreur ici ne bloque jamais le litige.
create or replace function public.sync_dispute_from_order()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.disputed and not coalesce(old.disputed, false) then
      insert into public.disputes (order_id, buyer_id, seller_id, reason, photo_seller, photo_buyer, guest_id, buyer_name, buyer_phone, order_code)
      values (new.id, new.buyer_id, new.seller_id, coalesce(nullif(btrim(new.dispute_reason), ''), 'Non précisé'),
              (select path from public.order_photos where order_id = new.id and kind = 'before_shipping' order by created_at desc limit 1),
              (select path from public.order_photos where order_id = new.id and kind = 'after_receipt'   order by created_at desc limit 1),
              new.guest_id, new.buyer_name, new.phone,
              (select order_code from public.transactions where order_id = new.id))
      on conflict do nothing;
    end if;
  exception when others then
    raise warning 'litige non copié : %', sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists orders_sync_dispute on public.orders;
create trigger orders_sync_dispute after update of disputed on public.orders
  for each row execute function public.sync_dispute_from_order();

insert into public.disputes (order_id, buyer_id, seller_id, reason)
  select id, buyer_id, seller_id, coalesce(nullif(btrim(dispute_reason), ''), 'Non précisé') from public.orders where disputed
  on conflict do nothing;

-- Photo (colis avant envoi côté vendeur, réception côté acheteur) : le chemin vient du bucket "disputes".
create or replace function public.dispute_attach_photo(p_order uuid, p_path text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes%rowtype;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if p_path is null or split_part(p_path, '/', 1) <> p_order::text then raise exception 'fichier_invalide'; end if;
  select * into d from public.disputes where order_id = p_order and status = 'en_attente' for update;
  if not found then raise exception 'litige_introuvable'; end if;
  if d.buyer_id = v_uid then update public.disputes set photo_buyer = p_path where id = d.id;
  elsif d.seller_id = v_uid then update public.disputes set photo_seller = p_path where id = d.id;
  else raise exception 'acces_refuse'; end if;
end $$;

-- Le vendeur joint la photo du colis avant l'envoi ; l'acheteur joint la photo du produit reçu. Max 5 photos par commande et par type.
create or replace function public.order_add_photo(p_order uuid, p_path text)
returns text language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); o public.orders%rowtype; v_kind text;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if p_path is null or split_part(p_path, '/', 1) <> p_order::text or char_length(p_path) > 300 then raise exception 'fichier_invalide'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'commande_introuvable'; end if;
  if o.delivery_method is null then raise exception 'commande_non_physique'; end if;
  if o.seller_id = v_uid then
    if o.status not in ('pending', 'confirmed', 'shipped', 'ready_for_pickup') then raise exception 'photo_trop_tard'; end if;
    v_kind := 'before_shipping';
  elsif o.buyer_id = v_uid then
    if o.status not in ('shipped', 'ready_for_pickup', 'delivered', 'completed') then raise exception 'photo_trop_tot'; end if;
    v_kind := 'after_receipt';
  else
    raise exception 'acces_refuse';
  end if;
  if (select count(*) from public.order_photos where order_id = p_order and kind = v_kind) >= 5 then raise exception 'trop_de_photos'; end if;
  insert into public.order_photos (order_id, user_id, kind, path) values (p_order, v_uid, v_kind, p_path);
  -- si un litige est déjà ouvert, la photo est aussi attachée à sa fiche
  if v_kind = 'before_shipping' then update public.disputes set photo_seller = p_path where order_id = p_order and status = 'en_attente';
  else update public.disputes set photo_buyer = p_path where order_id = p_order and status = 'en_attente'; end if;
  return v_kind;
end $$;
revoke all on function public.order_add_photo(uuid, text) from public, anon;
grant execute on function public.order_add_photo(uuid, text) to authenticated;

-- p_decision : 'refund' (remboursement de l'acheteur) | 'reject' (litige refusé, le vendeur est payé)
create or replace function public.admin_dispute_decide(p_dispute uuid, p_decision text)
returns void language plpgsql security definer set search_path = public as $$
declare d public.disputes%rowtype; v_tx uuid;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_decision not in ('refund', 'reject') then raise exception 'decision_invalide'; end if;
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.status <> 'en_attente' then raise exception 'litige_introuvable'; end if;
  if p_decision = 'refund' then
    select id into v_tx from public.transactions where order_id = d.order_id;
    perform public.admin_refund_transaction(v_tx, 'Litige : remboursé');
    update public.disputes set status = 'remboursé', resolved_at = now(), resolved_by = auth.uid() where id = d.id;
  else
    perform public.admin_resolve_dispute(d.order_id);
    update public.disputes set status = 'refusé', resolved_at = now(), resolved_by = auth.uid() where id = d.id;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- F. Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function public.wholesale_apply(text, text, text)                     from public, anon;
revoke all on function public.admin_wholesale_decide(uuid, boolean)                 from public, anon;
revoke all on function public.wholesale_save(uuid, bigint, bigint, integer, text, boolean) from public, anon;
revoke all on function public.wholesale_request(uuid, integer)                      from public, anon;
revoke all on function public.wholesale_set_request_status(uuid, text)              from public, anon;
revoke all on function public.dispute_attach_photo(uuid, text)                      from public, anon;
revoke all on function public.admin_dispute_decide(uuid, text)                      from public, anon;
revoke all on function public.join_waitlist(text, text)                             from public;
grant execute on function public.wholesale_apply(text, text, text)                  to authenticated;
grant execute on function public.admin_wholesale_decide(uuid, boolean)              to authenticated;
grant execute on function public.wholesale_save(uuid, bigint, bigint, integer, text, boolean) to authenticated;
grant execute on function public.wholesale_request(uuid, integer)                   to authenticated;
grant execute on function public.wholesale_set_request_status(uuid, text)           to authenticated;
grant execute on function public.dispute_attach_photo(uuid, text)                   to authenticated;
grant execute on function public.admin_dispute_decide(uuid, text)                   to authenticated;
grant execute on function public.join_waitlist(text, text)                          to anon, authenticated;
grant execute on function public.wholesale_split(bigint, boolean)                   to anon, authenticated;

-- ---------------------------------------------------------------------
-- G. Stockage privé : CNI / photo boutique (grossistes) et preuves de litige
-- ---------------------------------------------------------------------
do $storage2$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('wholesale', 'wholesale', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = false;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('disputes', 'disputes', false, 4194304, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = false;

  drop policy if exists wholesale_insert on storage.objects;
  create policy wholesale_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'wholesale' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists wholesale_select on storage.objects;
  create policy wholesale_select on storage.objects for select to authenticated
    using (bucket_id = 'wholesale' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

  drop policy if exists disputes_insert on storage.objects;
  create policy disputes_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'disputes' and exists (
      select 1 from public.orders o where o.id::text = (storage.foldername(name))[1] and auth.uid() in (o.buyer_id, o.seller_id)));
  drop policy if exists disputes_select on storage.objects;
  create policy disputes_select on storage.objects for select to authenticated
    using (bucket_id = 'disputes' and (public.is_admin() or exists (
      select 1 from public.orders o where o.id::text = (storage.foldername(name))[1] and auth.uid() in (o.buyer_id, o.seller_id))));
exception when others then
  raise notice 'STOCKAGE : créez à la main, dans Storage, deux buckets PRIVÉS : "wholesale" et "disputes". Détail : %', sqlerrm;
end $storage2$;

-- ---------------------------------------------------------------------
-- H. Statistiques publiques d'un vendeur (nombre de ventes + taux de satisfaction = avis de 4 étoiles ou plus). Agrégats seulement.
-- ---------------------------------------------------------------------
create or replace view public.seller_public_stats as
  select p.id as seller_id,
         coalesce((select count(*) from public.transactions t where t.seller_id = p.id and t.status = 'paid'), 0)::bigint as sales_count,
         (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where r.rating >= 4) / count(*))::int end
            from public.reviews r where r.seller_id = p.id) as satisfaction_percent
    from public.profiles p
   where not p.is_blocked;
grant select on public.seller_public_stats to anon, authenticated;

-- Nombre d'affiliés (comptes ayant un lien d'affiliation ou une commission), pour le tableau de bord admin
create or replace function public.admin_affiliate_count()
returns bigint language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  return (select count(*) from (select user_id from public.affiliate_links union select affiliate_id from public.transactions where affiliate_id is not null) q);
end $$;
revoke all on function public.admin_affiliate_count() from public, anon;
grant execute on function public.admin_affiliate_count() to authenticated;

-- =====================================================================
-- 27. CORRECTIFS DE SÉCURITÉ
-- =====================================================================

-- ---------------------------------------------------------------------
-- 27.1  CRITIQUE — droits d'écriture sur les VUES et les tables
--
-- Problème : Supabase ouvre par défaut TOUS les droits (insert/update/delete/truncate…) à anon et authenticated
-- sur tout nouvel objet du schéma public. Une vue qui lit une seule table (ex. public_profiles) est « modifiable »
-- et s'exécute avec les droits de son propriétaire : un simple visiteur pouvait donc faire DELETE sur la vue et
-- effacer des profils en contournant la RLS. On retire ces droits partout, puis on les ferme pour l'avenir.
-- ---------------------------------------------------------------------
do $priv$
declare r record;
begin
  -- Vues : lecture seule, point final.
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('v', 'm') loop
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from anon, authenticated', r.relname);
  end loop;

  -- Tables : aucun droit exotique (TRUNCATE ignore la RLS) ; les visiteurs non connectés n'écrivent nulle part.
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') loop
    execute format('revoke truncate, references, trigger on public.%I from anon, authenticated', r.relname);
    execute format('revoke insert, update, delete on public.%I from anon', r.relname);
  end loop;

  -- Séquences : jamais utilisables depuis le navigateur.
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'S' loop
    execute format('revoke all on sequence public.%I from anon, authenticated', r.relname);
  end loop;
end $priv$;

-- Les visiteurs non connectés n'ont aucune raison de lire la table profiles (la vue public_profiles suffit).
revoke select on public.profiles from anon;

-- Pour l'avenir : un nouvel objet créé dans public n'est plus ouvert d'office (chaque script accorde ce qu'il faut).
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;

-- ---------------------------------------------------------------------
-- 27.2  Fonctions internes : plus appelables depuis le navigateur
-- (elles servent aux triggers et aux fonctions « security definer » ; elles révélaient les réglages anti-fraude).
-- compute_split_for() reste publique : fonction de calcul pure, sans accès aux données.
-- ---------------------------------------------------------------------
do $fn$
declare f text;
begin
  foreach f in array array[
    'public.fraud_active()', 'public.fraud_hold_days()', 'public.fraud_block_withdrawal()', 'public.fraud_clamp_release()',
    'public.fraud_on_order_insert()', 'public.fraud_on_payment()', 'public.sync_dispute_from_order()', 'public.sync_product_location()'
  ] loop
    begin
      execute format('revoke all on function %s from public, anon, authenticated', f);
      execute format('grant execute on function %s to service_role', f);
    exception when undefined_function then null;
    end;
  end loop;
end $fn$;

-- ---------------------------------------------------------------------
-- 27.3  Limitation de débit (anti-abus) — compteur atomique, utilisé par les routes API
-- ---------------------------------------------------------------------
create table if not exists public.rate_limits (
  key          text primary key,
  window_start timestamptz not null default now(),
  hits         integer not null default 0
);
alter table public.rate_limits enable row level security;
revoke all on public.rate_limits from anon, authenticated;

-- Renvoie true si l'appel est autorisé, false s'il dépasse p_limit appels par fenêtre de p_window secondes.
create or replace function public.rate_limit_hit(p_key text, p_limit integer, p_window_seconds integer)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_hits integer;
begin
  if p_key is null or length(p_key) = 0 or p_limit is null or p_limit < 1 or p_window_seconds is null or p_window_seconds < 1 then
    return true; -- paramètres incohérents : on laisse passer plutôt que de bloquer un vrai client
  end if;
  insert into public.rate_limits as r (key, window_start, hits)
  values (left(p_key, 200), now(), 1)
  on conflict (key) do update
    set hits = case when r.window_start <= now() - make_interval(secs => p_window_seconds) then 1 else r.hits + 1 end,
        window_start = case when r.window_start <= now() - make_interval(secs => p_window_seconds) then now() else r.window_start end
  returning hits into v_hits;
  return v_hits <= p_limit;
end $$;

-- Nettoyage (appelé par la tâche planifiée) : supprime les compteurs de plus de 2 jours.
create or replace function public.purge_rate_limits()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  delete from public.rate_limits where window_start < now() - interval '2 days';
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.rate_limit_hit(text, integer, integer) from public, anon, authenticated;
revoke all on function public.purge_rate_limits() from public, anon, authenticated;
grant execute on function public.rate_limit_hit(text, integer, integer) to service_role;
grant execute on function public.purge_rate_limits() to service_role;

-- ---------------------------------------------------------------------
-- 27.4  File d'attente des emails (réessais automatiques si Resend est indisponible)
-- Réservée au serveur (service_role) : contient des liens de téléchargement et des clés de licence.
-- ---------------------------------------------------------------------
create table if not exists public.email_outbox (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null,
  to_email        text not null,
  subject         text not null,
  html            text not null,
  text_body       text,
  reply_to        text,
  status          text not null default 'pending' check (status in ('pending', 'sent', 'dead')),
  attempts        integer not null default 0,
  last_error      text,
  next_attempt_at timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  sent_at         timestamptz
);
create index if not exists email_outbox_due_idx on public.email_outbox (next_attempt_at) where status = 'pending';
alter table public.email_outbox enable row level security;
revoke all on public.email_outbox from anon, authenticated;

-- Réserve (verrou « skip locked ») jusqu'à p_limit emails à renvoyer ; décale la prochaine tentative (reprise après plantage).
create or replace function public.outbox_claim(p_limit integer default 20)
returns setof public.email_outbox language plpgsql security definer set search_path = public as $$
begin
  return query
  with due as (
    select id from public.email_outbox
     where status = 'pending' and next_attempt_at <= now()
     order by next_attempt_at
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  )
  update public.email_outbox o
     set attempts = o.attempts + 1,
         next_attempt_at = now() + interval '10 minutes'
    from due where o.id = due.id
  returning o.*;
end $$;

-- Résultat d'une tentative : envoyé, ou erreur (délai croissant 5 min → 12 h ; abandon après 6 essais).
create or replace function public.outbox_report(p_id uuid, p_ok boolean, p_error text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_ok then
    update public.email_outbox set status = 'sent', sent_at = now(), last_error = null,
           html = '[envoyé]', text_body = null  -- on ne garde pas les liens ni les clés une fois l'email parti
     where id = p_id;
  else
    update public.email_outbox
       set last_error = left(coalesce(p_error, 'erreur'), 300),
           status = case when attempts >= 6 then 'dead' else 'pending' end,
           next_attempt_at = now() + make_interval(mins => least(720, 5 * power(3, greatest(attempts - 1, 0))::int))
     where id = p_id;
  end if;
end $$;

-- Nettoyage : emails envoyés ou abandonnés depuis plus de 14 jours.
create or replace function public.purge_email_outbox()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  delete from public.email_outbox where status in ('sent', 'dead') and created_at < now() - interval '14 days';
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.outbox_claim(integer) from public, anon, authenticated;
revoke all on function public.outbox_report(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.purge_email_outbox() from public, anon, authenticated;
grant execute on function public.outbox_claim(integer) to service_role;
grant execute on function public.outbox_report(uuid, boolean, text) to service_role;
grant execute on function public.purge_email_outbox() to service_role;

-- ---------------------------------------------------------------------
-- 27.5  Téléchargements : compteur par commande (limite le partage d'un lien d'achat)
-- ---------------------------------------------------------------------
alter table public.orders add column if not exists download_count integer not null default 0;
alter table public.orders add column if not exists last_download_at timestamptz;

-- Atomique : ajoute 1 au compteur si la commande est payée et sous la limite. Renvoie l'identifiant du produit acheté, ou null.
create or replace function public.register_download(p_token uuid, p_max integer default 200)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_product uuid;
begin
  update public.orders
     set download_count = download_count + 1, last_download_at = now()
   where download_token = p_token
     and payment_status = 'paid' and status <> 'cancelled'
     and download_count < greatest(coalesce(p_max, 200), 1)
  returning product_id into v_product;
  return v_product;
end $$;
revoke all on function public.register_download(uuid, integer) from public, anon, authenticated;
grant execute on function public.register_download(uuid, integer) to service_role;

-- ---------------------------------------------------------------------
-- 27.6  Fichiers vendus : un vendeur ne peut référencer QUE ses propres fichiers de stockage
-- (sans cela, un vendeur pouvait déclarer le chemin d'un fichier d'un autre vendeur ; le serveur le signait ensuite)
-- ---------------------------------------------------------------------
create or replace function public.product_files_path_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_seller uuid;
begin
  select seller_id into v_seller from public.products where id = new.product_id;
  if v_seller is null or split_part(coalesce(new.storage_path, ''), '/', 1) <> v_seller::text then
    raise exception 'fichier_invalide';
  end if;
  return new;
end $$;
revoke all on function public.product_files_path_guard() from public, anon, authenticated;
drop trigger if exists product_files_path_guard on public.product_files;
create trigger product_files_path_guard before insert or update of storage_path, product_id on public.product_files
  for each row execute function public.product_files_path_guard();

-- Taille maximale d'un fichier vendu : 50 Mo (limite du plan gratuit Supabase). Étape protégée comme les autres buckets.
do $bk$
begin
  update storage.buckets set file_size_limit = 52428800 where id = 'deliverables' and file_size_limit is null;
exception when others then
  raise notice 'STOCKAGE : fixez à la main la taille maximale du bucket "deliverables". Détail : %', sqlerrm;
end $bk$;

-- ---------------------------------------------------------------------
-- 27.7  IP des comptes : enregistrée par le SERVEUR uniquement (une IP fournie par le navigateur serait falsifiable)
-- ---------------------------------------------------------------------
create or replace function public.fraud_record_ip_for(p_user uuid, p_ip text)
returns void language plpgsql security definer set search_path = public as $$
declare v_ip text := left(btrim(coalesce(p_ip, '')), 64);
begin
  if p_user is null or length(v_ip) < 3 then return; end if;
  -- au plus 30 IP différentes mémorisées par compte (évite de remplir la table)
  if (select count(*) from public.account_ips where user_id = p_user) >= 30 then return; end if;
  insert into public.account_ips (user_id, ip) values (p_user, v_ip) on conflict do nothing;
end $$;
revoke all on function public.fraud_record_ip_for(uuid, text) from public, anon, authenticated;
grant execute on function public.fraud_record_ip_for(uuid, text) to service_role;

-- L'ancienne version (IP envoyée par le navigateur) n'est plus appelable.
revoke all on function public.fraud_record_ip(text) from public, anon, authenticated;
grant execute on function public.fraud_record_ip(text) to service_role;

-- ---------------------------------------------------------------------
-- 27.7b Liste d'attente : liste des pays à jour (base déjà existante : on remplace la contrainte)
-- ---------------------------------------------------------------------
do $$ declare r record; begin
  for r in select conname from pg_constraint where conrelid = 'public.waitlist_international'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%country%' loop
    execute format('alter table public.waitlist_international drop constraint %I', r.conname);
  end loop;
  alter table public.waitlist_international add constraint waitlist_country_check check (country in ('GA', 'CG', 'TD', 'CI', 'SN', 'BJ', 'TG', 'BF', 'ML', 'NE', 'CF'));
end $$;

-- ---------------------------------------------------------------------
-- 27.8  Liste d'attente internationale : plafond (anti-remplissage de la table)
-- ---------------------------------------------------------------------
create or replace function public.join_waitlist(p_country text, p_phone text)
returns integer language plpgsql security definer set search_path = public as $$
declare v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'); v_pos integer;
begin
  if p_country is null or p_country not in ('GA', 'CG', 'TD', 'CI', 'SN', 'BJ', 'TG', 'BF', 'ML', 'NE', 'CF') then raise exception 'pays_invalide'; end if;
  if v_phone !~ '^\+?[0-9]{8,15}$' then raise exception 'telephone_invalide'; end if;
  select count(*) into v_pos from public.waitlist_international where country = p_country;
  if v_pos >= 20000 then raise exception 'liste_pleine'; end if;
  insert into public.waitlist_international (country, phone) values (p_country, v_phone) on conflict (country, phone) do nothing;
  select count(*) into v_pos from public.waitlist_international where country = p_country;
  return v_pos;
end $$;
revoke all on function public.join_waitlist(text, text) from public;
grant execute on function public.join_waitlist(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 27.9  Candidature grossiste : compte non bloqué et créé depuis plus de 24 h
-- ---------------------------------------------------------------------
create or replace function public.wholesale_apply(p_cni text, p_shop text, p_whatsapp text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_wa text := regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+]', '', 'g'); v_created timestamptz;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if public.is_blocked(v_uid) then raise exception 'acces_refuse'; end if;
  select created_at into v_created from public.profiles where id = v_uid;
  if v_created is null or v_created > now() - interval '24 hours' then raise exception 'compte_trop_recent'; end if;
  if v_wa !~ '^\+?[0-9]{8,15}$' then raise exception 'telephone_invalide'; end if;
  if p_cni is null or p_shop is null or split_part(p_cni, '/', 1) <> v_uid::text or split_part(p_shop, '/', 1) <> v_uid::text then raise exception 'fichier_invalide'; end if;
  if exists (select 1 from public.wholesale_applications where user_id = v_uid and status = 'approved') then raise exception 'deja_grossiste'; end if;
  insert into public.wholesale_applications (user_id, cni_path, shop_photo_path, whatsapp, status)
  values (v_uid, p_cni, p_shop, v_wa, 'pending')
  on conflict (user_id) do update
    set cni_path = excluded.cni_path, shop_photo_path = excluded.shop_photo_path, whatsapp = excluded.whatsapp,
        status = 'pending', created_at = now(), reviewed_at = null, reviewed_by = null;
end $$;
revoke all on function public.wholesale_apply(text, text, text) from public, anon;
grant execute on function public.wholesale_apply(text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 27.10  Index manquants (requêtes fréquentes du tableau de bord, du cron et des webhooks)
-- ---------------------------------------------------------------------
create index if not exists transactions_status_release_idx on public.transactions (status, release_at);
create index if not exists transactions_fapshi_id_idx on public.transactions (fapshi_trans_id);
create index if not exists product_boosts_fapshi_id_idx on public.product_boosts (fapshi_trans_id);
create index if not exists orders_download_token_idx on public.orders (download_token);

notify pgrst, 'reload schema';


-- =====================================================================
-- 28. V3 : CYCLE DE STATUT STRICT, TRACE DES MONTANTS, NETTOYAGE 30 JOURS, EMAIL DE BIENVENUE
-- =====================================================================

-- 28.1  Bases déjà installées : on autorise le statut "completed" (Terminé)
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('pending', 'confirmed', 'shipped', 'ready_for_pickup', 'delivered', 'completed', 'cancelled'));

-- 28.2  Synchronisation des statuts SANS SAUT : En attente -> Payé -> Livré -> Terminé
--       * paiement : pending -> paid | failed | expired ; failed/expired -> pending | paid ; paid -> refunded
--       * commande : pending -> confirmed -> shipped | ready_for_pickup -> delivered -> completed
--                    (produit digital : pending -> delivered, une fois payé) ; cancelled possible avant "Terminé"
--       * jamais "Livré" sans paiement (sauf paiement à la livraison déjà encaissé) ; jamais "Terminé" tant que les fonds ne sont pas libérés.
--       Le trigger refuse toute autre transition, même venant d'une fonction ou d'une erreur de code.
create or replace function public.orders_status_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  v_old int;
  v_new int;
begin
  if new.payment_status is distinct from old.payment_status then
    if not (
         (old.payment_status = 'pending' and new.payment_status in ('paid', 'failed', 'expired'))
      or (old.payment_status in ('failed', 'expired') and new.payment_status in ('pending', 'paid'))
      or (old.payment_status = 'paid' and new.payment_status = 'refunded')
    ) then
      raise exception 'transition_paiement_invalide';
    end if;
  end if;

  if new.status is distinct from old.status then
    if old.status in ('completed', 'cancelled') then raise exception 'transition_statut_invalide'; end if;
    if new.status = 'cancelled' then return new; end if;

    v_old := case old.status when 'pending' then 0 when 'confirmed' then 1 when 'shipped' then 2 when 'ready_for_pickup' then 2 when 'delivered' then 3 else 4 end;
    v_new := case new.status when 'pending' then 0 when 'confirmed' then 1 when 'shipped' then 2 when 'ready_for_pickup' then 2 when 'delivered' then 3 else 4 end;

    -- pas de retour en arrière ; pas de saut (sauf digital : pending -> delivered)
    if v_new <> v_old + 1 and not (v_old = 0 and v_new = 3 and new.delivery_method is null) then
      raise exception 'transition_statut_invalide';
    end if;
    if new.status = 'confirmed' and old.status <> 'pending' then raise exception 'transition_statut_invalide'; end if;

    -- Payé obligatoire avant toute progression (le paiement à la livraison peut avancer jusqu'à "Expédiée / Prête")
    if v_new >= 1 and old.payment_status <> 'paid'
       and not (old.payment_method = 'cod' and v_new <= 2) then
      raise exception 'transition_statut_invalide';
    end if;

    -- Terminé : seulement quand les fonds ont été libérés
    if new.status = 'completed' and not exists (
         select 1 from public.transactions t where t.order_id = new.id and t.released_at is not null) then
      raise exception 'transition_statut_invalide';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists orders_status_guard_trg on public.orders;
create trigger orders_status_guard_trg before update of status, payment_status on public.orders
  for each row execute function public.orders_status_guard();

-- Même principe pour la transaction : pending -> paid -> refunded ; review -> refunded ; jamais de retour en arrière
create or replace function public.transactions_status_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if not (
         (old.status = 'pending'  and new.status in ('paid', 'failed', 'expired', 'review'))
      or (old.status in ('failed', 'expired') and new.status in ('pending', 'paid', 'review', 'expired'))
      or (old.status = 'paid'     and new.status = 'refunded')
      or (old.status = 'review'   and new.status = 'refunded')
    ) then
      raise exception 'transition_transaction_invalide';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists transactions_status_guard_trg on public.transactions;
create trigger transactions_status_guard_trg before update of status on public.transactions
  for each row execute function public.transactions_status_guard();

-- 28.3  Nettoyage des journaux (plan gratuit Supabase 500 Mo) : tout ce qui a plus de 30 jours,
--       SAUF les alertes encore ouvertes et les preuves de manipulation de montant (gardées 180 jours).
--       (product_views / product_shares ne sont PAS purgés : ce sont de minuscules lignes qui alimentent les statistiques du tableau de bord.)
--       Appelée chaque jour par la tâche planifiée /api/cron/release-funds (vercel.json).
create or replace function public.purge_old_logs()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n_fraud bigint := 0; n_fraud_amount bigint := 0; n_ips bigint := 0; n_pay bigint := 0; n_out bigint := 0; n_rate bigint := 0;
begin
  delete from public.fraud_logs
   where created_at < now() - interval '30 days' and status <> 'open' and reason not like 'Montant différent%';
  get diagnostics n_fraud = row_count;
  delete from public.fraud_logs where created_at < now() - interval '180 days' and status <> 'open';
  get diagnostics n_fraud_amount = row_count;
  delete from public.account_ips where first_seen < now() - interval '30 days';
  get diagnostics n_ips = row_count;
  delete from public.payment_events where created_at < now() - interval '30 days';
  get diagnostics n_pay = row_count;
  begin
    n_out := public.purge_email_outbox();
  exception when others then n_out := 0;
  end;
  begin
    n_rate := public.purge_rate_limits();
  exception when others then n_rate := 0;
  end;
  return jsonb_build_object('fraud_logs', n_fraud + n_fraud_amount, 'account_ips', n_ips, 'payment_events', n_pay, 'email_outbox', n_out, 'rate_limits', n_rate);
end $$;
revoke all on function public.purge_old_logs() from public, anon, authenticated;

-- 28.4  Email de bienvenue : envoyé UNE seule fois par compte (réservation atomique, même si deux onglets se connectent en même temps)
alter table public.profiles add column if not exists welcome_sent_at timestamptz;
create or replace function public.claim_welcome_email()
returns boolean language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if auth.uid() is null then return false; end if;
  update public.profiles set welcome_sent_at = now() where id = auth.uid() and welcome_sent_at is null;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;
-- si l'envoi échoue, on libère la réservation pour réessayer à la prochaine connexion
create or replace function public.release_welcome_email()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  update public.profiles set welcome_sent_at = null where id = auth.uid();
end $$;
revoke all on function public.claim_welcome_email() from public, anon;
revoke all on function public.release_welcome_email() from public, anon;
grant execute on function public.claim_welcome_email() to authenticated;
grant execute on function public.release_welcome_email() to authenticated;

notify pgrst, 'reload schema';

-- 28.5  RLS : une politique EXPLICITE sur CHAQUE table (aucune table "fermée par oubli")
--       * journaux antifraude / réglages / IP : lisibles par l'ADMIN uniquement (jamais par l'utilisateur concerné : la raison exacte reste secrète)
--       * tables internes (limitation de débit, file d'emails) : réservées au serveur (clé service_role, qui ignore le RLS)
--       * review_extras : lue seulement à travers la vue publique product_reviews_public
drop policy if exists fraud_logs_admin_read on public.fraud_logs;
create policy fraud_logs_admin_read on public.fraud_logs for select to authenticated using (public.is_admin());
drop policy if exists fraud_settings_admin_read on public.fraud_settings;
create policy fraud_settings_admin_read on public.fraud_settings for select to authenticated using (public.is_admin());
drop policy if exists account_ips_admin_read on public.account_ips;
create policy account_ips_admin_read on public.account_ips for select to authenticated using (public.is_admin());
grant select on public.fraud_logs, public.fraud_settings, public.account_ips to authenticated;

drop policy if exists rate_limits_server_only on public.rate_limits;
create policy rate_limits_server_only on public.rate_limits for all to anon, authenticated using (false) with check (false);
drop policy if exists email_outbox_server_only on public.email_outbox;
create policy email_outbox_server_only on public.email_outbox for all to anon, authenticated using (false) with check (false);
drop policy if exists review_extras_via_view_only on public.review_extras;
create policy review_extras_via_view_only on public.review_extras for all to anon, authenticated using (false) with check (false);

notify pgrst, 'reload schema';

-- =====================================================================
-- 29. PERFORMANCE : pages d'administration en peu de requêtes (max 3 requêtes de données par page, plan gratuit Supabase)
-- =====================================================================
-- Vendeurs signalés (note moyenne < 3 étoiles) avec leur nom : une seule requête au lieu de deux. Réservé à l'admin.
create or replace function public.admin_low_rated_sellers(p_below numeric default 3, p_limit integer default 50)
returns table (seller_id uuid, seller_name text, avg_rating numeric, review_count bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  return query
    select r.seller_id, coalesce(p.store_name, p.full_name, '—'), r.avg_rating, r.review_count
      from public.seller_ratings r
      left join public.profiles p on p.id = r.seller_id
     where r.avg_rating < p_below
     order by r.avg_rating asc, r.review_count desc
     limit least(greatest(p_limit, 1), 200);
end $$;
revoke all on function public.admin_low_rated_sellers(numeric, integer) from public, anon;
grant execute on function public.admin_low_rated_sellers(numeric, integer) to authenticated;

-- Tableau de bord admin en UNE requête : chiffres clés + frais par taux + nombre d'affiliés + revenus des boosts
create or replace function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  select jsonb_build_object(
    'stats',         (select to_jsonb(s) from public.admin_stats s),
    'fees',          coalesce((select jsonb_agg(to_jsonb(f)) from public.admin_fee_summary f), '[]'::jsonb),
    'affiliates',    public.admin_affiliate_count(),
    'boost_revenue', (select coalesce(sum(amount), 0) from public.product_boosts where status = 'paid')
  ) into v;
  return v;
end $$;
revoke all on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;

-- Tableau de bord vendeur : libère les fonds échus puis renvoie portefeuille + stats par produit (1 seule requête côté page)
create or replace function public.seller_dashboard()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'non_connecte'; end if;
  perform public.release_due_funds(v_uid);
  return jsonb_build_object(
    'wallet', (select to_jsonb(w) from (select user_id, balance_pending, balance_available, total_earned, total_withdrawn from public.wallets where user_id = v_uid) w),
    'stats',  coalesce((select jsonb_agg(to_jsonb(x)) from (select product_id, title, views, sales from public.seller_product_stats where seller_id = v_uid) x), '[]'::jsonb)
  );
end $$;
revoke all on function public.seller_dashboard() from public, anon;
grant execute on function public.seller_dashboard() to authenticated;

-- =====================================================================
-- 30. V3.1 : GUEST CHECKOUT (achat sans compte pour les produits PHYSIQUES)
--   * guest_accounts : compte invité créé en arrière-plan, lié au numéro de téléphone (le client ne le voit jamais)
--   * transactions.order_code : code unique KDDF-XXXX de chaque commande physique
--   * guest_track_order / guest_confirm_delivery / guest_open_dispute : suivi, réception et litige avec Numéro + Code
--     (réservées au serveur : service_role, avec limitation de débit côté API)
--   * la fonction create_checkout_order (section 12) porte les règles : physique sans compte, digital avec compte,
--     anti-fraude par téléphone (plus de 5 commandes en 1 h avec le même numéro => bloqué)
-- =====================================================================
create table if not exists public.guest_accounts (
  id            uuid primary key default gen_random_uuid(),
  phone_key     text not null unique check (char_length(phone_key) between 8 and 9),   -- 9 derniers chiffres (voir fraud_phone_key)
  phone         text not null check (char_length(phone) between 8 and 20),
  full_name     text check (full_name is null or char_length(full_name) <= 100),
  city          text check (city is null or char_length(city) <= 80),
  district      text check (district is null or char_length(district) <= 80),
  orders_count  integer not null default 0,
  created_at    timestamptz not null default now(),
  last_order_at timestamptz
);
alter table public.guest_accounts enable row level security;
revoke all on public.guest_accounts from anon, authenticated;
grant select on public.guest_accounts to authenticated;
drop policy if exists guest_accounts_admin_select on public.guest_accounts;
create policy guest_accounts_admin_select on public.guest_accounts for select using (public.is_admin());

alter table public.orders add column if not exists guest_id uuid references public.guest_accounts(id) on delete set null;
alter table public.orders add column if not exists client_ip text check (client_ip is null or char_length(client_ip) <= 64);
create index if not exists orders_guest_idx on public.orders (guest_id) where guest_id is not null;
create index if not exists orders_phone_key_idx on public.orders (public.fraud_phone_key(phone), created_at desc) where phone is not null;
create index if not exists orders_client_ip_idx on public.orders (client_ip, created_at desc) where client_ip is not null;

alter table public.transactions add column if not exists order_code text check (order_code is null or order_code ~ '^KDDF-[0-9]{4,6}$');
create unique index if not exists transactions_order_code_key on public.transactions (order_code) where order_code is not null;

alter table public.disputes add column if not exists guest_id uuid references public.guest_accounts(id) on delete set null;
alter table public.disputes add column if not exists buyer_name text;
alter table public.disputes add column if not exists buyer_phone text;
alter table public.disputes add column if not exists order_code text;
alter table public.disputes add column if not exists buyer_photos text[] not null default '{}';

-- Code KDDF-XXXX : 4 chiffres tant qu'il y a de la place, puis 5, puis 6 (jamais de doublon : index unique).
create or replace function public.next_order_code()
returns text language plpgsql volatile security definer set search_path = public as $$
declare v_try integer := 0; v_digits integer := 4; v_code text; v_min integer; v_max integer;
begin
  loop
    v_try := v_try + 1;
    if v_try > 25 then v_digits := 5; end if;
    if v_try > 50 then v_digits := 6; end if;
    v_min := power(10, v_digits - 1)::integer;
    v_max := power(10, v_digits)::integer - 1;
    v_code := 'KDDF-' || (v_min + floor(random() * (v_max - v_min + 1))::integer)::text;
    exit when not exists (select 1 from public.transactions where order_code = v_code);
    exit when v_try >= 80;
  end loop;
  return v_code;
end $$;

-- Retrouve la commande physique d'un client avec son NUMÉRO + son CODE (aucun compte nécessaire)
create or replace function public.guest_find_order(p_phone text, p_code text)
returns uuid language sql stable security definer set search_path = public as $$
  select o.id
    from public.transactions t
    join public.orders o on o.id = t.order_id
   where t.order_code = upper(btrim(coalesce(p_code, '')))
     and o.delivery_method is not null
     and public.fraud_phone_key(p_phone) is not null
     and public.fraud_phone_key(o.phone) = public.fraud_phone_key(p_phone)
$$;

-- Suivi : En attente -> En livraison -> Livré -> Terminé
create or replace function public.guest_track_order(p_phone text, p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid := public.guest_find_order(p_phone, p_code);
  o public.orders%rowtype; t public.transactions%rowtype; v_title text; v_dispute text;
begin
  if v_id is null then return jsonb_build_object('found', false); end if;
  select * into o from public.orders where id = v_id;
  select * into t from public.transactions where order_id = v_id;
  select title into v_title from public.products where id = o.product_id;
  select status into v_dispute from public.disputes where order_id = v_id order by created_at desc limit 1;
  return jsonb_build_object(
    'found', true,
    'order_id', o.id,
    'order_code', t.order_code,
    'customer_name', o.buyer_name,
    'product_title', coalesce(v_title, 'Produit'),
    'quantity', o.quantity,
    'total_price', o.total_price,
    'delivery_method', o.delivery_method,
    'delivery_address', o.delivery_address,
    'payment_method', o.payment_method,
    'payment_status', o.payment_status,
    'status', o.status,
    'created_at', o.created_at,
    'paid_at', o.paid_at,
    'delivered_at', o.delivered_at,
    'buyer_confirmed_at', o.buyer_confirmed_at,
    'disputed', o.disputed,
    'dispute_status', v_dispute,
    'can_confirm', (o.payment_status = 'paid' and o.status in ('shipped', 'ready_for_pickup', 'delivered', 'completed')
                    and o.buyer_confirmed_at is null and not o.disputed),
    'can_dispute', (o.payment_status = 'paid' and not o.disputed and t.released_at is null and o.status <> 'cancelled')
  );
end $$;

-- « J'ai reçu mon produit » sans compte (mêmes règles que buyer_confirm_delivery)
create or replace function public.guest_confirm_delivery(p_phone text, p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid := public.guest_find_order(p_phone, p_code); o public.orders%rowtype;
begin
  if v_id is null then raise exception 'commande_introuvable'; end if;
  select * into o from public.orders where id = v_id for update;
  if o.disputed then raise exception 'litige_ouvert'; end if;
  if o.payment_status <> 'paid' or o.delivery_method is null
     or o.status not in ('shipped', 'ready_for_pickup', 'delivered', 'completed') then
    raise exception 'commande_invalide';
  end if;
  if o.buyer_confirmed_at is not null then return; end if;
  update public.orders
     set buyer_confirmed_at = now(), status = case when status = 'completed' then status else 'delivered' end, delivered_at = coalesce(delivered_at, now())
   where id = o.id;
  update public.transactions set release_at = now()
   where order_id = o.id and status = 'paid' and released_at is null;
end $$;

-- Litige sans compte : Nom + Numéro + Code + photos (jusqu'à 3, déjà envoyées dans le bucket privé "disputes", dossier = id de la commande)
create or replace function public.guest_open_dispute(p_phone text, p_code text, p_reason text, p_paths text[])
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := public.guest_find_order(p_phone, p_code); o public.orders%rowtype; v_released timestamptz; v_paths text[] := coalesce(p_paths, '{}'); x text; v_dispute uuid;
begin
  if v_id is null then raise exception 'commande_introuvable'; end if;
  select * into o from public.orders where id = v_id for update;
  if o.payment_status <> 'paid' or o.delivery_method is null then raise exception 'commande_invalide'; end if;
  if o.disputed then raise exception 'litige_deja_ouvert'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 or char_length(p_reason) > 500 then raise exception 'motif_invalide'; end if;
  if cardinality(v_paths) > 3 then raise exception 'trop_de_photos'; end if;
  foreach x in array v_paths loop
    if x is null or split_part(x, '/', 1) <> o.id::text or char_length(x) > 300 then raise exception 'fichier_invalide'; end if;
  end loop;
  select released_at into v_released from public.transactions where order_id = o.id;
  if v_released is not null then raise exception 'fonds_deja_liberes'; end if;

  update public.orders set disputed = true, disputed_at = now(), dispute_reason = btrim(p_reason) where id = o.id;
  update public.disputes
     set buyer_photos = v_paths, photo_buyer = coalesce(v_paths[1], photo_buyer)
   where order_id = o.id and status = 'en_attente'
   returning id into v_dispute;
  return v_dispute;
end $$;

-- Droits : uniquement le serveur (service_role). Jamais le navigateur directement.
revoke all on function public.next_order_code()                          from public, anon, authenticated;
revoke all on function public.guest_find_order(text, text)               from public, anon, authenticated;
revoke all on function public.guest_track_order(text, text)              from public, anon, authenticated;
revoke all on function public.guest_confirm_delivery(text, text)         from public, anon, authenticated;
revoke all on function public.guest_open_dispute(text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.next_order_code()                       to service_role;
grant execute on function public.guest_find_order(text, text)            to service_role;
grant execute on function public.guest_track_order(text, text)           to service_role;
grant execute on function public.guest_confirm_delivery(text, text)      to service_role;
grant execute on function public.guest_open_dispute(text, text, text, text[]) to service_role;

-- =====================================================================
-- 31. PAYPAL + DEVISES EN TEMPS RÉEL (V3.2)
--   * transactions.pay_currency / pay_amount / fx_rate / fx_source / fx_locked_at : montant en devise étrangère VERROUILLÉ
--     à la création de la commande PayPal (le FCFA reste la monnaie comptable : total_amount, commissions, portefeuilles)
--   * fx_rates : dernière copie des taux (secours si la source en ligne tombe ; réservée au serveur)
--   * Aucune règle de commission ni de sécurité existante n'est modifiée.
-- =====================================================================
alter table public.transactions add column if not exists pay_currency text;
alter table public.transactions add column if not exists pay_amount   numeric(14, 2);
alter table public.transactions add column if not exists fx_rate      numeric(18, 10);
alter table public.transactions add column if not exists fx_source    text;
alter table public.transactions add column if not exists fx_locked_at timestamptz;

do $$ begin
  alter table public.transactions add constraint transactions_pay_currency_chk check (pay_currency is null or pay_currency in ('EUR', 'USD', 'GBP', 'CAD'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.transactions add constraint transactions_pay_amount_chk check (pay_amount is null or pay_amount > 0);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.transactions add constraint transactions_fx_pair_chk check ((pay_currency is null) = (pay_amount is null));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.transactions add constraint transactions_fx_rate_chk check (fx_rate is null or fx_rate > 0);
exception when duplicate_object then null; end $$;

create table if not exists public.fx_rates (
  currency   text primary key check (currency in ('USD', 'GBP', 'CAD')),
  per_eur    numeric(18, 8) not null check (per_eur > 0),   -- unités de la devise pour 1 EUR (le FCFA est arrimé : 1 EUR = 655,957 FCFA)
  source     text not null,
  as_of      timestamptz not null,
  fetched_at timestamptz not null default now()
);
alter table public.fx_rates enable row level security;
revoke all on public.fx_rates from anon, authenticated;   -- uniquement le serveur (service_role)
drop policy if exists fx_rates_server_only on public.fx_rates;
create policy fx_rates_server_only on public.fx_rates for all to anon, authenticated using (false) with check (false);

notify pgrst, 'reload schema';


-- =====================================================================
-- 28. REVENUS SUPPLÉMENTAIRES
--     frais de retrait, abonnement Pro, compte exempté de commission, boosts 14/30 jours, bannières sponsorisées
--     (Ce bloc est aussi fourni seul dans supabase/historique/mise-a-jour-revenus.sql pour une base déjà en ligne : on peut le relancer sans risque.)
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
--     (Ce bloc suit le bloc 28 et est inclus dans supabase/historique/mise-a-jour-revenus.sql.)
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


-- =====================================================================
-- 30. CORRECTIFS : quantité jusqu'à 1000 (limité par le stock) et candidature grossiste pour l'administrateur
-- =====================================================================
-- 30.1  Commande : la quantité n'est plus plafonnée à 50 (le stock reste la vraie limite, vérifié ci-dessous)
alter table public.orders drop constraint if exists orders_quantity_check;
alter table public.orders add constraint orders_quantity_check check (quantity between 1 and 1000);
create or replace function public.create_checkout_order(
  p_product_id      uuid,
  p_buyer_id        uuid,
  p_email           text,
  p_name            text,
  p_quantity        integer,
  p_delivery_method text,
  p_address         text,
  p_phone           text,
  p_ref_code        text,
  p_payment_method  text default 'online',
  p_city            text default null,
  p_district        text default null,
  p_ip              text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  p            public.products%rowtype;
  v_qty        integer := coalesce(p_quantity, 1);
  v_delivery   bigint := 0;
  v_aff_id     uuid;
  v_aff_pct    integer;
  v_total      bigint;
  v_order_id   uuid;
  v_token      uuid;
  v_tx_id      uuid;
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_name       text := nullif(btrim(coalesce(p_name, '')), '');
  v_address    text := nullif(btrim(coalesce(p_address, '')), '');
  v_city       text := nullif(btrim(coalesce(p_city, '')), '');
  v_district   text := nullif(btrim(coalesce(p_district, '')), '');
  v_phone_key  text;
  v_guest      uuid;
  v_code       text;
  v_ip         text := nullif(left(btrim(coalesce(p_ip, '')), 64), '');
  v_n          integer;
  v_try        integer := 0;
begin
  select * into p from public.products where id = p_product_id and is_published and moderation_status = 'approved';
  if not found then raise exception 'produit_introuvable'; end if;
  if public.is_blocked(p.seller_id) then raise exception 'vendeur_bloque'; end if;

  p_payment_method := coalesce(p_payment_method, 'online');
  if p_payment_method not in ('online', 'cod') then raise exception 'paiement_invalide'; end if;
  -- Le paiement à la livraison est INTERDIT pour les produits digitaux (livrés tout de suite).
  if p_payment_method = 'cod' and p.product_type <> 'physical' then raise exception 'cod_interdit_digital'; end if;

  if p.product_type = 'digital' then
    -- DIGITAL : compte obligatoire pour recevoir le fichier.
    if p_buyer_id is null then raise exception 'compte_requis_digital'; end if;
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'email_invalide'; end if;
    v_qty := 1;
    p_delivery_method := null;
    v_address := null;
    p_phone := null;
    v_city := null;
    v_district := null;
  else
    -- PHYSIQUE : l'email n'est pas obligatoire. Sans email, on utilise une adresse technique (jamais utilisée pour écrire au client).
    if v_email = '' then
      v_email := 'invite-' || coalesce(public.fraud_phone_key(p_phone), 'inconnu') || '@example.com';
    elsif v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      raise exception 'email_invalide';
    end if;
    if v_qty < 1 or v_qty > 1000 then raise exception 'quantite_invalide'; end if;
    if p.stock is null or p.stock < v_qty then raise exception 'stock_insuffisant'; end if;
    if p_delivery_method is null
       or coalesce((p.delivery_options -> p_delivery_method ->> 'enabled')::boolean, false) is not true then
      raise exception 'livraison_invalide';
    end if;
    v_delivery := (p.delivery_options -> p_delivery_method ->> 'price')::bigint;
    if p_phone is null or char_length(trim(p_phone)) < 8 then raise exception 'telephone_invalide'; end if;
    v_phone_key := public.fraud_phone_key(p_phone);
    if v_phone_key is null then raise exception 'telephone_invalide'; end if;
    -- Achat sans compte : nom complet, ville et quartier obligatoires.
    if p_buyer_id is null then
      if v_name is null or char_length(v_name) < 2 then raise exception 'nom_invalide'; end if;
      if v_city is null or char_length(v_city) < 2 then raise exception 'ville_invalide'; end if;
      if v_district is null or char_length(v_district) < 2 then raise exception 'quartier_invalide'; end if;
    end if;
    -- Adresse de livraison = « Quartier, Ville » (+ repère éventuel)
    if v_city is not null and v_district is not null then
      v_address := v_district || ', ' || v_city || case when v_address is not null then ' (' || v_address || ')' else '' end;
    end if;
    if p_delivery_method <> 'pickup_douala' and char_length(coalesce(v_address, '')) < 5 then
      raise exception 'adresse_invalide';
    end if;

    -- ANTI-FRAUDE (téléphone) : plus de 5 commandes en 1 h avec le même numéro => bloqué.
    -- Si l'anti-fraude plante, la commande passe (allowed: true).
    begin
      if public.fraud_active() then
        select count(*) into v_n from public.orders
         where public.fraud_phone_key(phone) = v_phone_key and created_at > now() - interval '1 hour';
        if v_n >= 5 then
          insert into public.fraud_logs (user_id, seller_id, reason, risk_score, action, status, amount)
          values (p_buyer_id, p.seller_id,
                  format('Plus de 5 commandes en 1 h avec le même numéro (%s commandes, numéro se terminant par %s)', v_n + 1, right(v_phone_key, 3)),
                  100, 'blocked', 'closed', 0);
          return jsonb_build_object('blocked', true, 'reason', 'trop_de_commandes_numero');
        end if;
      end if;
    exception when others then
      raise warning 'anti-fraude (téléphone) ignoré : %', sqlerrm;
    end;
  end if;

  -- Affilié : code valide, produit ouvert à l'affiliation, ni le vendeur lui-même, ni l'acheteur lui-même.
  -- (pas d'affiliation sur un paiement à la livraison : la commission est prélevée sur le retrait du vendeur)
  -- Un acheteur SANS compte qui est arrivé par un lien d'affiliation (cookie 30 jours) donne la commission à l'affilié.
  if p_ref_code is not null and p.affiliate_enabled and p_payment_method = 'online' then
    select id into v_aff_id from public.profiles where referral_code = upper(trim(p_ref_code));
    if v_aff_id is not null and (v_aff_id = p.seller_id or v_aff_id is not distinct from p_buyer_id) then
      v_aff_id := null;
    end if;
    if v_aff_id is not null then v_aff_pct := p.affiliate_percent; end if;
  end if;

  v_total := p.price * v_qty + v_delivery;

  -- Compte invité en arrière-plan, lié au numéro (le client ne le voit jamais)
  if p_buyer_id is null and p.product_type = 'physical' then
    insert into public.guest_accounts (phone_key, phone, full_name, city, district, orders_count, last_order_at)
    values (v_phone_key, btrim(p_phone), v_name, v_city, v_district, 1, now())
    on conflict (phone_key) do update
      set full_name = coalesce(excluded.full_name, public.guest_accounts.full_name),
          city = coalesce(excluded.city, public.guest_accounts.city),
          district = coalesce(excluded.district, public.guest_accounts.district),
          phone = excluded.phone,
          orders_count = public.guest_accounts.orders_count + 1,
          last_order_at = now()
    returning id into v_guest;
  end if;

  insert into public.orders (
    product_id, seller_id, buyer_id, guest_id, buyer_email, buyer_name, affiliate_id, affiliate_percent,
    quantity, unit_price, delivery_method, delivery_price, total_price, delivery_address, phone, payment_method, client_ip
  ) values (
    p.id, p.seller_id, p_buyer_id, v_guest, v_email, v_name, v_aff_id, v_aff_pct,
    v_qty, p.price, p_delivery_method, v_delivery, v_total, v_address, nullif(btrim(coalesce(p_phone, '')), ''), p_payment_method, v_ip
  ) returning id, download_token into v_order_id, v_token;

  -- Cash à la livraison : le stock est réservé tout de suite (il n'y a pas de confirmation de paiement en ligne).
  if p_payment_method = 'cod' then
    update public.products set stock = stock - v_qty where id = p.id and stock >= v_qty;
    if not found then raise exception 'stock_insuffisant'; end if;
  end if;

  -- Code de suivi KDDF-XXXX pour chaque commande PHYSIQUE (unique : en cas de collision rarissime, on en tire un autre)
  loop
    v_try := v_try + 1;
    v_code := case when p.product_type = 'physical' then public.next_order_code() else null end;
    begin
      insert into public.transactions (order_id, product_id, buyer_id, seller_id, total_amount, order_code)
      values (v_order_id, p.id, p_buyer_id, p.seller_id, v_total, v_code)
      returning id into v_tx_id;
      exit;
    exception when unique_violation then
      if v_code is null or v_try >= 8 then raise; end if;
    end;
  end loop;

  return jsonb_build_object(
    'order_id', v_order_id,
    'transaction_id', v_tx_id,
    'download_token', v_token,
    'total', v_total,
    'title', p.title,
    'product_type', p.product_type,
    'payment_method', p_payment_method,
    'order_code', v_code,
    'guest', v_guest is not null
  );
end $$;

-- 30.2  Candidature grossiste : l'administrateur n'attend pas 24 h (son compte est déjà de confiance) ; les autres comptes gardent la règle des 24 h
create or replace function public.wholesale_apply(p_cni text, p_shop text, p_whatsapp text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_wa text := regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+]', '', 'g'); v_created timestamptz;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  if public.is_blocked(v_uid) then raise exception 'acces_refuse'; end if;
  select created_at into v_created from public.profiles where id = v_uid;
  if not public.is_admin() and (v_created is null or v_created > now() - interval '24 hours') then raise exception 'compte_trop_recent'; end if;
  if v_wa !~ '^\+?[0-9]{8,15}$' then raise exception 'telephone_invalide'; end if;
  if p_cni is null or p_shop is null or split_part(p_cni, '/', 1) <> v_uid::text or split_part(p_shop, '/', 1) <> v_uid::text then raise exception 'fichier_invalide'; end if;
  if exists (select 1 from public.wholesale_applications where user_id = v_uid and status = 'approved') then raise exception 'deja_grossiste'; end if;
  insert into public.wholesale_applications (user_id, cni_path, shop_photo_path, whatsapp, status)
  values (v_uid, p_cni, p_shop, v_wa, 'pending')
  on conflict (user_id) do update
    set cni_path = excluded.cni_path, shop_photo_path = excluded.shop_photo_path, whatsapp = excluded.whatsapp,
        status = 'pending', created_at = now(), reviewed_at = null, reviewed_by = null;
end $$;
revoke all on function public.wholesale_apply(text, text, text) from public, anon;
grant execute on function public.wholesale_apply(text, text, text) to authenticated;

notify pgrst, 'reload schema';


-- =====================================================================
-- 31. RETRAIT EXPRESS : supplément réglable (Admin > Commissions), la demande passe en tête de liste chez l'admin
-- =====================================================================
alter table public.commission_settings add column if not exists express_fee_percent numeric(4, 2) not null default 2 check (express_fee_percent between 0 and 10);
grant select (express_fee_percent) on public.commission_settings to anon, authenticated;
alter table public.withdrawals add column if not exists express boolean not null default false;
alter table public.withdrawals add column if not exists express_fee bigint not null default 0 check (express_fee >= 0);   -- partie « express » des frais (déjà comprise dans fee)
create index if not exists withdrawals_pending_express_idx on public.withdrawals (status, express desc, created_at);

-- L'ancienne version (3 paramètres) est remplacée par celle-ci (4e paramètre facultatif : l'ancien appel reste valable)
drop function if exists public.request_withdrawal(bigint, text, text);
create or replace function public.request_withdrawal(p_amount bigint, p_method text, p_phone text, p_express boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_id     uuid;
  v_deduct bigint := 0;
  v_base   bigint;
  v_fee    bigint := 0;
  v_fp     numeric := 1.5;
  v_fm     bigint  := 200;
  v_ep     numeric := 2;
  v_xfee   bigint  := 0;
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
  select withdrawal_fee_percent, withdrawal_fee_min, express_fee_percent into v_fp, v_fm, v_ep from public.commission_settings where id = 1;
  -- Le frais n'est PAS retiré du solde : il est simplement déduit du paiement envoyé (à payer = demandé - commission cash - frais).
  v_base := p_amount - v_deduct;
  if not coalesce((select commission_exempt from public.profiles where id = v_uid), false) then
    v_fee := least(v_base, greatest(coalesce(v_fm, 200), ceil(v_base * coalesce(v_fp, 1.5) / 100.0)::bigint));
    -- Retrait EXPRESS : supplément (pourcentage réglable) en plus des frais normaux ; la demande passe en tête de la liste de l'admin.
    if coalesce(p_express, false) then
      v_xfee := least(v_base - v_fee, ceil(v_base * coalesce(v_ep, 2) / 100.0)::bigint);
      v_fee := v_fee + v_xfee;
    end if;
  end if;

  insert into public.withdrawals (user_id, amount, method, phone_number, commission_deducted, fee, express, express_fee)
  values (v_uid, p_amount, p_method, p_phone, v_deduct, v_fee, coalesce(p_express, false), v_xfee)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.request_withdrawal(bigint, text, text, boolean) from public, anon;
grant execute on function public.request_withdrawal(bigint, text, text, boolean) to authenticated;

-- Réglage du supplément express avec les autres tarifs (5e paramètre : vide = inchangé)
drop function if exists public.admin_set_revenue_settings(numeric, integer, numeric, integer);
create or replace function public.admin_set_revenue_settings(p_pro_percent numeric, p_pro_price integer, p_fee_percent numeric, p_fee_min integer, p_express_percent numeric default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if p_pro_percent is null or p_pro_percent < 0 or p_pro_percent > 10
     or p_pro_price is null or p_pro_price < 500 or p_pro_price > 200000
     or p_fee_percent is null or p_fee_percent < 0 or p_fee_percent > 10
     or p_fee_min is null or p_fee_min < 0 or p_fee_min > 5000
     or (p_express_percent is not null and (p_express_percent < 0 or p_express_percent > 10)) then
    raise exception 'valeur_invalide';
  end if;
  update public.commission_settings
     set pro_percent = round(p_pro_percent, 2), pro_price = p_pro_price,
         withdrawal_fee_percent = round(p_fee_percent, 2), withdrawal_fee_min = p_fee_min,
         express_fee_percent = coalesce(round(p_express_percent, 2), express_fee_percent),
         updated_at = now(), updated_by_admin_id = auth.uid()
   where id = 1;
end $$;
revoke all on function public.admin_set_revenue_settings(numeric, integer, numeric, integer, numeric) from public, anon;
grant execute on function public.admin_set_revenue_settings(numeric, integer, numeric, integer, numeric) to authenticated;

notify pgrst, 'reload schema';


-- =====================================================================
-- 32. ANNONCES (cloche de notification) : l'administrateur écrit un message, les utilisateurs le voient dans la cloche
--     Lecture/écriture UNIQUEMENT par les fonctions ci-dessous (aucun accès direct aux tables).
-- =====================================================================
create table if not exists public.announcements (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(title) between 3 and 80),
  body       text not null check (char_length(body) between 3 and 500),
  audience   text not null default 'all' check (audience in ('all', 'sellers', 'pro')),   -- tous / vendeurs (au moins 1 produit) / abonnés Pro
  link       text check (link is null or (char_length(link) <= 300 and (link ~ '^/($|[^/])' or link ~ '^https://[^\s]+$'))),
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null
);
create index if not exists announcements_created_idx on public.announcements (created_at desc);

create table if not exists public.announcement_reads (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (user_id, announcement_id)
);

alter table public.announcements enable row level security;
alter table public.announcement_reads enable row level security;
revoke all on public.announcements, public.announcement_reads from anon, authenticated;
-- Politique explicite « aucun accès direct » (tout passe par les fonctions ci-dessous, qui contrôlent qui lit quoi)
drop policy if exists annonces_aucun_acces_direct on public.announcements;
create policy annonces_aucun_acces_direct on public.announcements for all using (false) with check (false);
drop policy if exists annonces_lectures_aucun_acces_direct on public.announcement_reads;
create policy annonces_lectures_aucun_acces_direct on public.announcement_reads for all using (false) with check (false);

-- Annonces visibles pour l'utilisateur connecté (30 derniers jours, non expirées, bonne audience)
create or replace function public.visible_announcements(p_uid uuid)
returns setof public.announcements language sql stable security definer set search_path = public as $$
  select a.* from public.announcements a
   where p_uid is not null
     and a.created_at > now() - interval '30 days'
     and (a.expires_at is null or a.expires_at > now())
     and (   a.audience = 'all'
          or (a.audience = 'sellers' and exists (select 1 from public.products p where p.seller_id = p_uid))
          or (a.audience = 'pro' and public.is_pro(p_uid)))
$$;
revoke all on function public.visible_announcements(uuid) from public, anon, authenticated;

create or replace function public.my_announcements(p_limit integer default 20)
returns table (id uuid, title text, body text, link text, created_at timestamptz, is_read boolean)
language sql stable security definer set search_path = public as $$
  select a.id, a.title, a.body, a.link, a.created_at,
         exists (select 1 from public.announcement_reads r where r.announcement_id = a.id and r.user_id = auth.uid()) as is_read
    from public.visible_announcements(auth.uid()) a
   order by a.created_at desc
   limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

create or replace function public.my_unread_announcements()
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::integer
    from public.visible_announcements(auth.uid()) a
   where not exists (select 1 from public.announcement_reads r where r.announcement_id = a.id and r.user_id = auth.uid())
$$;

create or replace function public.mark_announcements_read()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.announcement_reads (user_id, announcement_id)
  select auth.uid(), a.id from public.visible_announcements(auth.uid()) a
  on conflict do nothing;
end $$;

revoke all on function public.my_announcements(integer), public.my_unread_announcements(), public.mark_announcements_read() from public, anon;
grant execute on function public.my_announcements(integer), public.my_unread_announcements(), public.mark_announcements_read() to authenticated;

-- Envoi (administrateur) : titre 3-80, message 3-500, lien facultatif (/page ou https://…), durée facultative en jours (1 à 365)
create or replace function public.admin_send_announcement(p_title text, p_body text, p_audience text, p_link text, p_days integer default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_title text := btrim(coalesce(p_title, '')); v_body text := btrim(coalesce(p_body, '')); v_link text := nullif(btrim(coalesce(p_link, '')), '');
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if char_length(v_title) < 3 or char_length(v_title) > 80 or char_length(v_body) < 3 or char_length(v_body) > 500 then raise exception 'annonce_invalide'; end if;
  if p_audience is null or p_audience not in ('all', 'sellers', 'pro') then raise exception 'annonce_invalide'; end if;
  if v_link is not null and not (char_length(v_link) <= 300 and (v_link ~ '^/($|[^/])' or v_link ~ '^https://[^\s]+$')) then raise exception 'annonce_lien_invalide'; end if;
  if p_days is not null and (p_days < 1 or p_days > 365) then raise exception 'annonce_invalide'; end if;
  if (select count(*) from public.announcements where created_by = auth.uid() and created_at > now() - interval '1 hour') >= 10 then raise exception 'trop_d_annonces'; end if;
  insert into public.announcements (title, body, audience, link, expires_at, created_by)
  values (v_title, v_body, p_audience, v_link, case when p_days is null then null else now() + make_interval(days => p_days) end, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.admin_list_announcements()
returns table (id uuid, title text, body text, audience text, link text, created_at timestamptz, expires_at timestamptz, reads bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  return query
    select a.id, a.title, a.body, a.audience, a.link, a.created_at, a.expires_at,
           (select count(*) from public.announcement_reads r where r.announcement_id = a.id)
      from public.announcements a order by a.created_at desc limit 50;
end $$;

create or replace function public.admin_delete_announcement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  delete from public.announcements where id = p_id;
end $$;

revoke all on function public.admin_send_announcement(text, text, text, text, integer), public.admin_list_announcements(), public.admin_delete_announcement(uuid) from public, anon;
grant execute on function public.admin_send_announcement(text, text, text, text, integer), public.admin_list_announcements(), public.admin_delete_announcement(uuid) to authenticated;

notify pgrst, 'reload schema';


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

-- =====================================================================
-- 34. V3.9 : IDENTITÉ DES VENDEURS + ALERTES D'ERREURS (identique à supabase/mise-a-jour-identite.sql)
-- =====================================================================
-- 34.1 VÉRIFICATION D'IDENTITÉ DES VENDEURS
--   Le vendeur envoie : une vidéo ou photo de lui tenant sa carte, le recto et le verso de la carte (espace privé « identity »).
--   L'administrateur valide ou refuse. Tant que l'identité n'est pas validée, le vendeur peut préparer ses produits (brouillons)
--   mais NE PEUT PAS les publier (réglable : Admin > Commissions > « Identité obligatoire »).
-- ---------------------------------------------------------------------
create table if not exists public.identity_verifications (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  front_path    text,                       -- recto de la carte (bucket privé "identity")
  back_path     text,                       -- verso
  selfie_path   text,                       -- photo ou vidéo de la personne tenant sa carte
  selfie_kind   text not null default 'photo' check (selfie_kind in ('photo', 'video')),
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reject_reason text check (reject_reason is null or char_length(reject_reason) <= 300),
  legacy        boolean not null default false,   -- ancien vendeur déjà actif avant la V3.9 : reconnu sans nouveaux documents
  submitted_at  timestamptz not null default now(),
  reviewed_at   timestamptz,
  reviewed_by   uuid references public.profiles(id) on delete set null,
  constraint identity_files_present check (legacy or (front_path is not null and back_path is not null and selfie_path is not null))
);
create index if not exists identity_status_idx on public.identity_verifications (status, submitted_at);
alter table public.identity_verifications enable row level security;
revoke all on public.identity_verifications from anon, authenticated;
grant select on public.identity_verifications to authenticated;
drop policy if exists identity_select on public.identity_verifications;
create policy identity_select on public.identity_verifications for select using (user_id = auth.uid() or public.is_admin());
-- Aucune écriture directe : tout passe par les fonctions ci-dessous
drop policy if exists identity_aucune_ecriture on public.identity_verifications;
create policy identity_aucune_ecriture on public.identity_verifications for all using (false) with check (false);

alter table public.commission_settings add column if not exists identity_required boolean not null default true;
grant select (identity_required) on public.commission_settings to anon, authenticated;

-- Stockage privé (jamais public) : photos jusqu'à 5 Mo, vidéo jusqu'à 25 Mo
do $storage_identity$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('identity', 'identity', false, 26214400,
          array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime'])
  on conflict (id) do update set public = false, file_size_limit = 26214400,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime'];

  drop policy if exists identity_insert on storage.objects;
  create policy identity_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'identity' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists identity_select_files on storage.objects;
  create policy identity_select_files on storage.objects for select to authenticated
    using (bucket_id = 'identity' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
end $storage_identity$;

-- Interne : vrai si le vendeur peut publier (identité validée, administrateur, ou règle désactivée)
create or replace function public.is_identity_ok(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select not coalesce((select identity_required from public.commission_settings where id = 1), true)
      or coalesce((select role = 'admin' from public.profiles where id = p_user), false)
      or exists (select 1 from public.identity_verifications where user_id = p_user and status = 'approved')
$$;
revoke all on function public.is_identity_ok(uuid) from public, anon, authenticated;

-- Interne : prévient tous les administrateurs (cloche). p_dedup_minutes > 0 : pas de doublon récent avec le même titre.
create or replace function public.notify_admins(p_title text, p_body text, p_link text default null, p_dedup_minutes integer default 0)
returns boolean language plpgsql security definer set search_path = public as $$
declare a record; v_sent boolean := false;
begin
  for a in select id from public.profiles where role = 'admin' loop
    if p_dedup_minutes > 0 and exists (
      select 1 from public.user_notifications n
       where n.user_id = a.id and n.title = left(p_title, 80) and n.created_at > now() - make_interval(mins => p_dedup_minutes)
    ) then
      continue;
    end if;
    perform public.notify_user(a.id, p_title, p_body, p_link);
    v_sent := true;
  end loop;
  return v_sent;
end $$;
revoke all on function public.notify_admins(text, text, text, integer) from public, anon, authenticated;

-- Le vendeur envoie ses documents
create or replace function public.identity_submit(p_front text, p_back text, p_selfie text, p_selfie_kind text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_status text; v_prefix text;
begin
  if v_uid is null then raise exception 'connexion_requise'; end if;
  v_prefix := v_uid::text || '/';
  if p_front is null or p_back is null or p_selfie is null
     or left(p_front, length(v_prefix)) <> v_prefix or left(p_back, length(v_prefix)) <> v_prefix or left(p_selfie, length(v_prefix)) <> v_prefix
     or char_length(p_front) > 200 or char_length(p_back) > 200 or char_length(p_selfie) > 200 then
    raise exception 'identite_documents_invalides';
  end if;
  if p_selfie_kind is null or p_selfie_kind not in ('photo', 'video') then raise exception 'identite_documents_invalides'; end if;
  select status into v_status from public.identity_verifications where user_id = v_uid for update;
  if v_status = 'approved' then raise exception 'identite_deja_verifiee'; end if;
  if v_status = 'pending' then raise exception 'identite_en_attente'; end if;
  insert into public.identity_verifications (user_id, front_path, back_path, selfie_path, selfie_kind, status, reject_reason, legacy, submitted_at, reviewed_at, reviewed_by)
  values (v_uid, p_front, p_back, p_selfie, p_selfie_kind, 'pending', null, false, now(), null, null)
  on conflict (user_id) do update
    set front_path = excluded.front_path, back_path = excluded.back_path, selfie_path = excluded.selfie_path, selfie_kind = excluded.selfie_kind,
        status = 'pending', reject_reason = null, legacy = false, submitted_at = now(), reviewed_at = null, reviewed_by = null;
  perform public.notify_admins('Vérification d''identité à traiter', 'Un vendeur a envoyé sa carte d''identité : ouvrez Admin > Identité.', '/admin/identite');
end $$;
revoke all on function public.identity_submit(text, text, text, text) from public, anon;
grant execute on function public.identity_submit(text, text, text, text) to authenticated;

-- État de ma vérification : none / pending / approved / rejected (+ motif du refus)
create or replace function public.my_identity()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object('status', status, 'reason', reject_reason, 'legacy', legacy) from public.identity_verifications where user_id = auth.uid()),
    jsonb_build_object('status', 'none', 'reason', null, 'legacy', false))
$$;
revoke all on function public.my_identity() from public, anon;
grant execute on function public.my_identity() to authenticated;

-- Administrateur : demandes en attente (les plus anciennes d'abord)
create or replace function public.admin_identity_list()
returns table (user_id uuid, full_name text, store_name text, phone text, whatsapp text, city text, front_path text, back_path text, selfie_path text, selfie_kind text, submitted_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  return query
    select v.user_id, p.full_name, p.store_name, p.phone, p.whatsapp, p.city, v.front_path, v.back_path, v.selfie_path, v.selfie_kind, v.submitted_at
      from public.identity_verifications v join public.profiles p on p.id = v.user_id
     where v.status = 'pending' order by v.submitted_at limit 50;
end $$;
revoke all on function public.admin_identity_list() from public, anon;
grant execute on function public.admin_identity_list() to authenticated;

-- Administrateur : valider ou refuser (un motif est obligatoire pour un refus). Valider donne aussi le badge « Vendeur vérifié ».
create or replace function public.admin_identity_decide(p_user uuid, p_approve boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  if not coalesce(p_approve, false) and (v_reason is null or char_length(v_reason) < 3 or char_length(v_reason) > 300) then raise exception 'motif_requis'; end if;
  update public.identity_verifications
     set status = case when p_approve then 'approved' else 'rejected' end,
         reject_reason = case when p_approve then null else v_reason end,
         reviewed_at = now(), reviewed_by = auth.uid()
   where user_id = p_user and status = 'pending';
  if not found then raise exception 'demande_introuvable'; end if;
  if p_approve then
    update public.profiles set is_verified = true where id = p_user;
    perform public.notify_user(p_user, 'Identité validée', 'Votre identité est vérifiée : vous pouvez publier vos produits.', '/dashboard/products');
  else
    perform public.notify_user(p_user, 'Identité refusée', 'Motif : ' || v_reason || '. Vous pouvez envoyer de nouveaux documents.', '/dashboard/verification');
  end if;
end $$;
revoke all on function public.admin_identity_decide(uuid, boolean, text) from public, anon;
grant execute on function public.admin_identity_decide(uuid, boolean, text) to authenticated;

-- Garde de publication : impossible de PUBLIER sans identité validée (les brouillons restent possibles)
create or replace function public.products_identity_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not new.is_published then return new; end if;
  if tg_op = 'UPDATE' and old.is_published then return new; end if;     -- déjà publié : modification normale
  if not public.is_identity_ok(new.seller_id) then raise exception 'identite_requise'; end if;
  return new;
end $$;
revoke all on function public.products_identity_guard() from public, anon, authenticated;
drop trigger if exists products_identity_trg on public.products;
create trigger products_identity_trg before insert or update of is_published on public.products
  for each row execute function public.products_identity_guard();

-- Interrupteur administrateur (Admin > Commissions)
create or replace function public.admin_set_identity_required(p_required boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  update public.commission_settings set identity_required = coalesce(p_required, true) where id = 1;
end $$;
revoke all on function public.admin_set_identity_required(boolean) from public, anon;
grant execute on function public.admin_set_identity_required(boolean) to authenticated;

-- Anciens vendeurs (déjà un produit publié, une vente ou le badge) : reconnus automatiquement, pour ne pas bloquer le site en ligne.
-- L'administrateur peut toujours les contrôler à la main (Admin > Validation).
insert into public.identity_verifications (user_id, status, legacy, selfie_kind, reviewed_at)
select p.id, 'approved', true, 'photo', now()
  from public.profiles p
 where p.role <> 'admin'
   and (p.is_verified
        or exists (select 1 from public.products x where x.seller_id = p.id and x.is_published)
        or exists (select 1 from public.transactions t where t.seller_id = p.id and t.status = 'paid'))
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------
-- 34.2 ALERTES D'ERREURS POUR L'ADMINISTRATEUR
--   Appelée par /api/errors et par le paiement : crée UNE alerte dans la cloche des administrateurs (au plus une toutes les 30 minutes)
--   et indique au serveur s'il doit aussi envoyer l'email d'alerte (même limite : pas de déluge d'emails).
-- ---------------------------------------------------------------------
create or replace function public.alert_admins_error(p_message text, p_url text default null)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  return public.notify_admins('Erreur sur le site', left(coalesce(nullif(btrim(p_message), ''), 'erreur inconnue'), 200) || coalesce(' (' || p_url || ')', ''), '/admin/erreurs', 30);
end $$;
revoke all on function public.alert_admins_error(text, text) from public, anon, authenticated;
grant execute on function public.alert_admins_error(text, text) to service_role;

-- ---------------------------------------------------------------------
-- 34.3 PROTECTION DES COMPTES : 2FA (facultative) et TÉLÉPHONE VÉRIFIÉ
--   - La 2FA (application d'authentification) est gérée par Supabase Auth (TOTP). L'utilisateur l'active quand il veut (page /securite).
--   - Dès qu'un compte l'a activée, la base REFUSE les actions d'administrateur et les demandes de retrait faites avec une session
--     « mot de passe seul » : un voleur de mot de passe ne peut donc ni administrer le site ni retirer l'argent.
--   - Le téléphone est confirmé par SMS (Supabase Auth, fournisseur SMS à activer). Exiger un téléphone confirmé pour publier est
--     réglable (Admin > Commissions) ; désactivé par défaut tant qu'un fournisseur SMS n'est pas configuré.
-- ---------------------------------------------------------------------
create or replace function public.mfa_ok()
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return true; end if;                                   -- serveur (clé service) : pas de session utilisateur
  if coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then return true; end if;      -- session déjà confirmée par le code à 6 chiffres
  return not exists (select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified');
exception when others then
  return true;   -- en cas de problème technique, on ne bloque jamais le site (la 2FA reste exigée par les pages)
end $$;
revoke all on function public.mfa_ok() from public, anon, authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') and public.mfa_ok();
$$;

create or replace function public.withdrawals_mfa_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.mfa_ok() then raise exception 'verification_2fa_requise'; end if;
  return new;
end $$;
revoke all on function public.withdrawals_mfa_guard() from public, anon, authenticated;
drop trigger if exists withdrawals_mfa_trg on public.withdrawals;
create trigger withdrawals_mfa_trg before insert on public.withdrawals
  for each row execute function public.withdrawals_mfa_guard();

alter table public.commission_settings add column if not exists phone_required boolean not null default false;
grant select (phone_required) on public.commission_settings to anon, authenticated;

-- Téléphone confirmé par SMS ? (lecture de auth.users, jamais exposée en direct)
create or replace function public.is_phone_ok(p_user uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce((select phone_required from public.commission_settings where id = 1), false) then return true; end if;
  if coalesce((select role = 'admin' from public.profiles where id = p_user), false) then return true; end if;
  return exists (select 1 from auth.users where id = p_user and phone_confirmed_at is not null);
exception when others then
  return true;
end $$;
revoke all on function public.is_phone_ok(uuid) from public, anon, authenticated;

create or replace function public.my_phone()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_phone text; v_ok timestamptz;
begin
  if auth.uid() is null then return jsonb_build_object('verified', false, 'phone', null); end if;
  select u.phone, u.phone_confirmed_at into v_phone, v_ok from auth.users u where u.id = auth.uid();
  return jsonb_build_object('verified', v_ok is not null, 'phone', case when v_ok is not null then v_phone else null end);
exception when others then
  return jsonb_build_object('verified', false, 'phone', null);
end $$;
revoke all on function public.my_phone() from public, anon;
grant execute on function public.my_phone() to authenticated;

-- La garde de publication contrôle maintenant l'identité ET (si l'administrateur l'exige) le téléphone confirmé
create or replace function public.products_identity_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not new.is_published then return new; end if;
  if tg_op = 'UPDATE' and old.is_published then return new; end if;     -- déjà publié : modification normale
  if not public.is_identity_ok(new.seller_id) then raise exception 'identite_requise'; end if;
  if not public.is_phone_ok(new.seller_id) then raise exception 'telephone_non_verifie'; end if;
  return new;
end $$;

create or replace function public.admin_set_phone_required(p_required boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  update public.commission_settings set phone_required = coalesce(p_required, false) where id = 1;
end $$;
revoke all on function public.admin_set_phone_required(boolean) from public, anon;
grant execute on function public.admin_set_phone_required(boolean) to authenticated;

-- Administrateur : état de sécurité d'un vendeur (identité, 2FA, téléphone) pour la liste Admin > Identité
create or replace function public.admin_security_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acces_refuse'; end if;
  begin
    return jsonb_build_object(
      'identity_pending', (select count(*) from public.identity_verifications where status = 'pending'),
      'identity_approved', (select count(*) from public.identity_verifications where status = 'approved' and not legacy),
      'identity_rejected', (select count(*) from public.identity_verifications where status = 'rejected'),
      'sellers_without_identity', (select count(distinct p.seller_id) from public.products p where p.is_published and not exists (select 1 from public.identity_verifications v where v.user_id = p.seller_id and v.status = 'approved')),
      'phones_confirmed', (select count(*) from auth.users where phone_confirmed_at is not null),
      'mfa_enabled', (select count(distinct user_id) from auth.mfa_factors where status = 'verified')
    );
  exception when others then
    return jsonb_build_object('identity_pending', (select count(*) from public.identity_verifications where status = 'pending'));
  end;
end $$;
revoke all on function public.admin_security_overview() from public, anon;
grant execute on function public.admin_security_overview() to authenticated;

notify pgrst, 'reload schema';

-- =====================================================================
-- 35. V4.0 : PAIEMENT DES VENTES EN GROS (identique à supabase/mise-a-jour-gros.sql)
-- =====================================================================
-- ---------------------------------------------------------------------
-- 35.1 PAIEMENT DES VENTES EN GROS
--   Avant : le grossiste et l'acheteur concluaient sur WhatsApp, hors du site (aucune commission, aucune protection).
--   Maintenant : « Commander et payer » crée une VRAIE commande physique (même circuit que le détail) :
--     - prix de gros calculé PAR LA BASE d'après le palier (dès 10 pièces / dès 50 pièces), jamais envoyé par le navigateur ;
--     - paiement en ligne obligatoire (pas de paiement à la livraison), compte acheteur obligatoire ;
--     - argent bloqué comme tout produit physique (jamais libéré avant 7 jours, litige possible, confirmation de réception) ;
--     - commission : 3 % pour la plateforme (0 % pendant le lancement ou pour un compte exempté, jamais plus que le taux normal
--       du vendeur), 5 % pour un affilié éventuel, le reste au grossiste. La livraison revient au grossiste.
--   Le devis WhatsApp reste possible pour négocier (et pour plus de 1 000 pièces).
-- ---------------------------------------------------------------------
alter table public.orders add column if not exists is_wholesale boolean not null default false;
create index if not exists orders_wholesale_idx on public.orders (seller_id, created_at desc) where is_wholesale;

-- Prix unitaire de gros pour une quantité (null si le produit n'est pas proposé en gros ou si la quantité est < 10).
-- Jamais supérieur au prix détail actuel (si le vendeur baisse son prix détail, le prix de gros suit).
create or replace function public.wholesale_unit_price(p_product uuid, p_qty integer)
returns bigint language sql stable security definer set search_path = public as $$
  select least(p.price, case when p_qty >= 50 then w.min_quantity_50_price else w.min_quantity_10_price end)
    from public.wholesale_products w
    join public.products p on p.id = w.product_id
   where w.product_id = p_product and w.is_active and p_qty >= 10
$$;

-- Création de la commande de gros : réutilise create_checkout_order (stock, livraison, anti-fraude, affiliation, compte invité),
-- puis remplace le prix détail par le prix de gros avant tout paiement (même transaction : tout ou rien).
create or replace function public.create_wholesale_order(
  p_product_id      uuid,
  p_buyer_id        uuid,
  p_email           text,
  p_name            text,
  p_quantity        integer,
  p_delivery_method text,
  p_address         text,
  p_phone           text,
  p_ref_code        text,
  p_payment_method  text default 'online',
  p_city            text default null,
  p_district        text default null,
  p_ip              text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  w        public.wholesale_products%rowtype;
  v_unit   bigint;
  v_res    jsonb;
  v_order  uuid;
  v_tx     uuid;
  o        public.orders%rowtype;
  v_total  bigint;
begin
  if p_buyer_id is null then raise exception 'compte_requis_gros'; end if;
  if coalesce(p_payment_method, 'online') <> 'online' then raise exception 'cod_interdit_gros'; end if;
  if p_quantity is null or p_quantity < 10 or p_quantity > 1000 then raise exception 'quantite_gros_invalide'; end if;

  select * into w from public.wholesale_products where product_id = p_product_id and is_active;
  if not found or not public.is_verified_wholesaler(w.seller_id) then raise exception 'produit_gros_introuvable'; end if;
  if w.seller_id = p_buyer_id then raise exception 'achat_propre_produit'; end if;
  if p_quantity > w.stock_wholesale then raise exception 'stock_gros_insuffisant'; end if;

  v_unit := public.wholesale_unit_price(p_product_id, p_quantity);
  if v_unit is null or v_unit < 100 then raise exception 'produit_gros_introuvable'; end if;

  v_res := public.create_checkout_order(p_product_id, p_buyer_id, p_email, p_name, p_quantity, p_delivery_method, p_address,
                                        p_phone, p_ref_code, 'online', p_city, p_district, p_ip);
  -- Anti-fraude téléphone : la commande n'a pas été créée, on renvoie le message tel quel
  if coalesce((v_res ->> 'blocked')::boolean, false) then return v_res; end if;

  v_order := (v_res ->> 'order_id')::uuid;
  v_tx    := (v_res ->> 'transaction_id')::uuid;
  select * into o from public.orders where id = v_order for update;

  v_total := v_unit * o.quantity + o.delivery_price;
  update public.orders
     set unit_price = v_unit,
         total_price = v_total,
         is_wholesale = true,
         affiliate_percent = case when o.affiliate_id is not null then 5 else null end   -- affiliation « gros » : 5 % fixes
   where id = v_order;
  update public.transactions set total_amount = v_total where id = v_tx;

  return v_res || jsonb_build_object('total', v_total, 'unit_price', v_unit, 'wholesale', true);
end $$;

-- Répartition d'une vente : gros = plateforme 3 % (au plus le taux du vendeur : 0 % en lancement ou si exempté) + affilié 5 % ;
-- sinon, le calcul habituel inchangé.
create or replace function public.compute_split_for_order(p_seller uuid, p_wholesale boolean, p_goods bigint, p_has_affiliate boolean, p_affiliate_percent integer, p_physical boolean)
returns table (platform_percent numeric, platform_fee bigint, affiliate_percent integer, affiliate_fee bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_pct numeric; v_aff integer;
begin
  if coalesce(p_wholesale, false) then
    v_pct := least(3, public.seller_platform_rate(p_seller));
    v_aff := case when p_has_affiliate then 5 else 0 end;
    return query select v_pct, floor(p_goods * v_pct / 100)::bigint, v_aff, case when p_has_affiliate then (p_goods * v_aff) / 100 else 0::bigint end;
    return;
  end if;
  return query select * from public.compute_split_for_seller(p_seller, p_goods, p_has_affiliate, p_affiliate_percent, p_physical);
end $$;

-- Confirmation de paiement : identique à la version V3.8, avec UNE seule ligne changée (compute_split_for_order au lieu de compute_split_for_seller)
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
  select * into s from public.compute_split_for_order(o.seller_id, o.is_wholesale, v_goods, v_has_aff, o.affiliate_percent, not v_digital);
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

-- Stock « gros » : diminué quand le paiement est réellement confirmé (pas quand le paiement est seulement en revue)
create or replace function public.wholesale_after_paid()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_wholesale and new.payment_status = 'paid' and old.payment_status is distinct from 'paid'
     and exists (select 1 from public.transactions where order_id = new.id and status = 'paid') then
    update public.wholesale_products
       set stock_wholesale = greatest(0, stock_wholesale - new.quantity), updated_at = now()
     where product_id = new.product_id;
  end if;
  return new;
end $$;
drop trigger if exists orders_wholesale_after_paid on public.orders;
create trigger orders_wholesale_after_paid after update of payment_status on public.orders
  for each row execute function public.wholesale_after_paid();

-- Droits : ces fonctions ne sont appelées que par le serveur (clé service_role) ou par d'autres fonctions
revoke all on function public.wholesale_unit_price(uuid, integer) from public, anon, authenticated;
revoke all on function public.create_wholesale_order(uuid, uuid, text, text, integer, text, text, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.compute_split_for_order(uuid, boolean, bigint, boolean, integer, boolean) from public, anon, authenticated;
revoke all on function public.wholesale_after_paid() from public, anon, authenticated;
grant execute on function public.wholesale_unit_price(uuid, integer) to service_role;
grant execute on function public.create_wholesale_order(uuid, uuid, text, text, integer, text, text, text, text, text, text, text, text) to service_role;
grant execute on function public.compute_split_for_order(uuid, boolean, bigint, boolean, integer, boolean) to service_role;
revoke all on function public.confirm_fapshi_payment(text, bigint, text, bigint) from public, anon, authenticated;
grant execute on function public.confirm_fapshi_payment(text, bigint, text, bigint) to service_role;

notify pgrst, 'reload schema';

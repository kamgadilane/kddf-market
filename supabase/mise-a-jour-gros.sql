-- =====================================================================
-- KDDF Market V4.0 : MISE À JOUR « Paiement des ventes en gros » (commande + paiement sécurisé + commission 3 %)
-- À lancer UNE FOIS dans Supabase > SQL Editor (sans danger si vous le lancez deux fois).
-- Prérequis : le site est déjà en V3.9 (mise-a-jour-identite.sql lancé). Ce fichier est AUSSI inclus dans schema.sql (section 35) :
-- en installation neuve, ne lancez que schema.sql.
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

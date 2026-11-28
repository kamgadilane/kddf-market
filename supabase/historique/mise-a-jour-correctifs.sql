-- KDDF Market : correctifs (quantité de commande jusqu'à 1000, candidature grossiste).
-- À coller dans Supabase > SQL Editor > Run. Sans danger si lancé plusieurs fois.


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

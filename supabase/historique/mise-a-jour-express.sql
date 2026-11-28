-- KDDF Market : retrait express (supplément réglable dans Admin > Commissions).
-- À coller dans Supabase > SQL Editor > Run. Sans danger si lancé plusieurs fois.
-- (Exige que mise-a-jour-revenus.sql ait déjà été lancé.)


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

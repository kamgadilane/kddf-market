-- =====================================================================
-- KDDF Market V3.9 : MISE À JOUR « Identité des vendeurs + alertes d'erreurs + protection des comptes (2FA, téléphone) »
-- À lancer UNE FOIS dans Supabase > SQL Editor (sans danger si vous le lancez deux fois).
-- Prérequis : le site est déjà en V3.8 (mise-a-jour-finale.sql lancé). Ce fichier est AUSSI inclus dans schema.sql (section 34) :
-- en installation neuve, ne lancez que schema.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
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

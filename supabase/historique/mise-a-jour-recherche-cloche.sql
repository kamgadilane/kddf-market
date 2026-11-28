-- KDDF Market : cloche de notification (annonces envoyées par l'administrateur).
-- À coller dans Supabase > SQL Editor > Run. Sans danger si lancé plusieurs fois.
-- (Exige que mise-a-jour-revenus.sql ait déjà été lancé : la fonction is_pro existe.)


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

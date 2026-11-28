-- KDDF MARKET : vérifie que l'installation est complète ET sécurisée.
-- Supabase > SQL Editor > collez ce fichier > Run. Chaque ligne doit afficher "OK".
select 'table ' || t as controle,
       case when to_regclass('public.' || t) is not null then 'OK' else 'MANQUANT : exécutez supabase/mise-a-jour-finale.sql puis supabase/mise-a-jour-identite.sql (ou relancez schema.sql)' end as etat
from unnest(array['profiles','products','orders','transactions','wallets','withdrawals','reviews','product_files','product_boosts','rate_limits','email_outbox','support_messages','commission_settings','fraud_settings','wholesale_applications','wholesale_products','wholesale_requests','fraud_logs','waitlist_international','product_locations','disputes','order_photos','affiliate_links','commission_history','guest_accounts','fx_rates','pro_subscriptions','service_fee_rules','announcements','announcement_reads','user_notifications','app_errors','identity_verifications']) as t
union all
select 'bucket ' || b,
       case when exists (select 1 from storage.buckets where id = b) then 'OK' else 'MANQUANT : créez-le dans Storage' end
from unnest(array['covers','deliverables','support','disputes','wholesale','identity']) as b
union all
select 'fonction ' || f,
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = f) then 'OK' else 'MANQUANT : exécutez supabase/mise-a-jour-finale.sql puis supabase/mise-a-jour-identite.sql (ou relancez schema.sql)' end
from unnest(array['rate_limit_hit','outbox_claim','outbox_report','register_download','fraud_record_ip_for','confirm_fapshi_payment','release_due_funds','admin_overview','seller_dashboard','order_add_photo','purge_old_logs','claim_welcome_email','next_order_code','guest_find_order','guest_track_order','guest_confirm_delivery','guest_open_dispute','seller_platform_rate','confirm_pro_payment','request_withdrawal','apply_service_fee','admin_set_service_fee','admin_set_free_product_limit','notify_user','my_notifications','my_unread_notifications','mark_notifications_read','my_announcements','admin_send_announcement','log_app_error','admin_list_errors','delete_my_account','export_my_data','identity_submit','my_identity','admin_identity_list','admin_identity_decide','admin_set_identity_required','notify_admins','alert_admins_error','mfa_ok','is_phone_ok','my_phone','admin_set_phone_required','admin_security_overview']) as f
union all
-- SÉCURITÉ : aucune vue publique ne doit être modifiable par un visiteur ou un utilisateur connecté
select 'securite : vues en lecture seule',
       case when count(*) = 0 then 'OK' else 'DANGER : relancez schema.sql (section 27) - ' || string_agg(c.relname, ', ') end
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('v', 'm')
  and (has_table_privilege('anon', c.oid, 'INSERT,UPDATE,DELETE') or has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE'))
union all
select 'securite : tables fermées aux visiteurs (écriture)',
       case when count(*) = 0 then 'OK' else 'DANGER : relancez schema.sql (section 27) - ' || string_agg(c.relname, ', ') end
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
  and (has_table_privilege('anon', c.oid, 'INSERT') or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'))
union all
select 'securite : RLS activée sur toutes les tables',
       case when count(*) = 0 then 'OK' else 'DANGER : RLS absente sur ' || string_agg(c.relname, ', ') end
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity

-- GUEST CHECKOUT (V3.1) : les fonctions « sans compte » ne doivent être appelables que par le serveur (service_role)
union all
select 'securite : fonctions invité réservées au serveur',
       case when count(*) = 0 then 'OK' else 'DANGER : relancez schema.sql (section 30) - ' || string_agg(p.proname, ', ') end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('next_order_code','guest_find_order','guest_track_order','guest_confirm_delivery','guest_open_dispute')
  and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
union all
select 'colonne transactions.order_code',
       case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'transactions' and column_name = 'order_code') then 'OK' else 'MANQUANT : relancez schema.sql (section 30)' end
union all
select 'colonne ' || c,
       case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name || '.' || column_name = c) then 'OK' else 'MANQUANT : exécutez supabase/mise-a-jour-finale.sql' end
from unnest(array['transactions.service_fee','transactions.service_gateway','commission_settings.free_product_limit','commission_settings.express_fee_percent','withdrawals.express','profiles.deleted_at','profiles.commission_exempt']) as c
union all
select 'frais de service : 4 passerelles réglées',
       case when to_regclass('public.service_fee_rules') is not null
             and (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.service_fee_rules', false, true, '')))[1]::text = '4'
            then 'OK' else 'PROBLÈME : exécutez supabase/mise-a-jour-finale.sql' end
union all
select 'taux de commission par défaut (normal 8 % / Pro 5 %) : valeurs actuelles',
       case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'commission_settings' and column_name = 'free_product_limit')
            then coalesce((xpath('/row/t/text()', query_to_xml('select ''OK : normal '' || after_launch_percent || '' % / Pro '' || pro_percent || '' % / limite gratuite '' || free_product_limit || '' produits'' as t from public.commission_settings where id = 1', false, true, '')))[1]::text, 'MANQUANT : ligne commission_settings absente')
            else 'MANQUANT : exécutez supabase/mise-a-jour-finale.sql' end
union all
select 'securite : fonctions internes réservées au serveur',
       case when count(*) = 0 then 'OK' else 'DANGER : exécutez supabase/mise-a-jour-finale.sql - ' || string_agg(p.proname, ', ') end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('apply_service_fee','notify_user','log_app_error','confirm_fapshi_payment','confirm_pro_payment','mfa_ok','is_phone_ok','is_identity_ok','notify_admins')
  and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
union all
select 'securite : fonctions du compte fermées aux visiteurs',
       case when count(*) = 0 then 'OK' else 'DANGER : exécutez supabase/mise-a-jour-finale.sql - ' || string_agg(p.proname, ', ') end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('delete_my_account','export_my_data','my_notifications','my_unread_notifications','mark_notifications_read','admin_set_service_fee','admin_set_free_product_limit','admin_list_errors')
  and has_function_privilege('anon', p.oid, 'EXECUTE')
union all
-- SÉCURITÉ V3.9 : l'espace « identity » (cartes d'identité) ne doit JAMAIS être public
select 'securite : espace identity privé',
       case when exists (select 1 from storage.buckets where id = 'identity' and not public) then 'OK' else 'DANGER : espace identity absent ou public' end
union all
-- PROTECTION DES COMPTES V3.9 : retraits protégés par la 2FA + règle « téléphone confirmé »
select 'securite : retraits protégés par la 2FA et règle téléphone',
       case when exists (select 1 from pg_trigger where tgname = 'withdrawals_mfa_trg' and not tgisinternal)
             and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'commission_settings' and column_name = 'phone_required')
            then 'OK' else 'PROBLÈME : exécutez supabase/mise-a-jour-identite.sql' end
union all
-- VENTES EN GROS V4.0 : colonne, fonctions et déclencheur présents
select 'ventes en gros (V4.0) : installées',
       case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'orders' and column_name = 'is_wholesale')
             and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'create_wholesale_order')
             and exists (select 1 from pg_trigger where tgname = 'orders_wholesale_after_paid' and not tgisinternal)
            then 'OK' else 'MANQUANT : exécutez supabase/mise-a-jour-gros.sql' end
union all
select 'securite : fonctions de vente en gros réservées au serveur',
       case when count(*) = 0 then 'OK' else 'DANGER : exécutez supabase/mise-a-jour-gros.sql - ' || string_agg(p.proname, ', ') end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('create_wholesale_order','wholesale_unit_price','compute_split_for_order','wholesale_after_paid')
  and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'));

-- Run ONCE, only AFTER the `send-push` Edge Function is deployed and its secrets are set (see docs/APPLE_ACCOUNT_STEPS.md).
-- 1. Replace PASTE-YOUR-SERVICE-ROLE-KEY with the "service_role" key (Project Settings → API). It is stored encrypted in
--    Supabase Vault — it never goes in the repository or the app.
-- 2. Run this whole file.
create extension if not exists pg_net;
select vault.create_secret('PASTE-YOUR-SERVICE-ROLE-KEY', 'service_role_key');

select cron.schedule('fade-send-push', '* * * * *', $$
  select net.http_post(
    url     := 'https://skfbqidighnmhsvgscxf.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
    body    := '{}'::jsonb)
$$);

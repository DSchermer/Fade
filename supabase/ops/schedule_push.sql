-- Run ONCE, only AFTER the `send-push` Edge Function is deployed and its secrets are set (see docs/APPLE_ACCOUNT_STEPS.md).
--
-- BEFORE running this file, store the project's "service_role" key in Supabase Vault through the dashboard (so it never appears in
-- a SQL query, a query history, or this repository):
--   Dashboard → Project Settings → API Keys → copy the `service_role` key (Legacy API keys tab; a long string starting eyJ…)
--   Dashboard → Integrations → Vault (or Database → Vault) → Add new secret → Name: service_role_key → paste the key → Save.
-- The key is a master password: never put it in the app, in this repository, or in chat.
--
-- Then run this whole file. It schedules the sender every minute.
create extension if not exists pg_net;

select cron.schedule('fade-send-push', '* * * * *', $$
  select net.http_post(
    url     := 'https://skfbqidighnmhsvgscxf.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
    body    := '{}'::jsonb)
$$);

-- Check that the key is stored (should return 1, and NOT show the key):
select count(*) as service_role_key_stored from vault.decrypted_secrets where name = 'service_role_key';

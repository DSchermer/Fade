-- Run ONCE (or again to update the schedule), only AFTER the `send-push` Edge Function is deployed and its secrets are set
-- (see docs/APPLE_ACCOUNT_STEPS.md).
--
-- BEFORE running this file, store two secrets in Supabase Vault through the dashboard (so they never appear in a SQL query,
-- a query history, or this repository). Integrations → Vault → Add new secret:
--   • `service_role_key`: the project's legacy `service_role` key (Project Settings → API Keys → Legacy tab; long string starting eyJ…).
--     It only has to be a valid key so Supabase's front door lets the request through.
--   • `push_secret`: a random password that you also save as the Edge Function secret `PUSH_SECRET`. The function checks THIS one.
--     Make it in Terminal with:  openssl rand -hex 24 | pbcopy   (then paste the same value in both places).
--
-- Then run this whole file. It schedules the sender every minute.
create extension if not exists pg_net;

select cron.schedule('fade-send-push', '* * * * *', $$
  select net.http_post(
    url     := 'https://skfbqidighnmhsvgscxf.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'x-push-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'push_secret')),
    body    := '{}'::jsonb)
$$);

-- Check that both secrets are stored (should return 2, and NOT show the values):
select count(*) as secrets_stored from vault.decrypted_secrets where name in ('service_role_key', 'push_secret');

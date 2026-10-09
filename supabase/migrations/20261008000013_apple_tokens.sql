-- Fade — Milestone 12: a private place for the Sign in with Apple refresh token, so the connection to a person's
-- Apple ID can be revoked when they delete their account (an App Store requirement).
-- Only the Edge Functions (service key) can read or write this table; no app user can.
create table public.apple_tokens (
  user_id       uuid primary key,
  refresh_token text not null,
  created_at    timestamptz not null default now()
);
alter table public.apple_tokens enable row level security;     -- no policy, no grant
revoke all on public.apple_tokens from public, anon, authenticated;

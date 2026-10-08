-- Fade — Milestone 2: usernames.
-- A profile row is created the first time a signed-in user picks a username.
-- Usernames are stored lowercase, 3–20 chars of a-z 0-9 _, unique, and can be changed later.

create function public.set_username(p_username text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := lower(btrim(coalesce(p_username, '')));
begin
  if v_uid is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;
  if v_name !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'username_invalid' using errcode = '22023';
  end if;
  if v_name = any (array['admin', 'administrator', 'fade', 'support', 'moderator', 'mod', 'system',
                         'root', 'staff', 'help', 'official', 'null', 'undefined', 'deleted', 'deleteduser']) then
    raise exception 'username_reserved' using errcode = '22023';
  end if;
  if exists (select 1 from public.profiles where id = v_uid and (banned or deleted_at is not null)) then
    raise exception 'account_disabled' using errcode = '42501';
  end if;

  insert into public.profiles (id, username, display_name)
  values (v_uid, v_name, v_name)
  on conflict (id) do update set username = excluded.username;

  return v_name;
exception when unique_violation then
  raise exception 'username_taken' using errcode = '23505';
end $$;

-- Lets the app show "taken" while typing. Returns true if the name is valid and free (or already yours).
create function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select lower(btrim(coalesce(p_username, ''))) ~ '^[a-z0-9_]{3,20}$'
     and not exists (select 1 from public.profiles
                      where username = lower(btrim(p_username))
                        and id is distinct from auth.uid());
$$;

revoke all on function public.set_username(text), public.username_available(text) from public, anon;
grant execute on function public.set_username(text), public.username_available(text) to authenticated;

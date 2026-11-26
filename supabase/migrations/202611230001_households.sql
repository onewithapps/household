-- Accounts live in auth.users. Membership/roles are assigned only by these RPCs.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) between 1 and 80)
);
create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 100),
  created_at timestamptz not null default now()
);
create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'adult', 'child')),
  created_at timestamptz not null default now(),
  primary key (household_id, user_id)
);
create table public.household_invites (
  token uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  email text not null check (email = lower(btrim(email)) and position('@' in email) > 1),
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  unique (household_id, email)
);

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;

-- Security-definer membership checks avoid recursive RLS policies.
create function public.is_household_member(p_household_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.household_members
    where household_id = p_household_id and user_id = auth.uid());
$$;
create function public.shares_household(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.household_members me
    join public.household_members other on other.household_id = me.household_id
    where me.user_id = auth.uid() and other.user_id = p_user_id);
$$;
create policy read_households on public.households for select to authenticated
  using (public.is_household_member(id));
create policy read_members on public.household_members for select to authenticated
  using (public.is_household_member(household_id));
create policy read_profiles on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_household(id));
-- No direct invite access or table writes, including for authenticated users.
revoke all on public.profiles, public.households, public.household_members, public.household_invites from anon, authenticated;
grant select on public.profiles, public.households, public.household_members to authenticated;

create function public.create_household(p_name text, p_display_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_household uuid;
begin
  if v_user is null then raise exception 'Sign in first'; end if;
  -- Serialize household enrollment for this user across concurrent requests.
  perform 1 from auth.users where id = v_user for update;
  if exists(select 1 from public.household_members where user_id = v_user) then
    raise exception 'You already belong to a household';
  end if;
  insert into public.profiles(id, display_name) values(v_user, btrim(p_display_name))
    on conflict(id) do update set display_name = excluded.display_name;
  insert into public.households(name) values(btrim(p_name)) returning id into v_household;
  insert into public.household_members(household_id, user_id, role) values(v_household, v_user, 'owner');
  return v_household;
end;
$$;

create function public.create_household_invite(p_household_id uuid, p_email text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_token uuid;
begin
  if not exists(select 1 from public.household_members
    where household_id = p_household_id and user_id = auth.uid() and role in ('owner', 'adult')) then
    raise exception 'Only adults in this household can invite members';
  end if;
  -- Reissuing an invitation invalidates the previous token for this email.
  insert into public.household_invites(household_id, email, created_by)
    values(p_household_id, lower(btrim(p_email)), auth.uid())
    on conflict(household_id, email) do update set token = gen_random_uuid(),
      expires_at = now() + interval '7 days', accepted_at = null, created_by = auth.uid()
    returning token into v_token;
  return v_token;
end;
$$;

create function public.accept_household_invite(p_token uuid, p_display_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_email text; v_invite public.household_invites;
begin
  if v_user is null then raise exception 'Sign in first'; end if;
  select lower(email) into v_email from auth.users
    where id = v_user and email_confirmed_at is not null for update;
  if v_email is null then raise exception 'Verify your email first'; end if;
  if exists(select 1 from public.household_members where user_id = v_user) then
    raise exception 'You already belong to a household';
  end if;
  select * into v_invite from public.household_invites where token = p_token for update;
  if not found or v_invite.email <> v_email or v_invite.expires_at <= now() or v_invite.accepted_at is not null then
    raise exception 'Invitation is invalid, expired, or belongs to another email';
  end if;
  insert into public.profiles(id, display_name) values(v_user, btrim(p_display_name))
    on conflict(id) do update set display_name = excluded.display_name;
  insert into public.household_members(household_id, user_id, role) values(v_invite.household_id, v_user, 'adult');
  update public.household_invites set accepted_at = now() where token = p_token;
  return v_invite.household_id;
end;
$$;

revoke all on function public.is_household_member(uuid), public.shares_household(uuid),
  public.create_household(text, text), public.create_household_invite(uuid, text),
  public.accept_household_invite(uuid, text) from public, anon;
grant execute on function public.is_household_member(uuid), public.shares_household(uuid),
  public.create_household(text, text), public.create_household_invite(uuid, text),
  public.accept_household_invite(uuid, text) to authenticated;

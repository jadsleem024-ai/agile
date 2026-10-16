-- ============================================================================
--  AGILE — multi-coach accounts, email auth, per-coach data isolation
--  Run this once in the Supabase SQL editor (Dashboard -> SQL -> New query).
--  It is idempotent: safe to re-run.
-- ============================================================================

-- The admin account. Everything below keys off this address.
-- Change it here if the owner email ever changes.
create or replace function public.admin_email() returns text
language sql immutable as $$ select 'agile.performances@gmail.com'::text $$;

-- ---------------------------------------------------------------------------
-- 1. New columns on the existing tables
-- ---------------------------------------------------------------------------

-- Owner of the row. Defaults to whoever is inserting, so app code never has
-- to pass it explicitly.
alter table public.trainees
  add column if not exists coach_id uuid references auth.users(id) on delete cascade default auth.uid();
alter table public.programs
  add column if not exists coach_id uuid references auth.users(id) on delete cascade default auth.uid();
alter table public.exercise_library
  add column if not exists coach_id uuid references auth.users(id) on delete cascade default auth.uid();

-- Admin-authored default library entries, readable by coaches who are opted in
-- via profiles.shares_library.
alter table public.exercise_library
  add column if not exists is_global boolean not null default false;

-- Binds a trainee record to the auth account that redeemed its code.
alter table public.trainees
  add column if not exists claimed_by uuid references auth.users(id) on delete set null;

-- How many times the assigned rotation repeats before the block is finished.
-- NULL means repeat forever, which is the behaviour before loops existed.
alter table public.trainees
  add column if not exists loop_target integer;

-- Marks the rows of a session the trainee explicitly finished ("Save & Done"),
-- so the app knows to roll the rotation forward to the next program.
alter table public.progress
  add column if not exists session_finished boolean not null default false;

create index if not exists trainees_coach_id_idx         on public.trainees(coach_id);
create index if not exists programs_coach_id_idx         on public.programs(coach_id);
create index if not exists exercise_library_coach_id_idx on public.exercise_library(coach_id);

-- ---------------------------------------------------------------------------
-- 2. Profiles — one row per auth user, carrying the role
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text not null,
  full_name    text,
  role         text not null default 'pending'
                 check (role in ('pending', 'admin', 'coach', 'trainee')),
  -- Whether a coach sees the admin-authored shared exercise library. Defaults
  -- to false: the admin opts a coach in explicitly rather than every coach
  -- getting it and the admin having to opt individuals out.
  shares_library boolean not null default false,
  trainee_id   uuid references public.trainees(id) on delete set null,
  activated_at timestamptz,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. Coach access codes — issued by the admin, redeemed once by a coach
-- ---------------------------------------------------------------------------

create table if not exists public.coach_codes (
  code       text primary key,
  label      text,
  created_by uuid references auth.users(id) on delete set null,
  claimed_by uuid references auth.users(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4. Role helpers
--
-- security definer so a policy on profiles can consult profiles without
-- recursing through its own RLS check.
-- ---------------------------------------------------------------------------

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.my_trainee_id() returns uuid
language sql stable security definer set search_path = public as $$
  select trainee_id from public.profiles where id = auth.uid() and role = 'trainee'
$$;

create or replace function public.my_trainee_code() returns text
language sql stable security definer set search_path = public as $$
  select t.code
    from public.trainees t
    join public.profiles p on p.trainee_id = t.id
   where p.id = auth.uid() and p.role = 'trainee'
$$;

-- True when the current user owns this trainee (admin sees everyone).
create or replace function public.owns_trainee(p_trainee_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or exists (select 1 from public.trainees t
                  where t.id = p_trainee_id and t.coach_id = auth.uid())
$$;

create or replace function public.owns_program(p_program_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or exists (select 1 from public.programs p
                  where p.id = p_program_id and p.coach_id = auth.uid())
$$;

-- A trainee may read any program currently assigned to them, through either
-- the rotation table or the single-program column.
create or replace function public.trainee_can_see_program(p_program_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.trainee_programs tp
                  where tp.program_id = p_program_id
                    and tp.trainee_id = public.my_trainee_id())
      or exists (select 1 from public.trainees t
                  where t.id = public.my_trainee_id()
                    and t.program_id = p_program_id)
$$;

-- ---------------------------------------------------------------------------
-- 5. Provision a profile whenever an auth user is created
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_is_admin boolean := lower(new.email) = lower(public.admin_email());
begin
  insert into public.profiles (id, email, role, activated_at)
  values (new.id,
          new.email,
          case when v_is_admin then 'admin' else 'pending' end,
          case when v_is_admin then now() else null end)
  on conflict (id) do update set email = excluded.email;

  -- First time the owner signs up, adopt every pre-existing row that was
  -- created before accounts existed, so nothing is orphaned by RLS.
  if v_is_admin then
    update public.trainees         set coach_id = new.id where coach_id is null;
    update public.programs         set coach_id = new.id where coach_id is null;
    update public.exercise_library set coach_id = new.id where coach_id is null;
  end if;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill for accounts that already exist.
insert into public.profiles (id, email, role, activated_at)
select u.id,
       u.email,
       case when lower(u.email) = lower(public.admin_email()) then 'admin' else 'pending' end,
       case when lower(u.email) = lower(public.admin_email()) then now() else null end
  from auth.users u
on conflict (id) do nothing;

-- If the owner's account already existed, the trigger above will never fire
-- for it, so adopt the pre-account rows and confirm the admin role here.
do $$
declare
  v_admin uuid;
begin
  select id into v_admin
    from auth.users
   where lower(email) = lower(public.admin_email())
   limit 1;

  if v_admin is not null then
    update public.profiles
       set role = 'admin', activated_at = coalesce(activated_at, now())
     where id = v_admin;
    update public.trainees         set coach_id = v_admin where coach_id is null;
    update public.programs         set coach_id = v_admin where coach_id is null;
    update public.exercise_library set coach_id = v_admin where coach_id is null;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Code redemption (security definer — the caller never touches the tables)
-- ---------------------------------------------------------------------------

create or replace function public.claim_coach_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_code public.coach_codes%rowtype;
  v_norm text := upper(trim(p_code));
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Not signed in');
  end if;

  select * into v_code from public.coach_codes where code = v_norm;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'That coach code does not exist');
  end if;
  if v_code.claimed_by is not null and v_code.claimed_by <> auth.uid() then
    return jsonb_build_object('ok', false, 'error', 'That coach code has already been used');
  end if;

  update public.coach_codes
     set claimed_by = auth.uid(), claimed_at = now()
   where code = v_norm;

  update public.profiles
     set role = 'coach', trainee_id = null, activated_at = now()
   where id = auth.uid() and role <> 'admin';

  return jsonb_build_object('ok', true, 'role', 'coach');
end $$;

create or replace function public.claim_trainee_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_trainee public.trainees%rowtype;
  v_norm text := upper(trim(p_code));
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Not signed in');
  end if;

  select * into v_trainee from public.trainees where upper(code) = v_norm;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'That code does not match any trainee');
  end if;
  if v_trainee.claimed_by is not null and v_trainee.claimed_by <> auth.uid() then
    return jsonb_build_object('ok', false, 'error', 'That code is already linked to another account');
  end if;

  update public.trainees set claimed_by = auth.uid() where id = v_trainee.id;

  update public.profiles
     set role = 'trainee', trainee_id = v_trainee.id, activated_at = now()
   where id = auth.uid() and role <> 'admin';

  return jsonb_build_object('ok', true, 'role', 'trainee',
                            'trainee_id', v_trainee.id,
                            'trainee_code', v_trainee.code,
                            'trainee_name', v_trainee.name);
end $$;

grant execute on function public.claim_coach_code(text)   to authenticated;
grant execute on function public.claim_trainee_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Row Level Security
-- ---------------------------------------------------------------------------

-- Clear every pre-existing policy on these tables first.
--
-- This matters: policies are OR'd together, so a single leftover permissive
-- rule silently defeats everything below. This project shipped with
-- "Allow all access to exercise_library" (USING true, role public), which would
-- have let every coach read every other coach's library. Dropping the lot and
-- recreating only the policies defined here makes the end state deterministic.
do $$
declare
  r record;
begin
  for r in
    select schemaname, tablename, policyname
      from pg_policies
     where schemaname = 'public'
       and tablename in ('profiles', 'coach_codes', 'trainees', 'programs',
                         'exercises', 'trainee_programs', 'progress',
                         'exercise_library')
  loop
    execute format('drop policy if exists %I on %I.%I',
                   r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

alter table public.profiles         enable row level security;
alter table public.coach_codes      enable row level security;
alter table public.trainees         enable row level security;
alter table public.programs         enable row level security;
alter table public.exercises        enable row level security;
alter table public.trainee_programs enable row level security;
alter table public.progress         enable row level security;
alter table public.exercise_library enable row level security;

-- profiles -------------------------------------------------------------------
drop policy if exists profiles_self_read  on public.profiles;
drop policy if exists profiles_self_write on public.profiles;
drop policy if exists profiles_admin_all  on public.profiles;

create policy profiles_self_read on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_self_write on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_admin_all on public.profiles
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- coach_codes — admin only; coaches redeem via claim_coach_code() -------------
drop policy if exists coach_codes_admin_all on public.coach_codes;
create policy coach_codes_admin_all on public.coach_codes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- trainees -------------------------------------------------------------------
drop policy if exists trainees_owner_all on public.trainees;
drop policy if exists trainees_self_read on public.trainees;

create policy trainees_owner_all on public.trainees
  for all to authenticated
  using  (public.is_admin() or coach_id = auth.uid())
  with check (public.is_admin() or coach_id = auth.uid());

create policy trainees_self_read on public.trainees
  for select to authenticated using (id = public.my_trainee_id());

-- programs -------------------------------------------------------------------
drop policy if exists programs_owner_all    on public.programs;
drop policy if exists programs_trainee_read on public.programs;

create policy programs_owner_all on public.programs
  for all to authenticated
  using  (public.is_admin() or coach_id = auth.uid())
  with check (public.is_admin() or coach_id = auth.uid());

create policy programs_trainee_read on public.programs
  for select to authenticated using (public.trainee_can_see_program(id));

-- exercises (ownership flows through the parent program) ----------------------
drop policy if exists exercises_owner_all    on public.exercises;
drop policy if exists exercises_trainee_read on public.exercises;

create policy exercises_owner_all on public.exercises
  for all to authenticated
  using (public.owns_program(program_id))
  with check (public.owns_program(program_id));

create policy exercises_trainee_read on public.exercises
  for select to authenticated using (public.trainee_can_see_program(program_id));

-- trainee_programs -----------------------------------------------------------
drop policy if exists trainee_programs_owner_all    on public.trainee_programs;
drop policy if exists trainee_programs_trainee_read on public.trainee_programs;

create policy trainee_programs_owner_all on public.trainee_programs
  for all to authenticated
  using (public.owns_trainee(trainee_id))
  with check (public.owns_trainee(trainee_id));

create policy trainee_programs_trainee_read on public.trainee_programs
  for select to authenticated using (trainee_id = public.my_trainee_id());

-- progress -------------------------------------------------------------------
drop policy if exists progress_owner_all on public.progress;
drop policy if exists progress_self_all  on public.progress;

create policy progress_owner_all on public.progress
  for all to authenticated
  using (exists (select 1 from public.trainees t
                  where t.code = progress.trainee_code
                    and (public.is_admin() or t.coach_id = auth.uid())))
  with check (exists (select 1 from public.trainees t
                       where t.code = progress.trainee_code
                         and (public.is_admin() or t.coach_id = auth.uid())));

create policy progress_self_all on public.progress
  for all to authenticated
  using (trainee_code = public.my_trainee_code())
  with check (trainee_code = public.my_trainee_code());

-- exercise_library -----------------------------------------------------------
drop policy if exists exercise_library_owner_all on public.exercise_library;
create policy exercise_library_owner_all on public.exercise_library
  for all to authenticated
  using  (public.is_admin() or coach_id = auth.uid())
  with check (public.is_admin() or coach_id = auth.uid());

-- The shared default library: visible to the admin always, and to a coach
-- only once the admin has opted them in via profiles.shares_library.
drop policy if exists exercise_library_global_read on public.exercise_library;
create policy exercise_library_global_read on public.exercise_library
  for select to authenticated
  using (
    is_global and (
      public.is_admin()
      or (public.my_role() = 'coach'
          and coalesce((select shares_library from public.profiles where id = auth.uid()), false))
    )
  );

-- ============================================================================
-- Phase 2 — program loops, coach removal, and push notifications
--
-- Everything below was applied directly against the live project across
-- several later sessions and, like the shared-library section above it, never
-- made it back into this file until now. Idempotent, like the rest of the
-- file: safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Program loops
-- ---------------------------------------------------------------------------

-- How many finished sessions the trainee has completed in their current
-- block. Bumped by advance_block_position(); a trainee has no direct write
-- access to it, only to the RPC.
alter table public.trainees
  add column if not exists block_position integer not null default 0;

-- Bumps a trainee one session forward. Called once per Save and Done. If that
-- exact increment completes every loop of the block, it also notifies the
-- owning coach via the send-block-complete-push edge function.
create or replace function public.advance_block_position(p_code text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_new integer;
  v_trainee record;
  v_day_count integer;
  v_secret text;
  v_project_url text := 'https://yuaevlnbmsildmyuiujr.supabase.co';
begin
  if not (public.my_trainee_code() = p_code
          or exists (select 1 from public.trainees t
                      where t.code = p_code
                        and (public.is_admin() or t.coach_id = auth.uid()))) then
    raise exception 'not allowed';
  end if;

  update public.trainees set block_position = block_position + 1
   where code = p_code
   returning id, name, coach_id, loop_target, block_position
     into v_trainee;
  v_new := v_trainee.block_position;

  -- Fire the push exactly on the increment that completes the block, not
  -- before (not yet done) and not after (already notified).
  if v_trainee.loop_target is not null and v_trainee.coach_id is not null then
    select count(*) into v_day_count
      from public.trainee_programs where trainee_id = v_trainee.id;

    if v_day_count > 0 and v_new = v_day_count * v_trainee.loop_target then
      select value into v_secret from public.app_config where key = 'push_trigger_secret';

      perform net.http_post(
        url := v_project_url || '/functions/v1/send-block-complete-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Push-Trigger-Secret', v_secret
        ),
        body := jsonb_build_object(
          'coach_id', v_trainee.coach_id,
          'trainee_name', v_trainee.name,
          'loops', v_trainee.loop_target,
          'day_count', v_day_count
        )
      );
    end if;
  end if;

  return v_new;
end $$;

grant execute on function public.advance_block_position(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Coach removal
-- ---------------------------------------------------------------------------

-- Revokes a coach's access. Their roster moves to the admin rather than being
-- deleted (coach_id cascades on user delete, which would otherwise take real
-- trainee records with it), and the code they redeemed is deleted so it
-- cannot be used to walk back in.
create or replace function public.remove_coach(p_user_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid;
  v_trainees int; v_programs int; v_library int;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'Only the admin can remove a coach');
  end if;
  select id into v_admin from public.profiles where role = 'admin' limit 1;
  if p_user_id = v_admin then
    return jsonb_build_object('ok', false, 'error', 'The admin account cannot be removed');
  end if;

  update public.trainees set coach_id = v_admin where coach_id = p_user_id;
  get diagnostics v_trainees = row_count;
  update public.programs set coach_id = v_admin where coach_id = p_user_id;
  get diagnostics v_programs = row_count;
  update public.exercise_library set coach_id = v_admin where coach_id = p_user_id;
  get diagnostics v_library = row_count;

  delete from public.coach_codes where claimed_by = p_user_id;

  update public.profiles
     set role = 'pending', activated_at = null, shares_library = false
   where id = p_user_id;

  return jsonb_build_object('ok', true, 'trainees', v_trainees,
                            'programs', v_programs, 'library', v_library);
end $$;

grant execute on function public.remove_coach(uuid) to authenticated;

-- Deletes a coach code. If it was already redeemed, this must revoke that
-- coach's access too, since access is granted by profiles.role, not by the
-- code row still existing, so a plain delete from coach_codes left a claimed
-- code's coach fully able to keep working forever.
create or replace function public.delete_coach_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_code public.coach_codes%rowtype;
  v_admin uuid;
  v_norm text := upper(trim(p_code));
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'Only the admin can delete a coach code');
  end if;

  select * into v_code from public.coach_codes where code = v_norm;
  if not found then
    return jsonb_build_object('ok', true, 'demoted', false);
  end if;

  if v_code.claimed_by is not null then
    select id into v_admin from public.profiles where role = 'admin' limit 1;

    update public.trainees         set coach_id = v_admin where coach_id = v_code.claimed_by;
    update public.programs         set coach_id = v_admin where coach_id = v_code.claimed_by;
    update public.exercise_library set coach_id = v_admin where coach_id = v_code.claimed_by;

    update public.profiles
       set role = 'pending', activated_at = null, shares_library = false
     where id = v_code.claimed_by;
  end if;

  delete from public.coach_codes where code = v_norm;

  return jsonb_build_object('ok', true, 'demoted', v_code.claimed_by is not null);
end $$;

grant execute on function public.delete_coach_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Push notifications: coach alert when a trainee finishes their block
-- ---------------------------------------------------------------------------

-- Lets Postgres call the edge function directly from advance_block_position.
create extension if not exists pg_net with schema extensions;

-- A place for small server-side settings that must never be readable through
-- the API. The RLS policy below blocks every row-level client access; only
-- security-definer functions, which bypass RLS, can read it.
create table if not exists public.app_config (
  key   text primary key,
  value text not null
);
alter table public.app_config enable row level security;
drop policy if exists app_config_no_access on public.app_config;
create policy app_config_no_access on public.app_config
  for all to authenticated using (false) with check (false);

-- One row of this table is required before push notifications work. See
-- "Push notifications" in supabase/SETUP.md for the exact command, generated
-- fresh per project rather than checked in here.

-- Each device that should receive the alert. A coach may have more than one,
-- for example a phone and a tablet, and every row is pushed to.
create table if not exists public.push_tokens (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  token       text not null unique,
  platform    text not null default 'android',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists push_tokens_profile_id_idx on public.push_tokens(profile_id);
alter table public.push_tokens enable row level security;
drop policy if exists push_tokens_own on public.push_tokens;
create policy push_tokens_own on public.push_tokens
  for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

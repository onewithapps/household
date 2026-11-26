-- Run against a disposable/local Supabase database after applying the migration.
-- Everything, including fixture accounts, is rolled back.
begin;
create function pg_temp.assert_true(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %', label; end if; end;
$$;
create function pg_temp.expect_failure(statement text, expected text) returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    if position(expected in sqlerrm) > 0 then return; end if;
    raise exception 'Unexpected error: % (expected %)', sqlerrm, expected;
  end;
  raise exception 'Expected failure: %', statement;
end;
$$;
insert into auth.users(id, email, email_confirmed_at) values
 ('10000000-0000-0000-0000-000000000001', 'owner@example.com', now()),
 ('10000000-0000-0000-0000-000000000002', 'partner@example.com', now()),
 ('10000000-0000-0000-0000-000000000003', 'outsider@example.com', now()),
 ('10000000-0000-0000-0000-000000000004', 'expired@example.com', now()),
 ('10000000-0000-0000-0000-000000000005', 'child@example.com', now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('test.household', public.create_household('Our home', 'Owner')::text, true);
select pg_temp.assert_true((select count(*) = 1 from public.households), 'owner sees their household');
select pg_temp.expect_failure($q$select public.create_household('Second home', 'Owner')$q$, 'already belong');
select set_config('test.invite', public.create_household_invite(current_setting('test.household')::uuid, ' PARTNER@example.com ')::text, true);
select set_config('test.expired', public.create_household_invite(current_setting('test.household')::uuid, 'expired@example.com')::text, true);
select pg_temp.expect_failure('select * from public.household_invites', 'permission denied');
select pg_temp.expect_failure($q$update public.household_members set role = 'owner'$q$, 'permission denied');
select pg_temp.expect_failure($q$insert into public.households(name) values('Bypass')$q$, 'permission denied');
select pg_temp.expect_failure($q$update public.profiles set display_name = 'Impersonated'$q$, 'permission denied');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select pg_temp.assert_true((select count(*) = 0 from public.households), 'outsider cannot see household');
select pg_temp.assert_true((select count(*) = 0 from public.household_members), 'outsider cannot see members');
select pg_temp.assert_true((select count(*) = 0 from public.profiles), 'outsider cannot see profiles');
select pg_temp.expect_failure($q$select public.accept_household_invite(current_setting('test.invite')::uuid, 'Outsider')$q$, 'belongs to another email');
select pg_temp.expect_failure($q$select public.create_household_invite(current_setting('test.household')::uuid, 'other@example.com')$q$, 'Only adults');
select public.create_household('Other home', 'Outsider');
select pg_temp.assert_true((select count(*) = 1 from public.households), 'outsider sees only their own household');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select public.accept_household_invite(current_setting('test.invite')::uuid, 'Partner');
select pg_temp.assert_true((select count(*) = 1 from public.households), 'partner sees shared household');
select pg_temp.assert_true((select count(*) = 2 from public.household_members), 'partner sees both members');
select pg_temp.assert_true((select count(*) = 2 from public.profiles), 'partner sees both profiles');
select pg_temp.assert_true((select role = 'adult' from public.household_members where user_id = auth.uid()), 'invited partner is adult');
select pg_temp.expect_failure($q$select public.accept_household_invite(current_setting('test.invite')::uuid, 'Partner')$q$, 'already belong');

reset role;
-- Remove membership only in the fixture to exercise replay protection independently.
delete from public.household_members where user_id = '10000000-0000-0000-0000-000000000002';
update public.household_invites set expires_at = now() - interval '1 minute' where token = current_setting('test.expired')::uuid;
insert into public.profiles values('10000000-0000-0000-0000-000000000005', 'Child');
insert into public.household_members(household_id, user_id, role) values(current_setting('test.household')::uuid, '10000000-0000-0000-0000-000000000005', 'child');
set local role authenticated;
select pg_temp.expect_failure($q$select public.accept_household_invite(current_setting('test.invite')::uuid, 'Partner')$q$, 'invalid, expired');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
select pg_temp.expect_failure($q$select public.accept_household_invite(current_setting('test.expired')::uuid, 'Expired')$q$, 'invalid, expired');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
select pg_temp.expect_failure($q$select public.create_household_invite(current_setting('test.household')::uuid, 'other@example.com')$q$, 'Only adults');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('test.reissued', public.create_household_invite(current_setting('test.household')::uuid, 'partner@example.com')::text, true);
select pg_temp.assert_true(current_setting('test.reissued') <> current_setting('test.invite'), 'reissue rotates token');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select pg_temp.expect_failure($q$select public.accept_household_invite(current_setting('test.invite')::uuid, 'Partner')$q$, 'invalid, expired');
select public.accept_household_invite(current_setting('test.reissued')::uuid, 'Partner');

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.expect_failure('select * from public.households', 'permission denied');
select pg_temp.expect_failure($q$select public.create_household('Anonymous home', 'Anonymous')$q$, 'permission denied');
select pg_temp.expect_failure($q$select public.accept_household_invite(current_setting('test.reissued')::uuid, 'Anonymous')$q$, 'permission denied');
reset role;
rollback;

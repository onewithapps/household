<img src="assets/icon.svg" width="64" height="64" alt="">

# Household

A SwiftUI home for a family in Sint-Lievens-Houtem, Belgium. The first milestone
focuses on individual accounts, joining the same household, and an existing shared
iCloud calendar. iPhone and iPad are the primary destinations; the native Mac target
remains available but is not the current product focus.

## Implemented

- Email-code sign-in and account creation through Supabase Auth, session restoration,
  and sign-out on the current device.
- Named profiles, household creation, member list, and partner invitations. Codes are
  bound to the invited email, expire after seven days, and can be accepted once.
  Creating a new invitation for the same email invalidates the old code.
- Database access policies that isolate each household. Membership and adult roles
  can only be assigned by checked database functions.
- Explicit selection of an Apple Calendar on each device, a 30-day agenda, and adding
  timed or single-day all-day events to writable calendars.
- Permission-denied, missing-calendar, empty-agenda, loading, and retry states.

## Connect a new Supabase project

1. Create a Supabase project, preferably in an EU region. There is no deployed project
   associated with this repository yet.
2. In its SQL Editor, run `supabase/migrations/202611230001_households.sql` once.
   Keep this file as migration history; future schema changes should be new migrations.
3. In Authentication, enable the Email provider and allow new user signups. Keep
   email verification enabled.
4. Configure the **Magic Link** email template to show an OTP code rather than a link.
   Also include the code in **Confirm signup** for first-time users. For example:

   ```html
   <h2>Your Household sign-in code</h2>
   <p>Enter this code in the Household app:</p>
   <p><strong>{{ .Token }}</strong></p>
   <p>If you did not request this code, ignore this email.</p>
   ```

   The app verifies the code directly; no redirect/deep-link setup is needed.
5. Configure custom SMTP for sending sign-in emails to you and Natasha. Supabase's
   default mail service restricts recipients to project-team addresses and has low
   sending limits; ordinary app accounts do not become project-team members.
   Test delivery before relying on sign-in. Respect configured OTP expiry and resend
   rate limits; the app displays service errors when a code cannot be sent or verified.
6. Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`.
   Fill in the project URL and **publishable key** (or legacy **anon** key) from the
   project's connection/API settings. Preserve the `https:/$()/` syntax in xcconfig.
   Never use a secret key or `service_role` key in the app. Local.xcconfig is git-ignored.

References: [Supabase email codes](https://supabase.com/docs/guides/auth/auth-email-passwordless),
[SMTP setup](https://supabase.com/docs/guides/auth/auth-smtp).

## Run on a Mac

Use **Xcode 16.3 or newer** (Swift 6.1 is required by the pinned Supabase SDK),
with iOS/iPadOS 17+ or macOS 14+.

1. Open `Household.xcodeproj` and allow Xcode to resolve the Supabase Swift package
   (pinned to version 2.55.7).
2. Select the Household scheme and an iPhone/iPad simulator or your device.
3. For devices, select your team under Signing & Capabilities and replace
   `com.example.household` with your unique bundle identifier.
4. Press Command-R. Without backend configuration, the app shows a setup screen.

You create your account using an email code, enter your name, and create the household.
In **Household → Invite your partner**, create a code for Natasha's email and share it
with her. Natasha signs in with that same email, selects **Join a household**, and
pastes the invitation code. Household invites are shared manually; the app does not
send invitation emails. Sign-in codes and household invitation codes are different.

## Connect your existing calendar

Make sure your shared iCloud calendar is already visible in Apple's Calendar app on
each device, including the kitchen iPad. In Household, open Calendar, allow full calendar
access, and choose that shared calendar. The picker shows source names to help identify
it. EventKit does not automatically identify which calendar belongs to your household.

Selection is local to each signed-in user/household/device. Events stay in Apple Calendar
and sync through iCloud; the app never uploads them to Supabase. Household membership
and iCloud sharing are separate: joining the household does not grant iCloud calendar
access. Apple handles calendar sharing and permissions.

The agenda refreshes when the view appears, the app returns to the foreground, EventKit
reports a change, or you refresh it manually. Changes made offline depend on Apple's
calendar sync when connectivity returns. Read-only calendars can be viewed but cannot
receive new events. Edit/delete/recurring-event management remains in Apple Calendar
for this first version.

## Verification

Database migration and access tests were executed on a temporary PostgreSQL 18 instance
on Linux with a minimal `auth.users`/`auth.uid()` harness. Tests cover household isolation,
valid partner acceptance, wrong email, expired and reused invitations, invitation
rotation, child invite restrictions, anonymous access, and prohibited direct writes.
This validates database logic, not hosted Supabase email delivery or its HTTP API.

Against a disposable Supabase database with the migration applied, run:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/household_access.sql
```

The test file inserts synthetic accounts inside a transaction and rolls everything back.
Use a local/test database, not a live household database.

The Xcode project references, source membership, property lists, and Swift syntax
were also checked. Syntax parsing does not type-check SwiftUI or SDK calls.

Xcode and Apple SDKs are unavailable in the development workspace. A device build and
these end-to-end checks are still required:

- Sign in with each email; try an invalid/expired OTP and resending a code.
- Relaunch to verify session restoration; sign out and switch accounts.
- Create a household, join from the second account, and verify both profile names.
- Try a wrong-email invitation and an already-used invitation.
- Disconnect the network: household loading should show an error/retry, not onboarding.
- Deny calendar access, then enable it in Settings and return to the app.
- Select the shared calendar on both devices. Add an event and check iCloud propagation.
- Check an empty and a read-only calendar, removal of a selected calendar, all-day
  events around daylight-saving changes, and resizing/rotation on iPad.

## Scope still to come

Children without accounts, profile editing, household ownership transfer/removal,
self-service account deletion, and broader account administration are not implemented.
The schema reserves a child role; this release only creates adult memberships.
Before public distribution, add account deletion, icons, privacy information, and
production mail delivery. Home Screen widgets, a dedicated kitchen display mode,
weather, waste collection, Netatmo, banking, and to-dos are subsequent milestones.

Created in [T3 Code](https://t3.codes).

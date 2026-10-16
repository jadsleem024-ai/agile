# Supabase setup — project `yuaevlnbmsildmyuiujr`

The app signs everyone in with **email + password**.

A **6-digit emailed code** is required exactly once, when the account is first
created, to prove the address is real. After that, signing in is password only —
no code. The one exception is an account that was created but never confirmed:
it gets a fresh sign-up code instead of being dead-ended.

## Status: configured and live

| Step | State |
|---|---|
| 1. Migration (tables, RLS, policies) | done — applied and verified |
| 2. Email provider enabled, confirm-email on | done |
| 3. OTP length set to 6 | done (was 8, which did not match the app) |
| 4. `{{ .Token }}` in both email templates | done |
| 5. Custom SMTP (Gmail) | done — verified sending |
| 6. Emails-per-hour limit raised 2 → 150 | done |
| 7. Admin account created | done — first sign-in is yours |
| 8. Coach codes generated | done — two ready |
| 9. Push notifications (coach alert on block complete) | **needs two things from you** — see below |

Nothing further is required to sign in. Push notifications need a Firebase
project before they will actually deliver — the app works fully without it,
the alert just does not go out yet.

---

## Live configuration

**SMTP** — Gmail, via an app password.

| Field | Value |
|---|---|
| Host | `smtp.gmail.com` |
| Port | `465` |
| Username | `agile.performances@gmail.com` |
| Sender | `AGILE <agile.performances@gmail.com>` |

Authentication is a Google **app password** on that account, not the account
password — the two are independent. Revoking the app password, or turning off
2-Step Verification, silently stops all codes from being delivered.

Gmail allows roughly 500 messages a day, well above what this roster needs.
If codes ever stop arriving, the app password has most likely been revoked on the
Google account — generate a new one at https://myaccount.google.com/apppasswords
and update it in Supabase → Project Settings → Authentication → SMTP Settings.

**Auth** — confirm-email on, 6-digit codes, 60-minute expiry, 150 emails/hour,
minimum password length 6.

**Email templates** — both "Confirm signup" and "Magic Link" render the code as
`{{ .Token }}`. This edit is rejected by Supabase on the free tier while the
default email sender is in use; configuring custom SMTP is what unlocks it.

---

## Signing in

The admin account, already created and confirmed:

- email: `agile.performances@gmail.com`
- password: `COACHJAD1`

Open the app → **Continue**. No code, no access code — the address is recognised
by the database as the admin, so it goes straight to the Admin Panel.

It owns all existing trainees, programs and library exercises — ownership was
transferred from the previous admin, which is now demoted to `pending` and has
no access.

To move the admin to a different address later, change the value inside
`public.admin_email()` and re-run that one function.

---

## Handing out codes

**Coach codes** — two are ready in the Admin Panel → **Codes** tab:

| Code | For |
|---|---|
| `C-HT4CM9` | Coach 1 |
| `C-U2WQ8A` | Coach 2 |

A new coach signs up with their own email, picks "I am a Coach", and enters one.
From then on they only see their own trainees, programs and exercises. Generate
more from that tab at any time.

**Trainee codes** — unchanged, created with the trainee in the Trainees tab. The
seven existing trainees keep the codes they already have, and all of them now
belong to the admin account:

| Trainee | Code |
|---|---|
| AFHJ | `ADHAM1` |
| Aleen sleeem | `ALEEN225` |
| HANADI | `HANADITHEBEAST` |
| joseffff | `5ASO` |
| Saja | `SAJA123` |
| Taghreed | `TAGHREED123` |
| TRIAL WORKOUT | `TRIAL1` |

A trainee signs up with their own email, picks "I am a Trainee", and enters their
code once to link the account.

---

## Data isolation

Enforced by Postgres row level security, not by app code — a modified client
cannot read another coach's rows.

`trainees`, `programs` and `exercise_library` carry a `coach_id`; `exercises`,
`trainee_programs` and `progress` inherit ownership through their parent. All
eight tables have RLS enabled with no permissive policies remaining.

> One thing worth knowing: this project previously had a policy called
> "Allow all access to exercise_library" with `USING (true)` for role `public`.
> Policies are OR'd together, so that single rule would have let every coach read
> every other coach's library regardless of everything else. The migration drops
> all pre-existing policies on these tables before creating its own, so the end
> state is deterministic.

---

## Backup

A JSON snapshot of all six tables was taken immediately before the migration:

```
C:\Users\Admin\coach_backup_20260911_145958\
```

7 trainees, 7 programs, 85 exercises, 377 progress rows, 108 library exercises,
9 rotation entries. Keep it until you are satisfied everything works.

---

## Re-running the migration

`supabase/migrations/001_multi_coach_auth.sql` is idempotent — safe to re-run
from Dashboard → SQL Editor if you ever need to restore the policies.

---

## Push notifications

When a trainee finishes every loop of their block, their coach gets a real
phone notification — it arrives even if AGILE is closed on the coach's phone.

Everything on the Supabase side and in the app is already built and deployed:
the `push_tokens` table, the `send-block-complete-push` edge function, and the
trigger in `advance_block_position()` that fires it at the exact moment a
block completes (tested end-to-end against the live database). What's missing
is a Firebase project — that step needs your Google account and a browser, so
it's the one part I couldn't do for you.

**Two things needed, both one-time:**

### 1. `google-services.json` — lets the Android app receive pushes at all

1. Go to https://console.firebase.google.com → **Create a project** (the free
   Spark plan is all this needs; no billing required).
2. Once created, click the **Android icon** to add an app.
3. Package name: `com.agile.coach` (must match exactly).
4. Skip the optional SHA-1 field — not needed here.
5. Download `google-services.json` when offered.
6. Send me that file (or paste its contents). I'll place it at
   `android/app/google-services.json` — it's gitignored, so it never ends up
   in the repo, same treatment as the signing keystore.

Until this file exists, the app builds and runs exactly as it does today —
nothing breaks, the coach alert just doesn't fire yet.

### 2. A service account key — lets the *server side* send through Firebase

1. In the Firebase console: **Project settings** (gear icon) → **Service accounts**.
2. Click **Generate new private key** → confirm. A `.json` file downloads.
3. Send me that file's contents.

I'll store it as a secret on the `send-block-complete-push` function (never
in the repo, never in this chat log beyond receiving it once) and the push
goes live immediately — no rebuild needed for this half.

### After both are in

Nothing else to configure. The next trainee who finishes their loops will
trigger a real notification to their coach's phone.

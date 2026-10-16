# Coach Panel + Trainee App — Flutter version

A from-scratch Flutter re-implementation of **both** React apps you shared:

1. **Coach Admin Panel** — Trainees / Programs / Progress management
2. **Trainee Workout App** — the code-based login screen trainees use to log
   their workouts, with per-set timers, rest timers, video demos, and program
   rotation

Both talk to the same Supabase project and are bundled in this single app.
The app opens on the **trainee login screen** (matching the original site's
behavior); entering the coach access code `COACHJAD1` jumps into the coach
panel, exactly like the web version's `/coach` redirect.

This is **source code only** — I can't compile an APK inside this sandbox
(no Android SDK / Gradle access here), but the steps below take about
5–10 minutes on your own machine.

## What's different from the React version

**Coach panel:**
- **Reordering**: uses Flutter's native drag-to-reorder (`ReorderableListView`)
  for the top-level exercise/group order — the standard mobile pattern.
- **Moving an exercise into a different group**: instead of free drag-and-drop
  between groups, each exercise has a "⋮" menu → **Move to group**, where you
  pick the target group from a list.
- Navigation is phone-shaped: tapping a program opens a dedicated screen
  (rather than the two-column desktop layout in the web app).

**Trainee app:**
- **localStorage → SharedPreferences**: login session and the in-flight rest
  timer's end-time are persisted the same way, just via Flutter's local
  storage instead of the browser's.
- **Web Audio beeps → bundled sound file**: the multi-burst "timer's up" beep
  pattern is reproduced using a small synthesized `assets/sounds/beep.wav`
  played on the same burst schedule as the original, via `audioplayers`.
- **Browser Notifications → flutter_local_notifications**: rest-timer-done
  alerts fire as local notifications. Like the original (which used
  `setTimeout` + the page's `Notification` object), this needs the app
  process to still be alive — it's not a true OS-level scheduled alarm, so
  its capability matches the original implementation rather than exceeding it.

Everything else — trainee login by code/name, program rotation & switching,
single/superset/triset/circuit exercise display, per-set weight/rep/time
tracking, exercise videos, notes, and workout history — works the same way
against the same Supabase project.

## Project layout

```
lib/
  main.dart                          # app entry, theme, opens on trainee login
  supabase_config.dart               # Supabase URL/anon key + client
  models/                            # Trainee, Program, Exercise, Workout, ProgressEntry...
  services/
    supabase_service.dart            # coach-side queries
    trainee_service.dart             # trainee-side queries (login, program, progress)
    local_storage.dart                # SharedPreferences wrapper (session + rest timer)
    audio_service.dart                # beep burst pattern playback
    notification_service.dart         # rest-timer-done local notification
  screens/
    coach_panel_screen.dart          # coach bottom nav shell
    trainees_tab.dart / programs_tab.dart / program_detail_screen.dart / progress_tab.dart
    trainee_login_screen.dart        # code/name entry, auto-login, coach code shortcut
    trainee_workout_screen.dart      # main trainee workout flow
  widgets/
    exercise_form_sheet.dart, set_rows_editor.dart, video_upload_field.dart   # coach side
    exercise_panel.dart, rest_timer_bar.dart, video_modal.dart                # trainee side
assets/
  sounds/beep.wav                    # synthesized beep used for timer alerts
```

## Building the APK

You'll need the Flutter SDK installed: https://docs.flutter.dev/get-started/install

```bash
# 1. From inside this folder, fetch dependencies
flutter pub get

# 2. Generate the native android/ (and ios/) platform folders.
#    Safe to run even though lib/ and pubspec.yaml already exist —
#    it only fills in the missing platform scaffolding.
flutter create .

# 3. Build the release APK
flutter build apk --release
```

The finished APK will be at:

```
build/app/outputs/flutter-apk/app-release.apk
```

Copy that file to your phone (or run `flutter install` with the phone
connected via USB debugging) to install it directly — no Play Store needed.

## Required manifest / permission tweaks (after step 2 above)

The trainee app adds a couple of native capabilities that need small manifest
edits — do these once, after `flutter create .` has generated `android/`:

**`android/app/src/main/AndroidManifest.xml`** — add inside `<manifest>`,
above `<application>`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
```

(`READ_MEDIA_VIDEO` is for the coach panel's video-upload picker on Android 13+;
`POST_NOTIFICATIONS` is for the trainee app's rest-timer alert.)

**iOS** (`ios/Runner/Info.plist`) — only needed if you also build for iOS:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to pick exercise demonstration videos</string>
```

## One-time Supabase check

Same Supabase project as before (same URL/key, already filled in in
`lib/supabase_config.dart`). Confirm in your Supabase dashboard that:

- A **Storage bucket named `videos`** exists with public-read access.
- Tables `trainees`, `programs`, `exercises`, `progress`, and `trainee_programs`
  exist with the columns both React apps relied on (`group_id`, `group_name`,
  `set_rows`, `each_side`, `set_weights`, etc.) — since this is the same
  backend, no schema changes are needed.

## Optional: app icon / name

- App name: edit `android/app/src/main/AndroidManifest.xml` → `android:label`
  (only exists after step 2 above).
- App icon: drop your icon into `assets/icon.png` and use the
  `flutter_launcher_icons` package if you want a custom one — not included
  here to keep the starter minimal.


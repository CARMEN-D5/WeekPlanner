# WeekPlanner authentication setup

The app contains this project's low-privilege Supabase publishable key so a
normal Android Studio Run works. No server secret is stored in source control.
Build defines can override the client configuration for another environment.

```powershell
flutter run --dart-define=SUPABASE_PUBLISHABLE_KEY=your_publishable_or_anon_key
flutter build apk --release --dart-define=SUPABASE_PUBLISHABLE_KEY=your_publishable_or_anon_key
```

Both values are optional for the default project. They can be overridden with
`--dart-define` for another environment.

Use only the Supabase publishable key (or legacy anon key). Never use a
`service_role` key, Google Client Secret, JWT signing secret, or database
password in a Flutter build.

In Supabase Auth URL Configuration, keep `weekplanner://login-callback` in the
redirect allow-list. Run `supabase/profiles.sql` once in SQL Editor.

# Server settings

The app connects to the local erims Supabase stack by default (debug builds only).
For production, build with the settings in `prod.json`:

    flutter run --release --dart-define-from-file=env/prod.json
    flutter build appbundle --dart-define-from-file=env/prod.json
    flutter build apk --dart-define-from-file=env/prod.json

`prod.json` holds the same URL and publishable key as erims's
`src/environments/environment.ts`. The publishable key is public by design;
never put the secret / service_role key here.

Optional keys:

- `DEFAULT_PASSWORD`: the password new canvasser logins get, shown to
  coordinators. Must match `CANVASSER_DEFAULT_PASSWORD` on the server
  (defaults to `@Haske123`).

A release build without `SUPABASE_URL` refuses to start rather than look for a
local server.

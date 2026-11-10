#!/usr/bin/env bash
# Puts the tutorial demo back to the start, ready for another take:
#   - a ward coordinator on the default password, who must choose a new one
#   - no canvasser onboarded yet
#   - the app on the emulator signed out, with its data cleared
#
# LOCAL ONLY. It talks to the erims Supabase stack on this computer and the
# names and phone numbers are made up. Don't point it at production.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../.."
url="http://127.0.0.1:58321"
adb="$HOME/Android/Sdk/platform-tools/adb"

coordinator_phone="2348005550101"
canvasser_phone="2348005550102"
ward_name="Lanwa"
ward_lga="Moro"

sql() { docker exec -i supabase_db_erims psql -U postgres -At -v ON_ERROR_STOP=1 "$@"; }

key="$(docker exec supabase_edge_runtime_erims printenv SUPABASE_SERVICE_ROLE_KEY)"
password="$(sed -nE "s/.*'DEFAULT_PASSWORD', defaultValue: '([^']+)'.*/\1/p" "$app/lib/config.dart")"
[ -n "$password" ] || { echo "Couldn't read the default password from lib/config.dart" >&2; exit 1; }

admin() {
  local method="$1" path="$2" body="$3"
  curl -sS --fail-with-body -o /dev/null -X "$method" "$url/auth/v1/admin/$path" \
    -H "apikey: $key" -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" -d "$body"
}

# The canvasser from the last take: their record first, then their login.
sql -c "delete from public.canvassers where phone = '+$canvasser_phone';" >/dev/null
old_canvasser="$(sql -c "select id from auth.users where phone = '$canvasser_phone';")"
[ -z "$old_canvasser" ] || admin DELETE "users/$old_canvasser" '{}'

# The coordinator's login, on the default password.
body=$(cat <<JSON
{"phone":"+$coordinator_phone","phone_confirm":true,"password":"$password",
 "user_metadata":{"full_name":"Amina Bello","must_change_password":true},
 "app_metadata":{"role":"Coordinator"}}
JSON
)
user_id="$(sql -c "select id from auth.users where phone = '$coordinator_phone';")"
if [ -z "$user_id" ]; then
  admin POST users "$body"
  user_id="$(sql -c "select id from auth.users where phone = '$coordinator_phone';")"
else
  admin PUT "users/$user_id" "$body"
fi

# The coordinator's posting.
sql >/dev/null <<SQL
insert into public.ward_coordinators (ward_id, first_name, last_name, phone, user_id)
select w.id, 'Amina', 'Bello', '+$coordinator_phone', '$user_id'
from public.wards w join public.lgas l on l.id = w.lga_id
where w.name = '$ward_name' and l.name = '$ward_lga'
on conflict (phone) do update set user_id = excluded.user_id;
SQL

# The app, back to a fresh install, if the emulator is up.
package="$(sed -nE 's/.*applicationId = "([^"]+)".*/\1/p' "$app/android/app/build.gradle.kts")"
if "$adb" get-state >/dev/null 2>&1; then
  "$adb" shell pm clear "$package" >/dev/null
  "$adb" shell settings put system show_touches 1
  echo "App data cleared on the emulator."
else
  echo "No emulator running, so the app was left alone."
fi

echo "Demo ready. Sign in with 0800 555 0101 and the default password."

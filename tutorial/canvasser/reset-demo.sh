#!/usr/bin/env bash
# Puts the canvassing tutorial demo back to the start, ready for another take:
#   - a made-up polling unit with made-up voters and a few earlier visits
#   - a canvasser on the default password, who must choose a new one
#   - the app on the emulator signed out, with its data cleared
#
#   ./reset-demo.sh          set up or reset the demo
#   ./reset-demo.sh remove   take every demo record back out
#
# LOCAL ONLY. It talks to the erims Supabase stack on this computer. The local
# voters table holds what looks like the real register, so the demo has its own
# polling unit and every statement below is limited to that unit or demo phones.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../.."
url="http://127.0.0.1:58321"
adb="$HOME/Android/Sdk/platform-tools/adb"

canvasser_phone="2348005550200"
unit_code="00-00-00-001"
unit_name="Demo Primary School"
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

# Everything recorded at the demo unit, so each take starts the same.
sql >/dev/null <<SQL
delete from public.canvass_visits where polling_unit_id in (select id from public.polling_units where code = '$unit_code');
delete from public.voters where polling_unit_id in (select id from public.polling_units where code = '$unit_code');
SQL

user_id="$(sql -c "select id from auth.users where phone = '$canvasser_phone';")"

if [ "${1:-}" = "remove" ]; then
  sql >/dev/null <<SQL
delete from public.canvassers where phone = '+$canvasser_phone';
delete from public.polling_units where code = '$unit_code';
SQL
  [ -z "$user_id" ] || admin DELETE "users/$user_id" '{}'
  echo "Demo records removed."
  exit 0
fi

body=$(cat <<JSON
{"phone":"+$canvasser_phone","phone_confirm":true,"password":"$password",
 "user_metadata":{"full_name":"Hauwa Ahmed","must_change_password":true},
 "app_metadata":{"role":"Canvasser"}}
JSON
)
if [ -z "$user_id" ]; then
  admin POST users "$body"
  user_id="$(sql -c "select id from auth.users where phone = '$canvasser_phone';")"
else
  admin PUT "users/$user_id" "$body"
fi

sql >/dev/null <<SQL
insert into public.polling_units (ward_id, code, name)
select w.id, '$unit_code', '$unit_name'
from public.wards w join public.lgas l on l.id = w.lga_id
where w.name = '$ward_name' and l.name = '$ward_lga'
  and not exists (select 1 from public.polling_units where code = '$unit_code');

insert into public.canvassers (polling_unit_id, first_name, last_name, phone, user_id)
select id, 'Hauwa', 'Ahmed', '+$canvasser_phone', '$user_id'
from public.polling_units where code = '$unit_code'
on conflict (phone) do update set user_id = excluded.user_id;

with unit as (select id from public.polling_units where code = '$unit_code')
insert into public.voters (polling_unit_id, name, phone, vin, gender, birth_year)
select unit.id, v.name, v.phone, v.vin, v.gender, v.birth_year
from unit, (values
  ('Abubakar Salihu', '+2348005550201', 'DEMO000000000001', 'M', 1978),
  ('Aisha Yusuf',     '+2348005550202', 'DEMO000000000002', 'F', 1990),
  ('Bashir Olawale',  null,             'DEMO000000000003', 'M', 1985),
  ('Fatima Abdullahi','+2348005550204', null,               'F', null),
  ('Grace Adeyemi',   '+2348005550205', 'DEMO000000000005', 'F', 1972),
  ('Ibrahim Jimoh',   '+2348005550206', 'DEMO000000000006', 'M', 1969),
  ('Kehinde Oyewole', '+2348005550207', 'DEMO000000000007', 'F', 1995),
  ('Mariam Bello',    '+2348005550208', 'DEMO000000000008', 'F', 1988),
  ('Mohammed Sani',   '+2348005550209', 'DEMO000000000009', 'M', 1981),
  ('Ruth Ojo',        '+2348005550210', 'DEMO000000000010', 'F', 1992),
  ('Sule Aliyu',      '+2348005550211', 'DEMO000000000011', 'M', 1975),
  ('Taiwo Akande',    '+2348005550212', 'DEMO000000000012', 'M', 1998),
  ('Yakubu Danjuma',  '+2348005550213', 'DEMO000000000013', 'M', 1965),
  ('Zainab Lawal',    '+2348005550214', 'DEMO000000000014', 'F', 1983)
) as v(name, phone, vin, gender, birth_year);

-- Earlier visits, so that the follow-up lists have people in them.
insert into public.canvass_visits (id, voter_id, canvasser_id, polling_unit_id, visited_at, support, pvc_status, plans_to_vote)
select gen_random_uuid(), voter.id, canvasser.id, voter.polling_unit_id, now() - interval '2 days', e.support, e.pvc, e.plans
from (values
  ('Grace Adeyemi',  'undecided',       'has_pvc',           'unsure'),
  ('Sule Aliyu',     'leaning_against', 'has_pvc',           'yes'),
  ('Ibrahim Jimoh',  'strong_support',  'has_pvc',           'yes'),
  ('Ruth Ojo',       'strong_support',  'has_pvc',           'yes'),
  ('Mohammed Sani',  'leaning_support', 'registered_no_pvc', 'yes'),
  ('Yakubu Danjuma', 'strong_support',  'has_pvc',           'unsure')
) as e(name, support, pvc, plans)
join public.voters voter on voter.name = e.name
  and voter.polling_unit_id = (select id from public.polling_units where code = '$unit_code')
join public.canvassers canvasser on canvasser.phone = '+$canvasser_phone';
SQL

package="$(sed -nE 's/.*applicationId = "([^"]+)".*/\1/p' "$app/android/app/build.gradle.kts")"
if "$adb" get-state >/dev/null 2>&1; then
  "$adb" shell cmd connectivity airplane-mode disable >/dev/null 2>&1 || true
  "$adb" shell pm clear "$package" >/dev/null
  "$adb" shell settings put system show_touches 1
  echo "App data cleared on the emulator."
else
  echo "No emulator running, so the app was left alone."
fi

echo "Demo ready. Sign in with 0800 555 0200 and the default password."

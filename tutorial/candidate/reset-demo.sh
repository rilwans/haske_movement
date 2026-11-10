#!/usr/bin/env bash
# Puts the candidate tutorial demo back to the start, ready for another take:
#   - a made-up "Demo State" with invented LGAs, team, voters and visits
#   - a candidate for its election, on the default password
#   - the app on the emulator signed out, with its data cleared
#
#   ./reset-demo.sh          set up or reset the demo
#   ./reset-demo.sh remove   take every demo record back out
#
# LOCAL ONLY. It talks to the erims Supabase stack on this computer. The local
# database holds what looks like real campaign data, so the demo is a whole
# state of its own, and every statement below is limited to that state.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../.."
url="http://127.0.0.1:58321"
adb="$HOME/Android/Sdk/platform-tools/adb"

candidate_phone="2348005550400"
state_code="ZZ"

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

# Deleting the candidate also deletes their login, by a trigger in erims.
sql >/dev/null <<SQL
do \$\$
declare st uuid;
begin
  select id into st from public.states where code = '$state_code' and name = 'Demo State';
  if st is null then return; end if;
  delete from public.canvass_visits where polling_unit_id in (
    select p.id from public.polling_units p join public.wards w on w.id = p.ward_id join public.lgas l on l.id = w.lga_id where l.state_id = st);
  delete from public.voters where polling_unit_id in (
    select p.id from public.polling_units p join public.wards w on w.id = p.ward_id join public.lgas l on l.id = w.lga_id where l.state_id = st);
  delete from public.canvassers where polling_unit_id in (
    select p.id from public.polling_units p join public.wards w on w.id = p.ward_id join public.lgas l on l.id = w.lga_id where l.state_id = st);
  delete from public.ward_coordinators where ward_id in (
    select w.id from public.wards w join public.lgas l on l.id = w.lga_id where l.state_id = st);
  delete from public.lga_coordinators where lga_id in (select id from public.lgas where state_id = st);
  delete from public.candidates where election_id in (select id from public.elections where state_id = st);
  delete from public.elections where state_id = st;
  delete from public.polling_units where ward_id in (
    select w.id from public.wards w join public.lgas l on l.id = w.lga_id where l.state_id = st);
  delete from public.wards where lga_id in (select id from public.lgas where state_id = st);
  delete from public.lgas where state_id = st;
  delete from public.states where id = st;
end \$\$;
SQL

if [ "${1:-}" = "remove" ]; then
  echo "Demo records removed."
  exit 0
fi

body=$(cat <<JSON
{"phone":"+$candidate_phone","phone_confirm":true,"password":"$password",
 "user_metadata":{"full_name":"Demo Candidate","must_change_password":true},
 "app_metadata":{"role":"Candidate"}}
JSON
)
user_id="$(sql -c "select id from auth.users where phone = '$candidate_phone';")"
if [ -z "$user_id" ]; then
  admin POST users "$body"
  user_id="$(sql -c "select id from auth.users where phone = '$candidate_phone';")"
else
  admin PUT "users/$user_id" "$body"
fi

sql >/dev/null <<SQL
do \$\$
declare
  st uuid; ele uuid; lga uuid; wrd uuid; pu uuid; cv uuid;
  config record;
  ward_no int; unit_no int; serial int := 0; team_no int := 0; coordinator_no int := 0;
  leaders text[] := array['Halima Garba', 'Sadiq Umar', 'Blessing Ade', 'Emeka Obi'];
begin
  perform setseed(0.42);
  insert into public.states (code, name) values ('$state_code', 'Demo State') returning id into st;

  insert into public.elections (type, name, election_date, state_id, code)
  values ('governorship', 'Demo State Governorship', current_date + 90, st, '998') returning id into ele;
  insert into public.candidates (election_id, party_id, full_name, phone, user_id)
  select ele, id, 'Demo Candidate', '+$candidate_phone', '$user_id' from public.parties where acronym = 'PDP';

  for config in select * from (values
    (1, 'Demo North',   150, 0.62, 0.32, 0.26, 'security'),
    (2, 'Demo South',   118, 0.41, 0.00, 0.20, 'roads'),
    (3, 'Demo East',     92, 0.33, 0.30, 0.24, 'water'),
    (4, 'Demo West',     75, 0.55, 0.06, 0.40, 'jobs'),
    (5, 'Demo Central',  60, 0.74, 0.34, 0.24, 'cost_of_living')
  ) as t(no, name, voters_per_unit, coverage, last_week, week_before, main_issue)
  loop
    insert into public.lgas (state_id, code, name)
    values (st, 'ZZ-0' || config.no, config.name) returning id into lga;

    -- Demo East has no LGA coordinator, so that it shows under Needs attention.
    if config.no <> 3 then
      coordinator_no := coordinator_no + 1;
      insert into public.lga_coordinators (lga_id, first_name, last_name, phone)
      values (lga, split_part(leaders[coordinator_no], ' ', 1), split_part(leaders[coordinator_no], ' ', 2), '+234800555041' || coordinator_no);
    end if;

    for ward_no in 1..3 loop
      insert into public.wards (lga_id, code, name)
      values (lga, 'ZZ-0' || config.no || '-0' || ward_no, replace(config.name, 'Demo ', '') || ' Ward ' || ward_no) returning id into wrd;
      for unit_no in 1..4 loop
        insert into public.polling_units (ward_id, code, name, registered_voters, collected_pvc, latitude, longitude)
        values (wrd, 'ZZ-0' || config.no || '-0' || ward_no || '-00' || unit_no, 'Demo Unit ' || unit_no,
                config.voters_per_unit + 40 + unit_no * 3, config.voters_per_unit - 10 + unit_no * 2,
                8.2 + config.no * 0.15 + ward_no * 0.02 + unit_no * 0.002, 4.2 + config.no * 0.15)
        returning id into pu;

        if unit_no = 1 then
          team_no := team_no + 1;
          insert into public.canvassers (polling_unit_id, first_name, last_name, phone)
          values (pu, 'Demo', 'Canvasser ' || team_no, '+23480055505' || lpad(team_no::text, 2, '0')) returning id into cv;
          -- The last ward of each LGA but the first has no coordinator: a coverage gap.
          if not (ward_no = 3 and config.no > 1) then
            insert into public.ward_coordinators (ward_id, first_name, last_name, phone)
            values (wrd, 'Demo', 'Coordinator ' || team_no, '+23480055506' || lpad(team_no::text, 2, '0'));
          end if;
        end if;

        insert into public.voters (polling_unit_id, name, phone, gender, birth_year)
        select pu, 'Demo Voter ' || (serial + n),
               case when random() < 0.62 then '+2348005' || lpad((serial + n)::text, 6, '0') end,
               case when random() < 0.9 then (array['M', 'F'])[1 + floor(random() * 2)::int] end,
               case when random() < 0.8 then 1955 + floor(random() * 50)::int end
        from generate_series(1, config.voters_per_unit) n;
        serial := serial + config.voters_per_unit;

        insert into public.canvass_visits (id, voter_id, canvasser_id, polling_unit_id, visited_at, support, pvc_status, plans_to_vote, issues, latitude, longitude)
        select gen_random_uuid(), v.id, cv, pu,
               now() - case
                 when r.w < config.last_week then interval '1 hour' + random() * interval '6 days'
                 when r.w < config.last_week + config.week_before then interval '7 days' + random() * interval '6 days'
                 else interval '15 days' + random() * interval '30 days' end,
               case when r.s < 0.38 then 'strong_support' when r.s < 0.60 then 'leaning_support' when r.s < 0.78 then 'undecided'
                    when r.s < 0.90 then 'leaning_against' else 'opposed' end,
               case when r.p < 0.70 then 'has_pvc' when r.p < 0.85 then 'registered_no_pvc' when r.p < 0.93 then 'not_registered' else 'unknown' end,
               case when r.v < 0.72 then 'yes' when r.v < 0.90 then 'unsure' else 'no' end,
               array[case when r.i < 0.55 then config.main_issue
                     else (array['security', 'roads', 'jobs', 'water', 'health', 'education', 'electricity', 'agriculture', 'cost_of_living'])[1 + floor(random() * 9)::int] end],
               8.2 + config.no * 0.15 + ward_no * 0.02 + unit_no * 0.002 + random() * 0.002,
               4.2 + config.no * 0.15 + random() * 0.002
        from public.voters v
        cross join lateral (select random() + v.birth_year * 0 as w, random() as s, random() as p, random() as v, random() as i) r
        where v.polling_unit_id = pu and random() < config.coverage;
      end loop;
    end loop;
  end loop;
end \$\$;
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

echo "Demo ready. Sign in with 0800 555 0400 and the default password."

#!/usr/bin/env bash
set -euo pipefail

export DB_DSN="${DB_DSN:-mysql:host=127.0.0.1;port=3306;dbname=einsatzberichte;charset=utf8mb4}"
export DB_USER="${DB_USER:-root}"
export DB_PASSWORD="${DB_PASSWORD:-test-password}"
export SETUP_TOKEN="${SETUP_TOKEN:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}"
export APP_URL="${APP_URL:-https://localhost}"
export MAIL_FROM="${MAIL_FROM:-einsatzberichte@localhost.test}"
base_url="${TEST_BASE_URL:-http://127.0.0.1:8080}"
session_cookie='session'
[[ "$base_url" == https://* ]] && session_cookie='__Host-session'
db_host="${TEST_DB_HOST:-127.0.0.1}"
mysql_tls_args=()
if mysql --help 2>&1 | grep -q -- '--ssl-mode'; then
  mysql_tls_args=(--ssl-mode=DISABLED)
elif mysql --help 2>&1 | grep -q -- '--skip-ssl'; then
  mysql_tls_args=(--skip-ssl)
fi

DB_DSN='' REQUEST_METHOD=GET REQUEST_URI=/api/bootstrap php api.php | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'
DB_DSN='' php -r '$_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REQUEST_URI"]="/ebmanager/api/bootstrap"; $_SERVER["SCRIPT_NAME"]="/ebmanager/api.php"; require "api.php";' | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'
DB_DSN='' php -r '$_COOKIE["session"]=str_repeat("a",64); $_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REQUEST_URI"]="/api/me"; require "api.php";' | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'
php -r '
  $html=file_get_contents("public/index.html");
  foreach (["viewport-fit=cover","class=\"skip-link\"","aria-label=\"Hauptnavigation\"","aria-live=\"polite\"","min-height:44px",":focus-visible","Auf Touch-Geräten","checkPendingDivera","divera?summary=1","Neue DIVERA-Einsätze","Letzter Import:"] as $required) {
    if (!str_contains($html,$required)) exit(1);
  }
  if (preg_match("/<select[^>]+multiple/i",$html)) exit(1);
'

if [[ -z "${TEST_BASE_URL:-}" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost -addext subjectAltName=DNS:localhost \
    -keyout smtp-key.pem -out smtp-cert.pem >/dev/null 2>&1
  php test/fake-smtp.php smtp-cert.pem smtp-key.pem >smtp-server.log 2>&1 &
  smtp_pid=$!
  export SMTP_HOST=localhost SMTP_PORT=2525 SMTP_USERNAME=test SMTP_PASSWORD=test SMTP_CA_FILE="$PWD/smtp-cert.pem"
  php -S 127.0.0.1:8080 api.php >php-server.log 2>&1 &
  server_pid=$!
  trap 'kill "$server_pid" "${smtp_pid:-}" 2>/dev/null || true; rm -f smtp-cert.pem smtp-key.pem; cat php-server.log smtp-server.log' EXIT
fi

if [[ "$base_url" == https://* ]]; then
  http_url="http://${base_url#https://}"
  test "$(curl --silent --output /dev/null --write-out '%{http_code}' "$http_url/")" = 301
  curl --insecure --silent --head "$base_url/" | grep --ignore-case --quiet '^Strict-Transport-Security: max-age=31536000'
fi

for _ in {1..20}; do
  curl --insecure --silent --fail "$base_url/api/bootstrap" >/dev/null && break
  sleep 0.25
done

test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --data '{"organization":"Testwehr"}' \
  "$base_url/api/setup")" = 415

test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"organization":"Testwehr","unit":"Löschzug","name":"Admin","email":"admin@example.test","password":"geheimes-passwort","setupToken":"falsch"}' \
  "$base_url/api/setup")" = 403

test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data "{\"organization\":\"Testwehr\",\"unit\":\"Löschzug\",\"name\":\"Admin\",\"email\":\"ungültig\",\"password\":\"geheimes-passwort\",\"setupToken\":\"$SETUP_TOKEN\"}" \
  "$base_url/api/setup")" = 400

curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data "{\"organization\":\"Testwehr\",\"unit\":\"Löschzug\",\"name\":\"Admin\",\"email\":\"admin@example.test\",\"password\":\"geheimes-passwort\",\"setupToken\":\"$SETUP_TOKEN\"}" \
  "$base_url/api/setup" | grep --quiet '"ok":true'

migration_token='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO sessions(token,user_id,expires_at) SELECT '$migration_token',id,UTC_TIMESTAMP()+INTERVAL 1 HOUR FROM users WHERE email='admin@example.test'"
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  <migrations/002-hash-session-tokens.sql
curl --insecure --silent --fail --cookie "$session_cookie=$migration_token" \
  "$base_url/api/me" | grep --quiet '"role":"wehrleitung"'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM sessions WHERE token=SHA2('$migration_token',256)"

curl --insecure --silent --fail --cookie-jar cookies.txt \
  --header 'Content-Type: application/json' \
  --header "Origin: $base_url" \
  --data '{"email":"admin@example.test","password":"geheimes-passwort"}' \
  "$base_url/api/login" | grep --quiet '"ok":true'

session_token=$(awk -v name="$session_cookie" '$6==name {print $7}' cookies.txt)
test "$session_token"
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT token=SHA2('$session_token',256) FROM sessions LIMIT 1")" = 1
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" \
  "$base_url/api/me" | grep --quiet '"role":"wehrleitung"'

curl --insecure --silent --fail --cookie-jar second-login-cookies.txt \
  --header 'Content-Type: application/json' \
  --header "Origin: $base_url" \
  --data '{"email":"admin@example.test","password":"geheimes-passwort"}' \
  "$base_url/api/login" | grep --quiet '"ok":true'
users_json=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/users")
printf '%s' "$users_json" | php -r '$users=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(count($users[0]["loginHistory"])===2); assert($users[0]["loginHistory"][0]>=$users[0]["loginHistory"][1]);'
rm -f second-login-cookies.txt

system_json=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/system")
printf '%s' "$system_json" | php -r '
  $data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
  if (($data["database"]["status"]??"")!=="Bereit" || count($data["units"]??[])!==1 || count($data["users"]??[])!==1) exit(1);
  $check=function(array $value) use (&$check) {
    foreach ($value as $key=>$item) {
      if (preg_match("/password|dsn|token|access.?key/i",(string)$key)) exit(1);
      if (is_array($item)) $check($item);
    }
  };
  $check($data);
'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DROP TABLE divera_imports"
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/system" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(str_contains($data["database"]["status"],"unvollständig"));'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  <migrations/005-divera-imports.sql

regular_token='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
regular_hash=$(php -r "echo hash('sha256', '$regular_token');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,unit_id,'Testkraft','testkraft@example.test',password_hash,'fuehrungskraft' FROM users WHERE email='admin@example.test'; SET @user_id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@user_id,1); INSERT INTO sessions(token,user_id,expires_at) VALUES('$regular_hash',@user_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR)"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$regular_token" "$base_url/api/system")" = 403
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM users WHERE email='testkraft@example.test'"

test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{"name":"Admin","email":"admin@example.test","role":"fuehrungskraft","unitIds":[1]}' \
  "$base_url/api/users/1")" = 409

test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --header 'Origin: https://angreifer.example.test' \
  --request POST \
  "$base_url/api/logout")" = 403

second_unit_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"name":"Löschgruppe"}' \
  "$base_url/api/units" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"name":"löschgruppe"}' \
  "$base_url/api/units")" = 409
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT COUNT(*) FROM units WHERE organization_id=1 AND name='Löschgruppe'")" = 1
invite_status=$(curl --insecure --silent --output invite.json --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "{\"name\":\"Eingeladene Person\",\"email\":\"invite@example.test\",\"role\":\"fuehrungskraft\",\"unitIds\":[1,$second_unit_id]}" \
  "$base_url/api/users")
case "$invite_status" in
  201)
    test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
      einsatzberichte --execute="SELECT COUNT(*) FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE u.email='invite@example.test'")" = 1
    invited_user_id=$(php -r '$data=json_decode(file_get_contents("invite.json"),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
    test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
      einsatzberichte --execute="SELECT COUNT(*) FROM user_units WHERE user_id=$invited_user_id")" = 2
    curl --insecure --silent --fail \
      --cookie "$session_cookie=$session_token" \
      --header 'Content-Type: application/json' \
      --request PUT \
      --data "{\"name\":\"Eingeladene Person\",\"email\":\"invite@example.test\",\"role\":\"fuehrungskraft\",\"unitIds\":[$second_unit_id]}" \
      "$base_url/api/users/$invited_user_id" | grep --quiet '"ok":true'
    test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
      einsatzberichte --execute="SELECT GROUP_CONCAT(unit_id ORDER BY unit_id) FROM user_units WHERE user_id=$invited_user_id")" = "$second_unit_id"
    MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
      --execute="DELETE FROM users WHERE email='invite@example.test'"
    ;;
  503)
    test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
      einsatzberichte --execute="SELECT COUNT(*) FROM users WHERE email='invite@example.test'")" = 0
    ;;
  *) cat invite.json >&2; exit 1 ;;
esac
if [[ -z "${TEST_BASE_URL:-}" ]]; then
  test "$invite_status" = 201
  wait "$smtp_pid"
  smtp_pid=''
fi
rm -f invite.json

test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"title":"Ungültiger Einsatz","startedAt":"morgen","address":"","unitIds":[1]}' \
  "$base_url/api/incidents")" = 400
incident_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "{\"title\":\"Testeinsatz\",\"startedAt\":\"2026-08-22T18:00:00.000Z\",\"address\":\"\",\"unitIds\":[$second_unit_id,1]}" \
  "$base_url/api/incidents" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  SECOND_UNIT_ID="$second_unit_id" php -r '$incidents=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $assignments=json_decode($incidents[0]["assignments"],true,512,JSON_THROW_ON_ERROR); $expected=[1,(int)getenv("SECOND_UNIT_ID")]; sort($expected); assert(array_column($assignments,"unitId")===$expected);'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO divera_imports(unit_id,incident_id,imported_by,imported_at) VALUES(1,$incident_id,1,'2026-08-23 09:00:00')"
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/units" |
  php -r '$units=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $unit=array_values(array_filter($units,fn($item)=>$item["id"]===1))[0]; assert($unit["last_divera_import_at"]==="2026-08-23T09:00:00.000Z");'

report_payload='{"unitId":1,"runningNumber":"69/2026","damagedParty":{"name":"Max Mustermann","phone":"02733 123","address":"Musterweg 1"},"damagingParty":{"name":"Erika Beispiel","phone":"","address":"Beispielweg 2"},"incidentCommand":{"rank":"BOI","name":"D. Gerlach","additionalRank":"BI","additionalName":"A. Busch"},"narrative":"Ursprünglich","departedAt":"2026-08-22T18:05:00.000Z","arrivedAt":"2026-08-22T18:10:00.000Z","endedAt":"2026-08-22T19:00:00.000Z","incidentType":"Technische Hilfe","classification":{"site":[],"cause":[],"technical":[]},"crew":[]}'
report_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "$report_payload" \
  "$base_url/api/incidents/$incident_id/reports" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
[[ "$report_id" =~ ^[0-9]+$ ]] || {
  echo "Ungültige report_id: $report_id" >&2
  exit 1
}
report_id_int=$((report_id))
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(report_year,'|',running_number,'|',JSON_UNQUOTE(JSON_EXTRACT(damaged_party,'$.name')),'|',JSON_UNQUOTE(JSON_EXTRACT(damaging_party,'$.name')),'|',JSON_UNQUOTE(JSON_EXTRACT(incident_command,'$.name'))) FROM reports WHERE id=$report_id_int")" = '2026|69/2026|Max Mustermann|Erika Beispiel|D. Gerlach'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO members(id,organization_id,divera_id,name) VALUES(101,1,'test-101','Person 101'),(102,1,'test-102','Person 102'); INSERT INTO member_units(member_id,unit_id) VALUES(101,1),(102,1); INSERT INTO report_crew(report_id,member_id) VALUES($report_id_int,102),($report_id_int,101)"
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $crew=json_decode($reports[0]["crew"],true,512,JSON_THROW_ON_ERROR); assert(array_column($crew,"memberId")===[101,102]);'

duplicate_incident_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"title":"Zweiter Testeinsatz","startedAt":"2026-08-22T18:00:00.000Z","address":"","unitIds":[1]}' \
  "$base_url/api/incidents" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "$report_payload" \
  "$base_url/api/incidents/$duplicate_incident_id/reports")" = 409

MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="START TRANSACTION; UPDATE reports SET status='released' WHERE id=$report_id_int; DO SLEEP(2); COMMIT;" &
release_pid=$!
sleep 0.25
edit_status=$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "${report_payload/Ursprünglich/Manipuliert}" \
  "$base_url/api/reports/$report_id")
wait "$release_pid"
test "$edit_status" = 409
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(status, ':', narrative) FROM reports WHERE id=$report_id_int")" = 'released:Ursprünglich'
released_at=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT released_at FROM reports WHERE id=$report_id_int")
sleep 1
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --request POST \
  "$base_url/api/reports/$report_id/release")" = 409
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT released_at FROM reports WHERE id=$report_id_int")" = "$released_at"

reset_token='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
reset_hash=$(php -r "echo hash('sha256', '$reset_token');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO password_resets(user_id,token_hash,expires_at) SELECT id,'$reset_hash',UTC_TIMESTAMP()+INTERVAL 30 MINUTE FROM users WHERE email='admin@example.test'"
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data "{\"token\":\"$reset_token\",\"password\":\"neues-geheimes-passwort\"}" \
  "$base_url/api/password-reset/confirm" | grep --quiet '"ok":true'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" "$base_url/api/me")" = 401
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data '{"email":"admin@example.test","password":"neues-geheimes-passwort"}' \
  "$base_url/api/login" | grep --quiet '"ok":true'

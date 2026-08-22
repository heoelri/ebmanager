#!/usr/bin/env bash
set -euo pipefail

export DB_DSN="${DB_DSN:-mysql:host=127.0.0.1;port=3306;dbname=einsatzberichte;charset=utf8mb4}"
export DB_USER="${DB_USER:-root}"
export DB_PASSWORD="${DB_PASSWORD:-test-password}"
export SETUP_TOKEN="${SETUP_TOKEN:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}"
base_url="${TEST_BASE_URL:-http://127.0.0.1:8080}"
db_host="${TEST_DB_HOST:-127.0.0.1}"
mysql_tls_args=()
if mysql --help 2>&1 | grep -q -- '--ssl-mode'; then
  mysql_tls_args=(--ssl-mode=DISABLED)
elif mysql --help 2>&1 | grep -q -- '--skip-ssl'; then
  mysql_tls_args=(--skip-ssl)
fi

DB_DSN='' REQUEST_METHOD=GET REQUEST_URI=/api/bootstrap php api.php | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'

if [[ -z "${TEST_BASE_URL:-}" ]]; then
  php -S 127.0.0.1:8080 api.php >php-server.log 2>&1 &
  server_pid=$!
  trap 'kill "$server_pid"; cat php-server.log' EXIT
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

curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data "{\"organization\":\"Testwehr\",\"unit\":\"Löschzug\",\"name\":\"Admin\",\"email\":\"admin@example.test\",\"password\":\"geheimes-passwort\",\"setupToken\":\"$SETUP_TOKEN\"}" \
  "$base_url/api/setup" | grep --quiet '"ok":true'

curl --insecure --silent --fail --cookie-jar cookies.txt \
  --header 'Content-Type: application/json' \
  --data '{"email":"admin@example.test","password":"geheimes-passwort"}' \
  "$base_url/api/login" | grep --quiet '"ok":true'

session_token=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute='SELECT token FROM sessions LIMIT 1')
curl --insecure --silent --fail --cookie "__Host-session=$session_token" \
  "$base_url/api/me" | grep --quiet '"role":"wehrleitung"'

test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "__Host-session=$session_token" \
  --header 'Content-Type: application/json' \
  --header 'Origin: https://angreifer.example.test' \
  --request POST \
  "$base_url/api/logout")" = 403

incident_id=$(curl --insecure --silent --fail \
  --cookie "__Host-session=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"title":"Testeinsatz","startedAt":"2026-08-22T18:00:00.000Z","address":"","unitIds":[1]}' \
  "$base_url/api/incidents" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')

report_payload='{"unitId":1,"narrative":"Ursprünglich","departedAt":"2026-08-22T18:05:00.000Z","arrivedAt":"2026-08-22T18:10:00.000Z","endedAt":"2026-08-22T19:00:00.000Z","incidentType":"Technische Hilfe","classification":{"site":[],"cause":[],"technical":[]},"crew":[]}'
report_id=$(curl --insecure --silent --fail \
  --cookie "__Host-session=$session_token" \
  --header 'Content-Type: application/json' \
  --data "$report_payload" \
  "$base_url/api/incidents/$incident_id/reports" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')

MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="START TRANSACTION; UPDATE reports SET status='released' WHERE id=$report_id; DO SLEEP(2); COMMIT;" &
release_pid=$!
sleep 0.25
edit_status=$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "__Host-session=$session_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "${report_payload/Ursprünglich/Manipuliert}" \
  "$base_url/api/reports/$report_id")
wait "$release_pid"
test "$edit_status" = 409
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(status, ':', narrative) FROM reports WHERE id=$report_id")" = 'released:Ursprünglich'

reset_token='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
reset_hash=$(php -r "echo hash('sha256', '$reset_token');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO password_resets(user_id,token_hash,expires_at) SELECT id,'$reset_hash',UTC_TIMESTAMP()+INTERVAL 30 MINUTE FROM users WHERE email='admin@example.test'"
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data "{\"token\":\"$reset_token\",\"password\":\"neues-geheimes-passwort\"}" \
  "$base_url/api/password-reset/confirm" | grep --quiet '"ok":true'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "__Host-session=$session_token" "$base_url/api/me")" = 401
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data '{"email":"admin@example.test","password":"neues-geheimes-passwort"}' \
  "$base_url/api/login" | grep --quiet '"ok":true'

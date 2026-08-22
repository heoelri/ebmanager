#!/usr/bin/env bash
set -euo pipefail

export DB_DSN="${DB_DSN:-mysql:host=127.0.0.1;port=3306;dbname=einsatzberichte;charset=utf8mb4}"
export DB_USER="${DB_USER:-root}"
export DB_PASSWORD="${DB_PASSWORD:-test-password}"
export SETUP_TOKEN="${SETUP_TOKEN:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}"
base_url="${TEST_BASE_URL:-http://127.0.0.1:8080}"
db_host="${TEST_DB_HOST:-127.0.0.1}"

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

session_token=$(MYSQL_PWD="$DB_PASSWORD" mysql --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute='SELECT token FROM sessions LIMIT 1')
curl --insecure --silent --fail --cookie "session=$session_token" \
  "$base_url/api/me" | grep --quiet '"role":"wehrleitung"'

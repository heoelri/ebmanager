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
divera_log="${TMPDIR:-/tmp}/divera-requests-$$.log"
[[ "${DIVERA_API_BASE_URL:-}" == 'http://divera:8090' ]] && divera_log=/tmp/divera/requests.log
divera_pid=''
incident_status() {
  curl --insecure --silent --fail --cookie "$session_cookie=$1" "$base_url/api/incidents" |
    INCIDENT_ID="$2" php -r '$items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $matches=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID"))); assert(count($matches)===1); echo $matches[0]["reportStatus"]["key"];'
}
assert_pdf() {
  local token=$1 path=$2 expected=$3 forbidden=${4:-}
  local body="${TMPDIR:-/tmp}/export-$$.pdf" headers="${TMPDIR:-/tmp}/export-$$.headers"
  curl --insecure --silent --fail --cookie "$session_cookie=$token" --dump-header "$headers" --output "$body" "$base_url$path"
  grep --ignore-case --quiet '^Content-Type: application/pdf' "$headers"
  grep --ignore-case --quiet '^Content-Disposition: attachment; filename="[A-Za-z0-9._-]*\.pdf"' "$headers"
  PDF_BODY="$body" PDF_EXPECTED="$expected" PDF_FORBIDDEN="$forbidden" php -r '
    $pdf=file_get_contents(getenv("PDF_BODY"));
    assert(str_starts_with($pdf,"%PDF-1.4"));
    assert(str_ends_with($pdf,"%%EOF\n"));
    foreach(explode("|",getenv("PDF_EXPECTED")) as $text) assert(str_contains($pdf,iconv("UTF-8","Windows-1252//TRANSLIT",$text)));
    if (getenv("PDF_FORBIDDEN")!=="") assert(!str_contains($pdf,iconv("UTF-8","Windows-1252//TRANSLIT",getenv("PDF_FORBIDDEN"))));
  '
  rm -f "$body" "$headers"
}
if mysql --help 2>&1 | grep -- '--ssl-mode' >/dev/null; then
  mysql_tls_args=(--ssl-mode=DISABLED)
elif mysql --help 2>&1 | grep -- '--skip-ssl' >/dev/null; then
  mysql_tls_args=(--skip-ssl)
fi

# Fehlende Datenbankkonfiguration wird bei Root-, Unterverzeichnis- und authentifizierten Anfragen gemeldet.
DB_DSN='' REQUEST_METHOD=GET REQUEST_URI=/api/bootstrap php api.php | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'
DB_DSN='' php -r '$_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REQUEST_URI"]="/ebmanager/api/bootstrap"; $_SERVER["SCRIPT_NAME"]="/ebmanager/api.php"; require "api.php";' | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'
DB_DSN='' php -r '$_COOKIE["session"]=str_repeat("a",64); $_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REQUEST_URI"]="/api/me"; require "api.php";' | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'

# Die testweise überschreibbare DIVERA-Basisadresse enthält ausschließlich Schema, Host und optionalen Port.
DIVERA_API_BASE_URL='http://divera:8090/' php -r 'require "support.php"; if (diveraBaseUrl()!=="http://divera:8090") exit(1);'
for invalid_divera_url in 'https://host?x=1' 'https://user@host' 'https://host/path' 'https://host#fragment'; do
  DIVERA_API_BASE_URL="$invalid_divera_url" php -r 'require "support.php"; try { diveraBaseUrl(); exit(1); } catch (ApiError $error) { if ($error->status!==503) exit(1); }'
done

# Der Renderer erzeugt mehrseitige PDFs mit Umlauten und Exportmetadaten auf jeder Seite.
php -r '
  require "support.php";
  $pdf=pdfBinary("Prüfung",array_fill(0,120,["text"=>"Übung","bold"=>false]),"Nutzer: Prüfer | Rolle: Führungskraft");
  assert(str_starts_with($pdf,"%PDF-1.4"));
  assert(str_ends_with($pdf,"%%EOF\n"));
  assert(preg_match("#/Count ([3-9])#",$pdf));
  assert(substr_count($pdf,iconv("UTF-8","Windows-1252//TRANSLIT","Nutzer: Prüfer"))>=3);
  assert(str_contains($pdf,iconv("UTF-8","Windows-1252//TRANSLIT","Übung")));
  try { @pdfEncode("\xFF"); exit(1); } catch (ApiError $error) {
    assert($error->status===503);
    assert($error->getMessage()==="PDF-Text konnte nicht kodiert werden");
  }
'

# Das Frontend enthält die erwarteten Accessibility- und DIVERA-Elemente, lässt inaktive Besatzung entfernen und dupliziert keine Fachoptionen.
php -r '
  $html=file_get_contents("public/index.html");
  $javascript=file_get_contents("public/app.js");
  $frontend=$html.$javascript;
  $css=file_get_contents("public/styles.css");
  foreach (["viewport-fit=cover","public/styles.css","public/app.js","class=\"skip-link\"","aria-label=\"Hauptnavigation\"","aria-live=\"polite\"","Auf Touch-Geräten","checkPendingDivera","divera?summary=1","Neue DIVERA-Einsätze","Letzter Import:","rankOptions","pendingWarning","initialView","DIVERA-Einsatznummer","class=\"command-row\"","class=\"form-section\"","class=\"report-times\"","restoreDialogFocus","zone.key==='available'||zone.key===current","!zone.historical||zone.key===current","<select name=\"commandRank\">","<select name=\"additionalCommandRank\">"] as $required) {
    if (!str_contains($frontend,$required)) exit(1);
  }
  foreach (["--control-height: 44px",":focus-visible","safe-area-inset-bottom","forced-colors: active"] as $required) {
    if (!str_contains($css,$required)) exit(1);
  }
  if (str_contains($html,"<style") || preg_match("/<script(?![^>]*\\s+src\\s*=)[^>]*>/i",$html) || preg_match("/\\son[a-z]+=/i",$frontend) || preg_match("/\\sstyle=\"/i",$frontend)) exit(1);
  foreach (["Kleinbrand","Wohngebäude","Menschen in Notlage","Feuerwehrmann-Anwärter"] as $duplicatedOption) {
    if (str_contains($frontend,$duplicatedOption)) exit(1);
  }
  if (preg_match("/<select[^>]+multiple/i",$frontend)) exit(1);
'

# Fachoptionen sind vorhanden und ihre Klassifikationsschlüssel stimmen mit den Gruppenbezeichnungen überein.
php -r 'require "constants.php"; assert(RANKS["BM"]==="Brandmeister"); assert(RANKS["GBI"]==="Gemeindebrandinspektor"); assert(RANKS["SBI"]==="Stadtbrandinspektor"); assert(array_key_last(RANKS)==="SBI"); assert(INCIDENT_TYPES!==[]); assert(array_keys(CLASSIFICATIONS)===array_keys(CLASSIFICATION_LABELS));'

# Ohne externen Testserver werden lokale HTTP- und SMTP-Testserver gestartet.
if [[ -z "${TEST_BASE_URL:-}" ]]; then
  export DIVERA_API_BASE_URL=http://127.0.0.1:8090 DIVERA_REQUEST_LOG="$divera_log"
  php -S 127.0.0.1:8090 test/fake-divera.php >divera-server.log 2>&1 &
  divera_pid=$!
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost -addext subjectAltName=DNS:localhost \
    -keyout smtp-key.pem -out smtp-cert.pem >/dev/null 2>&1
  rm -f smtp-messages.log
  php test/fake-smtp.php smtp-cert.pem smtp-key.pem 1 smtp-messages.log >smtp-server.log 2>&1 &
  smtp_pid=$!
  export SMTP_HOST=localhost SMTP_PORT=2525 SMTP_USERNAME=test SMTP_PASSWORD=test SMTP_CA_FILE="$PWD/smtp-cert.pem"
  php -S 127.0.0.1:8080 api.php >php-server.log 2>&1 &
  server_pid=$!
  trap 'kill "$server_pid" "${smtp_pid:-}" "${divera_pid:-}" 2>/dev/null || true; rm -f smtp-cert.pem smtp-key.pem "$divera_log"; cat php-server.log smtp-server.log divera-server.log' EXIT
fi
sleep 0.25

# Das HTTPS-Deployment leitet HTTP um und sendet HSTS.
if [[ "$base_url" == https://* ]]; then
  http_url="http://${base_url#https://}"
  test "$(curl --silent --output /dev/null --write-out '%{http_code}' "$http_url/")" = 301
  curl --insecure --silent --head "$base_url/" | grep --ignore-case --quiet '^Strict-Transport-Security: max-age=31536000'
fi

# Der Bootstrap-Endpunkt muss innerhalb eines begrenzten Zeitfensters erreichbar werden.
bootstrap_ready=false
for _ in {1..60}; do
  if curl --insecure --silent --fail "$base_url/api/bootstrap" >/dev/null; then
    bootstrap_ready=true
    break
  fi
  sleep 0.5
done
if [[ "$bootstrap_ready" != true ]]; then
  echo "Bootstrap-Endpunkt unter $base_url/api/bootstrap ist nicht erreichbar." >&2
  curl --insecure --silent --show-error "$base_url/api/bootstrap" >&2 || true
  exit 1
fi

# Setup-Anfragen ohne JSON-Content-Type werden abgelehnt.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --data '{"organization":"Testwehr"}' \
  "$base_url/api/setup")" = 415

# Ein ungültiges Setup-Token wird abgelehnt.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"organization":"Testwehr","unit":"Löschzug","name":"Admin","email":"admin@example.test","password":"geheimes-passwort","setupToken":"falsch"}' \
  "$base_url/api/setup")" = 403

# Das Setup validiert die E-Mail-Adresse.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data "{\"organization\":\"Testwehr\",\"unit\":\"Löschzug\",\"name\":\"Admin\",\"email\":\"ungültig\",\"password\":\"geheimes-passwort\",\"setupToken\":\"$SETUP_TOKEN\"}" \
  "$base_url/api/setup")" = 400

# Ein gültiges Setup legt Organisation, Einheit und erste Wehrleitung an.
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data "{\"organization\":\"Testwehr\",\"unit\":\"Löschzug\",\"name\":\"Admin\",\"email\":\"admin@example.test\",\"password\":\"geheimes-passwort\",\"setupToken\":\"$SETUP_TOKEN\"}" \
  "$base_url/api/setup" | grep --quiet '"ok":true'

# Der Login erzeugt eine nutzbare Sitzung und speichert ausschließlich deren SHA-256-Hash.
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

# Der Options-Endpunkt liefert exakt die zentral konfigurierten Einsatzarten und Klassifikationen.
options_json=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/options")
printf '%s' "$options_json" | php -r '
  require "constants.php";
  $options=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
  assert($options["ranks"]===RANKS);
  assert($options["incidentTypes"]===INCIDENT_TYPES);
  assert($options["classifications"]===CLASSIFICATIONS);
  assert($options["classificationLabels"]===CLASSIFICATION_LABELS);
'

# Apache verhindert den direkten HTTP-Zugriff auf die zentrale Konstantendatei.
if [[ "$base_url" == https://* ]]; then
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' "$base_url/constants.php")" = 403
fi

# Die Benutzerverwaltung zeigt auch nach wiederholten Anmeldungen nur die letzte Anmeldung.
weak_password_hash=$(php -r 'echo password_hash("geheimes-passwort", PASSWORD_BCRYPT, ["cost"=>4]);')
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE users SET password_hash='$weak_password_hash' WHERE email='admin@example.test'"
curl --insecure --silent --fail --cookie-jar second-login-cookies.txt \
  --header 'Content-Type: application/json' \
  --header "Origin: $base_url" \
  --data '{"email":"admin@example.test","password":"geheimes-passwort"}' \
  "$base_url/api/login" | grep --quiet '"ok":true'
current_password_hash=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT password_hash FROM users WHERE email='admin@example.test'")
WEAK_HASH="$weak_password_hash" CURRENT_HASH="$current_password_hash" php -r '
  assert(getenv("CURRENT_HASH")!==getenv("WEAK_HASH"));
  assert(password_verify("geheimes-passwort",getenv("CURRENT_HASH")));
  assert(!password_needs_rehash(getenv("CURRENT_HASH"),PASSWORD_DEFAULT));
'
users_json=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/users")
printf '%s' "$users_json" | php -r '$users=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); exit(count($users[0]["loginHistory"])===1 ? 0 : 1);'
rm -f second-login-cookies.txt

# Die Systemübersicht enthält erwartete Statusdaten, aber keine Zugangsdaten oder Tokens.
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

# Ein fehlender Schemateil wird als unvollständige Datenbank erkannt.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="RENAME TABLE divera_imports TO divera_imports_missing"
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/system" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(str_contains($data["database"]["status"],"unvollständig"));'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="RENAME TABLE divera_imports_missing TO divera_imports"

# Führungskräfte ohne Wehrleitungsrolle dürfen weder Systemübersicht noch Nutzerverwaltung aufrufen.
regular_token='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
regular_hash=$(php -r "echo hash('sha256', '$regular_token');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,1,'Testkraft','testkraft@example.test',password_hash,'fuehrungskraft' FROM users WHERE email='admin@example.test'; SET @user_id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@user_id,1); INSERT INTO sessions(token,user_id,expires_at) VALUES('$regular_hash',@user_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR)"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$regular_token" "$base_url/api/system")" = 403
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$regular_token" "$base_url/api/users")" = 403
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM users WHERE email='testkraft@example.test'"

# Die letzte Wehrleitung eines Mandanten kann nicht herabgestuft werden.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{"name":"Admin","email":"admin@example.test","role":"fuehrungskraft","unitIds":[1]}' \
  "$base_url/api/users/1")" = 409

# Zustandsändernde Anfragen mit fremdem Origin werden abgewehrt.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --header 'Origin: https://angreifer.example.test' \
  --request POST \
  "$base_url/api/logout")" = 403

# Einheitsnamen sind innerhalb einer Wehr ohne Beachtung der Groß-/Kleinschreibung eindeutig.
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

# Einladungen gelten sieben Tage, nennen ihr Ablaufdatum und Nutzer können mehreren Einheiten zugeordnet werden.
invite_status=$(curl --insecure --silent --output invite.json --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "{\"name\":\"Eingeladene Person\",\"email\":\"invite@example.test\",\"role\":\"fuehrungskraft\",\"unitIds\":[1,$second_unit_id]}" \
  "$base_url/api/users")
case "$invite_status" in
  201)
    invite_expiry=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
      einsatzberichte --execute="SELECT expires_at FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE u.email='invite@example.test'")
    test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
      einsatzberichte --execute="SELECT ABS(TIMESTAMPDIFF(SECOND,expires_at,UTC_TIMESTAMP()+INTERVAL 7 DAY))<=2 FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE u.email='invite@example.test'")" = 1
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
  grep --quiet 'Recipient: invite@example.test' smtp-messages.log
  grep --quiet 'Subject: Konto aktivieren' smtp-messages.log
  grep --quiet '#invite=' smtp-messages.log
  ! grep --quiet '?invite=' smtp-messages.log
  expected_invite_expiry=$(INVITE_EXPIRY="$invite_expiry" php -r '$date=(new DateTimeImmutable(getenv("INVITE_EXPIRY"),new DateTimeZone("UTC")))->setTimezone(new DateTimeZone("Europe/Berlin")); echo $date->format("d.m.Y")." um ".$date->format("H:i")." Uhr";')
  grep --fixed-strings --quiet "Der Link ist bis zum $expected_invite_expiry (Europe/Berlin) gültig." smtp-messages.log
fi
rm -f invite.json

# Einsätze akzeptieren ausschließlich gültige ISO-Zeitpunkte.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"title":"Ungültiger Einsatz","startedAt":"morgen","address":"","unitIds":[1]}' \
  "$base_url/api/incidents")" = 400

# Einsatzzuordnungen werden vollständig und stabil nach Einheit sortiert ausgegeben.
incident_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "{\"title\":\"Testeinsatz\",\"startedAt\":\"2026-08-22T18:00:00.000Z\",\"address\":\"\",\"unitIds\":[$second_unit_id,1]}" \
  "$base_url/api/incidents" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  SECOND_UNIT_ID="$second_unit_id" php -r '$incidents=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $assignments=json_decode($incidents[0]["assignments"],true,512,JSON_THROW_ON_ERROR); $expected=[1,(int)getenv("SECOND_UNIT_ID")]; sort($expected); assert(array_column($assignments,"unitId")===$expected); assert($incidents[0]["reportStatus"]["key"]==="reports_pending"); assert(count($incidents[0]["reportStatus"]["pendingUnits"])===2);'

# Der letzte erfolgreiche DIVERA-Import wird je Einheit als UTC-Zeitpunkt ausgegeben.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO divera_imports(unit_id,incident_id,imported_by,imported_at) VALUES(1,$incident_id,1,'2026-08-23 09:00:00')"
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/units" |
  php -r '$units=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $unit=array_values(array_filter($units,fn($item)=>$item["id"]===1))[0]; assert($unit["last_divera_import_at"]==="2026-08-23T09:00:00.000Z");'

# Einheitsführungen gehören exakt einer Einheit an; Führungskräfte dürfen mehreren Einheiten angehören.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "{\"name\":\"Ungültige Leitung\",\"email\":\"invalid-leader@example.test\",\"role\":\"einheitsleitung\",\"unitIds\":[1,$second_unit_id]}" \
  "$base_url/api/users")" = 400

leader_token='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
leader_hash=$(php -r "echo hash('sha256', '$leader_token');")
force_token='ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
force_hash=$(php -r "echo hash('sha256', '$force_token');")
other_force_token='abababababababababababababababababababababababababababababababab'
other_force_hash=$(php -r "echo hash('sha256', '$other_force_token');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,1,'Einheitsleitung Eins','leitung1@example.test',password_hash,'einheitsleitung' FROM users WHERE email='admin@example.test';
    SET @leader_id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@leader_id,1); INSERT INTO sessions(token,user_id,expires_at) VALUES('$leader_hash',@leader_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR);
    INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,1,'Führungskraft Test','fuehrungskraft@example.test',password_hash,'fuehrungskraft' FROM users WHERE email='admin@example.test';
    SET @force_id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@force_id,1); INSERT INTO sessions(token,user_id,expires_at) VALUES('$force_hash',@force_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR);
    INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,1,'Weitere Führungskraft','weitere-fuehrungskraft@example.test',password_hash,'fuehrungskraft' FROM users WHERE email='admin@example.test';
    SET @other_force_id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@other_force_id,1); INSERT INTO sessions(token,user_id,expires_at) VALUES('$other_force_hash',@other_force_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR)"
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE incident_units SET vehicles=JSON_ARRAY(JSON_OBJECT('id','foreign-secret','name','Fremdfahrzeug','own',TRUE)) WHERE incident_id=$incident_id AND unit_id=$second_unit_id"

# Nicht-Wehrführungen sehen nur aktuell zugeordnete Einheiten, Fahrzeuge und rollenbezogene Berichtsstatus.
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units" |
  php -r '$units=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(array_column($units,"id")===[1]);'
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '
    $items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
    $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0];
    $assignments=json_decode($incident["assignments"],true,512,JSON_THROW_ON_ERROR);
    assert(array_column($assignments,"unitId")===[1]);
    assert($incident["units"]==="Löschzug");
    assert(!str_contains(json_encode($incident),"Fremdfahrzeug"));
  '
test "$(incident_status "$force_token" "$incident_id")" = report_required
test "$(incident_status "$leader_token" "$incident_id")" = report_required

# Berichte starten rollenabhängig, bleiben bis zur jeweiligen Übergabe verborgen und speichern die Fachdaten.
report_payload='{"unitId":1,"foreign_id":"manipuliert","divera_id":"manipuliert","runningNumber":"69/2026","damagedParty":{"name":"Max Mustermann","phone":"02733 123","address":"Musterweg 1"},"damagingParty":{"name":"Erika Beispiel","phone":"","address":"Beispielweg 2"},"incidentCommand":{"rank":"BOI","name":"D. Gerlach","additionalRank":"BI","additionalName":"A. Busch"},"narrative":"Ursprünglich","departedAt":"2026-08-22T18:05:00.000Z","arrivedAt":"2026-08-22T18:10:00.000Z","endedAt":"2026-08-22T19:00:00.000Z","incidentType":"Technische Hilfe","classification":{"site":[],"cause":[],"technical":[]},"crew":[]}'
report_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" \
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
  einsatzberichte --execute="SELECT CONCAT(status,'|',report_year,'|',running_number,'|',JSON_UNQUOTE(JSON_EXTRACT(damaged_party,'$.name')),'|',JSON_UNQUOTE(JSON_EXTRACT(damaging_party,'$.name')),'|',JSON_UNQUOTE(JSON_EXTRACT(incident_command,'$.rank')),'|',JSON_UNQUOTE(JSON_EXTRACT(incident_command,'$.name'))) FROM reports WHERE id=$report_id_int")" = 'author_draft|2026|69/2026|Max Mustermann|Erika Beispiel|BOI|D. Gerlach'
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(COALESCE(foreign_id,''),'|',COALESCE(divera_id,'')) FROM incidents WHERE id=$incident_id")" = '|'

# Ausrücke- und Eintreffzeit können bei einem abgebrochenen Einsatz geleert werden.
report_without_travel_times="${report_payload/\"departedAt\":\"2026-08-22T18:05:00.000Z\",\"arrivedAt\":\"2026-08-22T18:10:00.000Z\"/\"departedAt\":null,\"arrivedAt\":null}"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "$report_without_travel_times" \
  "$base_url/api/reports/$report_id")" = 200
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT departed_at IS NULL AND arrived_at IS NULL FROM reports WHERE id=$report_id_int")" = 1

test "$(curl --insecure --silent --fail --cookie "$session_cookie=$leader_token" "$base_url/api/incidents/$incident_id/reports")" = '[]'
test "$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents/$incident_id/reports")" = '[]'
test "$(incident_status "$force_token" "$incident_id")" = report_required
test "$(incident_status "$other_force_token" "$incident_id")" = report_exists
test "$(incident_status "$leader_token" "$incident_id")" = awaiting_report
assert_pdf "$force_token" "/api/reports/$report_id/pdf" 'Einzelbericht|Führungskraft Test|Rolle: Führungskraft|Ursprünglich|Max Mustermann'
assert_pdf "$force_token" "/api/incidents/$incident_id/pdf" 'Rollenbezogene Einsatzakte|Führungskraft Test|Rolle: Führungskraft|Ursprünglich' 'Fremdfahrzeug'
assert_pdf "$other_force_token" "/api/incidents/$incident_id/pdf" 'Rollenbezogene Einsatzakte|Weitere Führungskraft|Rolle: Führungskraft|Testeinsatz' 'Ursprünglich'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$leader_token" "$base_url/api/reports/$report_id/pdf")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/reports/$report_id/pdf")" = 404

# PDF-Endpunkte geben keine Daten eines fremden Mandanten preis.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO organizations(id,name) VALUES(900,'Fremde Wehr');
    INSERT INTO units(id,organization_id,name) VALUES(900,900,'Fremde Einheit');
    INSERT INTO users(id,organization_id,unit_id,name,email,password_hash,role) VALUES(900,900,NULL,'Fremde Wehrführung','fremd@example.test','x','wehrleitung');
    INSERT INTO incidents(id,organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text,consolidated_at) VALUES(900,900,'Fremder Einsatz','2026-08-22T18:00:00.000Z','','','','','','Fremd konsolidiert',UTC_TIMESTAMP());
    INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(900,900,JSON_ARRAY());
    INSERT INTO reports(id,incident_id,unit_id,author_id,narrative,vehicles,personnel,classification,status) VALUES(900,900,900,900,'Fremder Bericht','','',JSON_OBJECT(),'wehr_review');
    INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,created_at) VALUES(900,NULL,'wehr_review',900,'Fremde Wehrführung','wehrleitung',UTC_TIMESTAMP())"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/incidents/900/pdf")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/reports/900/pdf")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/incidents/900/consolidation/pdf")" = 404

# Besatzungsmitglieder werden unabhängig von der Einfügereihenfolge stabil sortiert ausgegeben.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO members(id,organization_id,divera_id,name) VALUES(101,1,'test-101','Person 101'),(102,1,'test-102','Person 102'); INSERT INTO member_units(member_id,unit_id) VALUES(101,1),(102,1); INSERT INTO report_crew(report_id,member_id) VALUES($report_id_int,102),($report_id_int,101)"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $crew=json_decode($reports[0]["crew"],true,512,JSON_THROW_ON_ERROR); assert(array_column($crew,"memberId")===[101,102]);'

# Laufende Nummern sind pro Einheit und Kalenderjahr eindeutig.
duplicate_incident_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"title":"Zweiter Testeinsatz","startedAt":"2026-08-22T18:00:00.000Z","address":"","unitIds":[1]}' \
  "$base_url/api/incidents" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --cookie "$session_cookie=$force_token" \
  --data "$report_payload" \
  "$base_url/api/incidents/$duplicate_incident_id/reports")" = 409

# Berichte mit nicht chronologischen Einsatzzeiten werden abgelehnt.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --cookie "$session_cookie=$force_token" \
  --data '{"unitId":1,"runningNumber":"98/2026","damagedParty":{},"damagingParty":{},"incidentCommand":{},"narrative":"Test","departedAt":"2026-08-22T19:30:00.000Z","arrivedAt":"2026-08-22T18:30:00.000Z","endedAt":"2026-08-22T20:00:00.000Z","incidentType":"Technische Hilfe","classification":{"site":[],"cause":[],"technical":[]},"crew":[]}' \
  "$base_url/api/incidents/$duplicate_incident_id/reports")" = 400

# Nur der Autor kann seinen Entwurf bearbeiten; die Übergabe ist einmalig und Rückgaben benötigen einen Kommentar.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "${report_payload/Ursprünglich/Manipuliert}" \
  "$base_url/api/reports/$report_id")" = 403
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "${report_payload/Ursprünglich/Manipuliert}" \
  "$base_url/api/reports/$report_id")" = 200
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{}' \
  "$base_url/api/reports/$report_id/submit-to-unit" >/dev/null
test "$(incident_status "$force_token" "$incident_id")" = submitted
test "$(incident_status "$other_force_token" "$incident_id")" = report_exists
test "$(incident_status "$leader_token" "$incident_id")" = review_required
assert_pdf "$leader_token" "/api/reports/$report_id/pdf" 'Einzelbericht|Einheitsleitung Eins|Rolle: Einheitsführung|Manipuliert'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{}' \
  "$base_url/api/reports/$report_id/submit-to-unit")" = 409
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{}' \
  "$base_url/api/reports/$report_id/return-to-author")" = 400

# Die Rückgabe verlangt eine weiterhin bestehende Autorenzuordnung und bleibt in der Historie sichtbar.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE uu FROM user_units uu JOIN users u ON u.id=uu.user_id WHERE u.email='fuehrungskraft@example.test' AND uu.unit_id=1"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{"comment":"Bitte ergänzen"}' \
  "$base_url/api/reports/$report_id/return-to-author")" = 409
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO user_units(user_id,unit_id) SELECT id,1 FROM users WHERE email='fuehrungskraft@example.test'"
curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{"comment":"Bitte ergänzen"}' \
  "$base_url/api/reports/$report_id/return-to-author" >/dev/null
curl --insecure --silent --fail --cookie "$session_cookie=$leader_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($reports[0]["status"]==="author_draft"); assert($reports[0]["editable"]===false); assert(end($reports[0]["history"])["comment"]==="Bitte ergänzen");'
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request POST --data '{}' \
  "$base_url/api/reports/$report_id/submit-to-unit" >/dev/null
curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" --header 'Content-Type: application/json' --request POST --data '{}' \
  "$base_url/api/reports/$report_id/submit-to-command" >/dev/null

# In der Wehrführungsprüfung ist der Bericht für frühere Prüfstufen unveränderlich und nur noch lesbar.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "$report_payload" \
  "$base_url/api/reports/$report_id")" = 403
test "$(incident_status "$force_token" "$incident_id")" = submitted
test "$(incident_status "$leader_token" "$incident_id")" = submitted
test "$(incident_status "$session_token" "$incident_id")" = reports_pending
assert_pdf "$session_token" "/api/reports/$report_id/pdf" 'Einzelbericht|Admin|Rolle: Wehrführung|Manipuliert'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/consolidation/pdf")" = 403
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/incidents/$incident_id/consolidation/pdf")" = 409

# Die Wehrführung kann erst nach Berichten aller alarmierten Einheiten konsolidieren und den Gesamtbericht exportieren.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' \
  --data "${report_payload/\"unitId\":1/\"unitId\":$second_unit_id}" \
  "$base_url/api/incidents/$incident_id/reports" >/dev/null
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '$items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0]; assert($incident["reportStatus"]["key"]==="ready");'
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data '{"text":"Konsolidiert"}' "$base_url/api/incidents/$incident_id/consolidation" >/dev/null
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE incidents SET consolidated_at='2026-08-24 09:00:00' WHERE id=$incident_id"
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '$items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0]; assert($incident["reportStatus"]["key"]==="completed");'
assert_pdf "$session_token" "/api/incidents/$incident_id/consolidation/pdf" 'Abgeschlossener Gesamtbericht|Konsolidiert|Admin|Rolle: Wehrführung|Manipuliert|24.08.2026 11:00 Uhr'

# Eine Rückgabe durch die Wehrführung invalidiert die Konsolidierung bis zur erneuten Übergabe.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  --data '{"comment":"Bitte durch die Einheit prüfen"}' "$base_url/api/reports/$report_id/return-to-unit" >/dev/null
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '$items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0]; assert($incident["reportStatus"]["key"]==="reports_pending"); assert($incident["reportStatus"]["pendingUnits"]===["Löschzug"]);'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/incidents/$incident_id/consolidation/pdf")" = 409
test "$(incident_status "$leader_token" "$incident_id")" = review_required
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(status,'|',consolidated_at IS NULL,'|',(SELECT COUNT(*) FROM report_transitions WHERE report_id=$report_id_int)) FROM reports JOIN incidents ON incidents.id=reports.incident_id WHERE reports.id=$report_id_int")" = 'unit_review|1|6'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data '{"text":"Zu früh"}' "$base_url/api/incidents/$incident_id/consolidation")" = 409
curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" --header 'Content-Type: application/json' --request POST --data '{}' \
  "$base_url/api/reports/$report_id/submit-to-command" >/dev/null

# Frühere Prüfstufen behalten nach Rückgabe und erneuter Übergabe ihre Leserechte.
for previous_reviewer_token in "$force_token" "$leader_token"; do
  curl --insecure --silent --fail \
    --cookie "$session_cookie=$previous_reviewer_token" "$base_url/api/incidents/$incident_id/reports" |
    php -r '$reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(count($reports)===1); assert($reports[0]["status"]==="wehr_review"); assert($reports[0]["editable"]===false); assert(count($reports[0]["history"])===7);'
done

# Workflow-Benachrichtigungen erreichen dedupliziert die zuständigen Einheits- und Wehrführungen.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,$second_unit_id,'Einheitsleitung Zwei','leitung2@example.test',password_hash,'einheitsleitung' FROM users WHERE email='admin@example.test';
    SET @leader_two_id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@leader_two_id,$second_unit_id)"
if [[ -z "${TEST_BASE_URL:-}" ]]; then
  rm -f notification-messages.log
  php test/fake-smtp.php smtp-cert.pem smtp-key.pem 5 notification-messages.log >>smtp-server.log 2>&1 &
  smtp_pid=$!
  sleep 0.25
fi
notification_incident_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data "{\"title\":\"Benachrichtigungstest\",\"startedAt\":\"2026-08-22T18:00:00.000Z\",\"address\":\"Teststraße 1\",\"unitIds\":[1,$second_unit_id]}" \
  "$base_url/api/incidents")
notification_incident_id=$(printf '%s' "$notification_incident_response" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
notification_report_payload='{"unitId":1,"runningNumber":"70/2026","damagedParty":{},"damagingParty":{},"incidentCommand":{},"narrative":"Bericht der Führungskraft","departedAt":"2026-08-22T18:05:00.000Z","arrivedAt":"2026-08-22T18:10:00.000Z","endedAt":"2026-08-22T19:00:00.000Z","incidentType":"Technische Hilfe","classification":{"site":[],"cause":[],"technical":[]},"crew":[]}'
notification_report_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --data "$notification_report_payload" \
  "$base_url/api/incidents/$notification_incident_id/reports")
notification_report_id=$(printf '%s' "$notification_report_response" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
notification_submit_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{}' \
  "$base_url/api/reports/$notification_report_id/submit-to-unit")
notification_command_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{}' \
  "$base_url/api/reports/$notification_report_id/submit-to-command")
notification_return_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --request POST --data '{"comment":"Rückfrage"}' \
  "$base_url/api/reports/$notification_report_id/return-to-unit")
if [[ -z "${TEST_BASE_URL:-}" ]]; then
  printf '%s\n%s\n%s\n%s\n%s\n' "$notification_incident_response" "$notification_report_response" "$notification_submit_response" "$notification_command_response" "$notification_return_response" |
    php -r 'foreach(file("php://stdin",FILE_IGNORE_NEW_LINES) as $response) assert(!isset(json_decode($response,true,512,JSON_THROW_ON_ERROR)["warning"]));'
  wait "$smtp_pid"
  smtp_pid=''
  test "$(grep --count '^Recipient: leitung1@example.test' notification-messages.log)" = 3
  test "$(grep --count '^Recipient: leitung2@example.test' notification-messages.log)" = 1
  test "$(grep --count '^Recipient: admin@example.test' notification-messages.log)" = 1
  test "$(tr -d '\r' <notification-messages.log | grep --count '^Subject: Neuer Einsatz$')" = 2
  test "$(tr -d '\r' <notification-messages.log | grep --count '^Subject: Einsatzbericht eingereicht$')" = 1
  test "$(tr -d '\r' <notification-messages.log | grep --count '^Subject: Einsatzbericht geprüft$')" = 1
  test "$(tr -d '\r' <notification-messages.log | grep --count '^Subject: Einsatzbericht zurückgegeben$')" = 1
  grep --quiet 'Feuerwehr: Testwehr' notification-messages.log
  grep --quiet 'Einheit: Löschzug' notification-messages.log
  grep --quiet "Einsatznummer: $notification_incident_id" notification-messages.log
  grep --quiet 'Stichwort: Benachrichtigungstest' notification-messages.log
  grep --quiet 'Datum und Uhrzeit: 22.08.2026 20:00 Uhr (Europe/Berlin)' notification-messages.log
  grep --quiet 'Ausgelöst durch: Führungskraft Test' notification-messages.log
  grep --quiet 'Kommentar: Rückfrage' notification-messages.log
  test "$(grep --count "Link: $APP_URL/?incident=$notification_incident_id" notification-messages.log)" = 5

  # Einheitsführungen lösen beim Erstellen noch keine Benachrichtigung aus.
  quiet_incident_id=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
    einsatzberichte --execute="INSERT INTO incidents(organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text) VALUES(1,'Stiller Test','2026-08-22T18:00:00.000Z','','','','','',''); SET @incident_id=LAST_INSERT_ID(); INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(@incident_id,1,'[]'); SELECT @incident_id")
  quiet_report_response=$(curl --insecure --silent --fail \
    --cookie "$session_cookie=$leader_token" \
    --header 'Content-Type: application/json' \
    --data "${notification_report_payload/70\/2026/71\/2026}" \
    "$base_url/api/incidents/$quiet_incident_id/reports")
  quiet_report_id=$(printf '%s' "$quiet_report_response" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(!isset($data["warning"])); echo $data["id"];')
  test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
    einsatzberichte --execute="SELECT status FROM reports WHERE id=$quiet_report_id")" = unit_review

  # Ein Versandfehler wird sichtbar gemeldet, ohne den bereits gespeicherten Einsatz zurückzurollen.
  failed_notification_response=$(curl --insecure --silent --fail \
    --cookie "$session_cookie=$session_token" \
    --header 'Content-Type: application/json' \
    --data '{"title":"Gespeichert trotz Mailfehler","startedAt":"2026-08-22T18:00:00.000Z","address":"","unitIds":[1]}' \
    "$base_url/api/incidents")
  failed_notification_id=$(printf '%s' "$failed_notification_response" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(str_contains($data["warning"],"gespeichert")); echo $data["id"];')
  test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
    einsatzberichte --execute="SELECT COUNT(*) FROM incidents WHERE id=$failed_notification_id AND title='Gespeichert trotz Mailfehler'")" = 1
fi

# DIVERA-Discovery und Einzelimport stehen Führungskräften offen, Konfiguration und Stammdatensynchronisation nicht.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data '{"accessKey":"test"}' "$base_url/api/units/1/divera" >/dev/null
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/divera" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(count($data["alarms"])===2); assert(count($data["vehicles"])===2);'

# HTTP-Fehler der DIVERA-Quelle nennen den konkreten Statuscode, ohne den Access-Key offenzulegen.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data '{"accessKey":"http-error"}' "$base_url/api/units/1/divera" >/dev/null
curl --insecure --silent --cookie "$session_cookie=$force_token" "$base_url/api/units/1/divera?summary=1" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($data["error"]==="DIVERA-Abfrage fehlgeschlagen (HTTP 503)"); assert(!str_contains($data["error"],"http-error"));'
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data '{"accessKey":"test"}' "$base_url/api/units/1/divera" >/dev/null

# Die periodische DIVERA-Kurzabfrage lädt Alarme, aber keine Stammdaten.
: > "$divera_log"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/divera?summary=1" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(count($data["alarms"])===2); assert($data["vehicles"]===[]);'
test "$(grep --count '^GET /api/v2/alarms$' "$divera_log")" = 1
! grep --quiet '^GET /api/v2/pull/all$' "$divera_log"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data '{"accessKey":"verboten"}' "$base_url/api/units/1/divera")" = 403
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/members/sync")" = 403

# Eine unbekannte DIVERA-ID wird nicht als lokaler Einsatz importiert.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --data '{"id":"kein-solcher-alarm"}' "$base_url/api/units/1/divera/import")" = 404
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --data '{"id":"alarm-1"}' "$base_url/api/units/1/divera/import" >/dev/null

# Eine nachträglich importierte Einheitenzuordnung invalidiert einen bestehenden Gesamtbericht.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE incidents SET consolidated_at=UTC_TIMESTAMP() WHERE divera_id='alarm-1'"
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data '{"accessKey":"test"}' "$base_url/api/units/$second_unit_id/divera" >/dev/null
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' \
  --data '{"id":"alarm-1"}' "$base_url/api/units/$second_unit_id/divera/import" >/dev/null
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT consolidated_at IS NULL FROM incidents WHERE divera_id='alarm-1'")" = 1

# Der Gesamtabgleich lädt jede Quelle einmal, ersetzt Stammdaten und importiert alle Einsätze idempotent.
: > "$divera_log"
sync_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync")
printf '%s' "$sync_response" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($data["members"]===2); assert($data["qualifications"]===2); assert($data["vehicles"]===2); assert($data["incidentsCreated"]===1); assert($data["incidentsUpdated"]===1); assert($data["assignmentsCreated"]===1);'
test "$(grep --count '^GET /api/v2/pull/all$' "$divera_log")" = 1
test "$(grep --count '^GET /api/v2/alarms$' "$divera_log")" = 1
! grep --extended-regexp --quiet '^(POST|PUT|PATCH|DELETE) ' "$divera_log"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/resources" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $members=array_column($data["members"],null,"divera_id"); assert(count($members)===4); assert(count($data["vehicles"])===2); assert($members["m1"]["active"]===1 && $members["m1"]["qualifications"]==="AGT"); assert($members["m2"]["active"]===1 && $members["m2"]["qualifications"]==="MA"); assert($members["test-101"]["active"]===0 && $members["test-102"]["active"]===0);'

# Ein wiederholter Gesamtabgleich aktualisiert vorhandene Einsätze ohne Duplikate.
: > "$divera_log"
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($data["incidentsCreated"]===0); assert($data["incidentsUpdated"]===2); assert($data["assignmentsCreated"]===0);'
test "$(grep --count '^GET /api/v2/pull/all$' "$divera_log")" = 1
test "$(grep --count '^GET /api/v2/alarms$' "$divera_log")" = 1

# Fehlerhafte DIVERA-Antworten brechen den Abgleich ab, ohne bestehende Stammdaten zu verändern.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE units SET divera_access_key='malformed' WHERE id=1"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync")" = 502
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT((SELECT COUNT(*) FROM vehicles WHERE unit_id=1),'|',(SELECT COUNT(*) FROM member_units WHERE unit_id=1))")" = '2|4'

# Nicht mehr gelieferte Mitglieder werden inaktiv, bleiben in historischen Berichten und sind nicht neu auswählbar.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT IGNORE INTO report_crew(report_id,member_id) SELECT $report_id_int,id FROM members WHERE organization_id=1 AND divera_id='m2';
    UPDATE units SET divera_access_key='reduced' WHERE id=1"
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync" >/dev/null
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT((SELECT COUNT(*) FROM vehicles WHERE unit_id=1),'|',(SELECT COUNT(*) FROM qualifications WHERE unit_id=1),'|',(SELECT COUNT(*) FROM member_units WHERE unit_id=1),'|',(SELECT SUM(active) FROM member_units WHERE unit_id=1),'|',(SELECT COUNT(*) FROM members WHERE organization_id=1 AND divera_id='m2'))")" = '1|1|4|1|1'
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/resources" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $members=array_column($data["members"],null,"divera_id"); assert(count($members)===4); assert($members["m1"]["active"]===1); assert($members["m2"]["active"]===0);'
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/members" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(count($data)===1); assert($data[0]["active"]===1);'
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(in_array("Bernd Beispiel",array_column(json_decode($data[0]["crew"],true,512,JSON_THROW_ON_ERROR),"name"),true));'

inactive_member_id=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT m.id FROM members m JOIN member_units mu ON mu.member_id=m.id WHERE mu.unit_id=1 AND mu.active=0 AND m.divera_id='m2'")

# Ein bereits zugeordnetes inaktives Mitglied kann auch im selben Bericht nicht manipuliert umgeordnet werden.
inactive_reassignment="${report_without_travel_times/\"crew\":[]/\"crew\":[{\"memberId\":$inactive_member_id,\"vehicle\":\"HLF 20\",\"role\":\"besatzung\"}]}"
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE reports SET status='unit_review' WHERE id=$report_id_int"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$leader_token" --header 'Content-Type: application/json' --request PUT \
  --data "$inactive_reassignment" "$base_url/api/reports/$report_id")" = 400
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE reports SET status='wehr_review' WHERE id=$report_id_int"

# Ein inaktives Mitglied kann nicht manipuliert einem weiteren Bericht hinzugefügt werden.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --data "{\"unitId\":1,\"runningNumber\":\"99/2026\",\"damagedParty\":{},\"damagingParty\":{},\"incidentCommand\":{},\"narrative\":\"Test\",\"departedAt\":null,\"arrivedAt\":null,\"endedAt\":\"2026-08-22T20:00:00.000Z\",\"incidentType\":\"Technische Hilfe\",\"classification\":{\"site\":[],\"cause\":[],\"technical\":[]},\"crew\":[{\"memberId\":$inactive_member_id,\"vehicle\":\"\",\"role\":\"besatzung\"}]}" \
  "$base_url/api/incidents/$duplicate_incident_id/reports")" = 400
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync")" = 403

# Passwort-Wiederherstellung verrät keine Konten und begrenzt neue Token pro Nutzer.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"email":"nicht-registriert@example.test"}' \
  "$base_url/api/password-reset/request")" = 202
rate_limit_hash=$(php -r "echo hash('sha256', 'rate-limit');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM password_resets WHERE user_id=(SELECT id FROM users WHERE email='admin@example.test');
    INSERT INTO password_resets(user_id,token_hash,expires_at) SELECT id,'$rate_limit_hash',UTC_TIMESTAMP()+INTERVAL 30 MINUTE FROM users WHERE email='admin@example.test'"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"email":"admin@example.test"}' \
  "$base_url/api/password-reset/request")" = 202
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT COUNT(*) FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE u.email='admin@example.test'")" = 1
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM password_resets WHERE user_id=(SELECT id FROM users WHERE email='admin@example.test')"

# Abgelaufene und unbekannte Reset-Tokens werden abgelehnt; ein gültiges Token ist einmalig und beendet bestehende Sitzungen.
reset_token='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
reset_hash=$(php -r "echo hash('sha256', '$reset_token');")
expired_token='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
expired_hash=$(php -r "echo hash('sha256', '$expired_token');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO password_resets(user_id,token_hash,expires_at) SELECT id,'$expired_hash',UTC_TIMESTAMP()-INTERVAL 1 MINUTE FROM users WHERE email='admin@example.test'"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data "{\"token\":\"$expired_token\"}" \
  "$base_url/api/password-reset/context")" = 400
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM password_resets WHERE token_hash='$expired_hash'"
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO password_resets(user_id,token_hash,expires_at) SELECT id,'$reset_hash',UTC_TIMESTAMP()+INTERVAL 30 MINUTE FROM users WHERE email='admin@example.test'"
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data "{\"token\":\"$reset_token\"}" \
  "$base_url/api/password-reset/context" | grep --quiet '"email":"admin@example.test"'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"token":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
  "$base_url/api/password-reset/context")" = 400
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data "{\"token\":\"$reset_token\",\"password\":\"neues-geheimes-passwort\"}" \
  "$base_url/api/password-reset/confirm" | grep --quiet '"ok":true'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data "{\"token\":\"$reset_token\",\"password\":\"weiteres-geheimes-passwort\"}" \
  "$base_url/api/password-reset/confirm")" = 400
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" "$base_url/api/me")" = 401
curl --insecure --silent --fail \
  --header 'Content-Type: application/json' \
  --data '{"email":"admin@example.test","password":"neues-geheimes-passwort"}' \
  "$base_url/api/login" | grep --quiet '"ok":true'

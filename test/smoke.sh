#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Smoke-Test fehlgeschlagen in Zeile $LINENO" >&2' ERR

export DB_DSN="${DB_DSN:-mysql:host=${TEST_DB_HOST:-127.0.0.1};port=3306;dbname=einsatzberichte;charset=utf8mb4}"
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
# Bearbeitungen verlangen genau einen sichtbaren Bericht und bewahren beim Ergänzen der geladenen Revision JSON-Objekte und -Listen.
report_data() {
  local payload=$1 token=${2:-$force_token} incident=${3:-$incident_id} report=${4:-$report_id}
  curl --insecure --silent --fail --cookie "$session_cookie=$token" "$base_url/api/incidents/$incident/reports" |
    REPORT_ID="$report" PAYLOAD="$payload" php -r '
      $reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
      $matches=array_values(array_filter($reports,fn($row)=>$row["id"]===(int)getenv("REPORT_ID")));
      if(count($matches)!==1) throw new RuntimeException("Genau ein sichtbarer Testbericht ist erforderlich");
      $report=$matches[0];
      assert(is_int($report["revision"]) && $report["revision"]>0);
      $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
      $data->revision=$report["revision"];
      echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
    '
}
# Die Konsolidierung verlangt genau einen sichtbaren Einsatz und bindet seinen Gesamtstand sowie sämtliche geladenen Quellberichte.
consolidation_data() {
  local text=$1 incident=${2:-$incident_id} snapshot reports
  snapshot=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents")
  reports=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents/$incident/reports")
  SNAPSHOT="$snapshot" REPORTS="$reports" INCIDENT_ID="$incident" TEXT="$text" php -r '
    $items=json_decode(getenv("SNAPSHOT"),true,512,JSON_THROW_ON_ERROR);
    $matches=array_values(array_filter($items,fn($row)=>$row["id"]===(int)getenv("INCIDENT_ID")));
    if(count($matches)!==1) throw new RuntimeException("Genau ein sichtbarer Testeinsatz ist erforderlich");
    $incident=$matches[0];
    assert(is_int($incident["revision"]) && $incident["revision"]>0);
    $reports=json_decode(getenv("REPORTS"),true,512,JSON_THROW_ON_ERROR);
    echo json_encode(["text"=>getenv("TEXT"),"revision"=>$incident["revision"],
      "reportVersions"=>array_map(fn($row)=>["id"=>$row["id"],"revision"=>$row["revision"]],$reports)],JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
  '
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
# Nur die Wehrführung erhält den Gesamttext; frühere Rollen behalten lediglich zulässige Einsatz- und Statusdaten.
assert_consolidated_visibility() {
  local incident_id=$1
  for restricted_token in "$force_token" "$leader_token"; do
    curl --insecure --silent --fail --cookie "$session_cookie=$restricted_token" "$base_url/api/incidents" |
      INCIDENT_ID="$incident_id" php -r '
        $raw=stream_get_contents(STDIN);
        $items=json_decode($raw,true,512,JSON_THROW_ON_ERROR);
        foreach($items as $item) assert(!array_key_exists("consolidated_text",$item));
        assert(!str_contains($raw,"Nicht freigegebene Angaben der anderen Einheit"));
        $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0];
        assert(array_key_exists("consolidated_at",$incident));
        assert(isset($incident["reportStatus"]));
      '
  done
  curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
    INCIDENT_ID="$incident_id" php -r '
      $items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
      $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0];
      assert($incident["consolidated_text"]==="Konsolidiert: Nicht freigegebene Angaben der anderen Einheit");
    '
}
if mysql --help 2>&1 | grep -- '--ssl-mode' >/dev/null; then
  mysql_tls_args=(--ssl-mode=DISABLED)
elif mysql --help 2>&1 | grep -- '--skip-ssl' >/dev/null; then
  mysql_tls_args=(--skip-ssl)
fi

# Revisionshelfer brechen bei fehlenden oder doppelten Treffern ab; genau ein Treffer liefert die erwarteten Vorbedingungen.
(
  session_token='test-helper'
  curl() { printf '%s' "$fixture"; }
  for fixture in '[]' '[{"id":7,"revision":3},{"id":7,"revision":4}]'; do
    if report_data '{}' test-helper 7 7 >/dev/null 2>&1; then
      echo "Berichtshelfer akzeptiert fehlende oder doppelte Treffer" >&2
      exit 1
    fi
    if consolidation_data 'Test' 7 >/dev/null 2>&1; then
      echo "Konsolidierungshelfer akzeptiert fehlende oder doppelte Treffer" >&2
      exit 1
    fi
  done
  fixture='[{"id":7,"revision":3}]'
  test "$(report_data '{}' test-helper 7 7)" = '{"revision":3}'
  test "$(consolidation_data 'Test' 7)" = '{"text":"Test","revision":3,"reportVersions":[{"id":7,"revision":3}]}'
)

# Fehlende Datenbankkonfiguration wird bei Root-, Unterverzeichnis- und authentifizierten Anfragen gemeldet.
DB_DSN='' REQUEST_METHOD=GET REQUEST_URI=/api/bootstrap php api.php | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'
DB_DSN='' php -r '$_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REQUEST_URI"]="/ebmanager/api/bootstrap"; $_SERVER["SCRIPT_NAME"]="/ebmanager/api.php"; require "api.php";' | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'
DB_DSN='' php -r '$_COOKIE["session"]=str_repeat("a",64); $_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REQUEST_URI"]="/api/me"; require "api.php";' | grep --quiet '"error":"Datenbankzugang ist nicht konfiguriert'

# Die testweise überschreibbare DIVERA-Basisadresse enthält ausschließlich Schema, Host und optionalen Port.
DIVERA_API_BASE_URL='http://divera:8090/' php -r 'require "support.php"; if (diveraBaseUrl()!=="http://divera:8090") exit(1);'
for invalid_divera_url in 'https://host?x=1' 'https://user@host' 'https://host/path' 'https://host#fragment'; do
  DIVERA_API_BASE_URL="$invalid_divera_url" php -r 'require "support.php"; try { diveraBaseUrl(); exit(1); } catch (ApiError $error) { if ($error->status!==503) exit(1); }'
done

# Primitive Validatoren sortieren IDs verlustfrei, raten keine IDs/Koordinaten und erhalten Passwort-Leerzeichen sowie optionale Textskalare.
php -r '
  require "support.php";
  $maximum=min(PHP_INT_MAX,MAX_API_INTEGER);
  assert(positiveId((string)$maximum)===$maximum);
  assert(positiveId("12")===12);
  assert(idList([$maximum,$maximum-1],"IDs")===[$maximum-1,$maximum]);
  if(PHP_INT_SIZE>=8) assert(positiveId("4294967296")===4294967296);
  foreach(["9007199254740992","9007199254740993","9223372036854775807"] as $value) {
    try { positiveId($value); throw new RuntimeException("Unsichere Browser-ID akzeptiert"); }
    catch(ApiError $error) { assert($error->status===400); }
  }
  assertResponseIntegers(["id"=>$maximum,"objects"=>[(object)["id"=>1]]]);
  if(PHP_INT_SIZE>=8) {
    try { assertResponseIntegers(["objects"=>[(object)["id"=>9007199254740992]]]); throw new LogicException("Unsichere Antwort-ID akzeptiert"); }
    catch(RuntimeException $error) { assert($error->getMessage()==="Ganzzahl außerhalb des sicheren JSON-Bereichs"); }
  }
  assert(passwordInput("  zehn Zeichen  ")==="  zehn Zeichen  ");
  assert(optional(null,"Text")==="" && optional(0,"Text")==="0" && optional(false,"Text")==="");
  assert(finiteNumber(null,"Koordinate")===null && finiteNumber("50.9","Koordinate")===50.9);
  foreach([[],new stdClass(),true,false,"50x"] as $value) {
    try { finiteNumber($value,"Koordinate"); throw new RuntimeException("Koordinatentyp akzeptiert"); }
    catch(ApiError $error) { assert($error->status===400); }
  }
  foreach([[],new stdClass(),true,123,"null\0byte"] as $value) {
    try { passwordInput($value); throw new RuntimeException("Passworttyp akzeptiert"); }
    catch(ApiError $error) { assert($error->status===400); }
  }
'

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

# Das Frontend enthält die erwarteten barrierefreien Verwaltungs-, DIVERA-, Fahrzeug- und Besatzungselemente ohne duplizierte Fachoptionen.
php -r '
  $html=file_get_contents("public/index.html");
  $javascript=file_get_contents("public/app.js");
  $frontend=$html.$javascript;
  $css=file_get_contents("public/styles.css");
  foreach (["viewport-fit=cover","public/styles.css","public/app.js","class=\"skip-link\"","aria-label=\"Hauptnavigation\"","aria-live=\"polite\"","Auf Touch-Geräten","checkPendingDivera","divera?summary=1","Neue DIVERA-Einsätze","Letzter Import:","rankOptions","pendingWarning","initialView","DIVERA-Einsatznummer","Weitere Fahrzeuge der eigenen Einheit","selectedAdditionalVehicles","class=\"command-row\"","class=\"form-section\"","class=\"report-times\"","restoreDialogFocus","Zugang zurücksetzen und neu einladen","resetUser","zone.key===current","zone.historical","zone.dataset.historical","<select name=\"commandRank\">","<select name=\"additionalCommandRank\">"] as $required) {
    if (!str_contains($frontend,$required)) { fwrite(STDERR,"Frontend-Marker fehlt: $required\n"); exit(1); }
  }
  foreach (["--control-height: 44px",":focus-visible","safe-area-inset-bottom","forced-colors: active"] as $required) {
    if (!str_contains($css,$required)) { fwrite(STDERR,"CSS-Marker fehlt: $required\n"); exit(1); }
  }
  if (str_contains($html,"<style") || preg_match("/<script(?![^>]*\\s+src\\s*=)[^>]*>/i",$html) || preg_match("/\\son[a-z]+=/i",$frontend) || preg_match("/\\sstyle=\"/i",$frontend)) {
    fwrite(STDERR,"Verbotenes Inline-Markup gefunden\n"); exit(1);
  }
  foreach (["Kleinbrand","Wohngebäude","Menschen in Notlage","Feuerwehrmann-Anwärter"] as $duplicatedOption) {
    if (str_contains($frontend,$duplicatedOption)) { fwrite(STDERR,"Fachoption im Frontend dupliziert: $duplicatedOption\n"); exit(1); }
  }
  if (preg_match("/<select[^>]+multiple/i",$frontend)) { fwrite(STDERR,"Mehrfach-Select im Frontend gefunden\n"); exit(1); }
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

# Text-, Wurzel-, ID- und Listenfehler liefern HTTP 400; abgewiesene Anfragen ändern weder Benutzer noch Einheiten oder Einsätze.
API_BASE_URL="$base_url" COOKIE="$session_cookie=$session_token" php -r '
  $call=function(string $path, string $method="GET", ?string $payload=null): array {
    $args=["curl","--insecure","--silent","--show-error","--cookie",getenv("COOKIE"),"--write-out","\n%{http_code}",
      "--header","Content-Type: application/json","--request",$method,getenv("API_BASE_URL").$path];
    if($payload!==null) array_push($args,"--data",$payload);
    $process=proc_open($args,[0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
    fclose($pipes[0]); $body=stream_get_contents($pipes[1]); $error=stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    if(proc_close($process)!==0) throw new RuntimeException("API-Testtransport fehlgeschlagen");
    return [(int)substr($body,-3),substr($body,0,-4)];
  };
  $before=[$call("/api/users"),$call("/api/units"),$call("/api/incidents")];
  foreach(["[]","null","false","0","\"Text\""] as $root) {
    if($call("/api/units","POST",$root)[0]!==400) throw new RuntimeException("JSON-Wurzel akzeptiert");
  }
  foreach(["[]","{}"] as $wrong) {
    foreach(["name","email","password"] as $field) {
      $payload=json_decode("{\"name\":\"Neu\",\"email\":\"neu@example.test\",\"password\":\"geheim-12345\",\"role\":\"wehrleitung\"}");
      $payload->$field=json_decode($wrong);
      // Das Startpasswort wird bei Einladungen nicht verwendet; geprüft wird die Passwortänderung.
      $path=$field==="password" ? "/api/users/1" : "/api/users";
      if($call($path,$field==="password" ? "PUT" : "POST",json_encode($payload))[0]!==400) throw new RuntimeException("Ungültiger Benutzertyp akzeptiert");
    }
    if($call("/api/incidents","POST","{\"unitIds\":[1],\"title\":\"Test\",\"startedAt\":\"2026-08-22T18:00:00.000Z\",\"address\":$wrong}")[0]!==400) throw new RuntimeException("Adressobjekt akzeptiert");
    if($call("/api/units","POST","{\"name\":$wrong}")[0]!==400) throw new RuntimeException("Namenstyp akzeptiert");
  }
  foreach(["true","false","1.0","1.5","\"1x\"","\"1e0\"","\"01\"","\" 1\"","\"+1\"","0","-1","9007199254740992","\"9007199254740993\"","9223372036854775808","\"18446744073709551616\"","[]","{}"] as $id) {
    if($call("/api/incidents","POST","{\"unitIds\":[$id],\"title\":\"Test\",\"startedAt\":\"2026-08-22T18:00:00.000Z\"}")[0]!==400) throw new RuntimeException("Ungültige Einsatz-ID akzeptiert");
    if($call("/api/users","POST","{\"name\":\"Test\",\"email\":\"test@example.test\",\"role\":\"wehrleitung\",\"unitIds\":[$id]}")[0]!==400) throw new RuntimeException("Ungültige Mitgliedschaft ignoriert");
  }
  foreach(["{}","\"[1]\"","true"] as $list) {
    if($call("/api/users","POST","{\"name\":\"Test\",\"email\":\"test@example.test\",\"role\":\"wehrleitung\",\"unitIds\":$list}")[0]!==400) throw new RuntimeException("Einheitsliste akzeptiert");
  }
  foreach(["0","01","1.0","1x","1e0","true","9007199254740992","9223372036854775808"] as $id) {
    if($call("/api/units/$id/resources")[0]!==400) throw new RuntimeException("Pfad-ID akzeptiert");
  }
  if([$call("/api/users"),$call("/api/units"),$call("/api/incidents")]!==$before) throw new RuntimeException("Teilmutation bei ungültiger Anfrage");
  $users=json_decode($before[0][1]);
  if($users[0]->unit_ids!==[] || !is_array($users[0]->loginHistory)) throw new RuntimeException("Benutzerlisten sind keine nativen Listen");
  // Eine explizit leere optionale Zuordnung der Wehrführung bleibt zulässig und ändert keine Kontodaten.
  $unchanged=["name"=>$users[0]->name,"email"=>$users[0]->email,"role"=>$users[0]->role,"unitIds"=>null];
  if($call("/api/users/".$users[0]->id,"PUT",json_encode($unchanged,JSON_THROW_ON_ERROR))[0]!==200
    || $call("/api/users")!==$before[0]) throw new RuntimeException("Optionale leere Benutzerzuordnung abgewiesen oder verändert");
'

# Bekannte Eindeutigkeitsverletzungen erhalten fachliche 409-Meldungen; ein unbekannter echter Unique-Key bleibt ein neutraler HTTP 500.
test "$(curl --insecure --silent --write-out '|%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --data '{"name":"Löschzug"}' "$base_url/api/units")" = '{"error":"Eine Einheit mit diesem Namen existiert bereits in dieser Organisation"}|409'
test "$(curl --insecure --silent --write-out '|%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --data '{"name":"Doppelt","email":"admin@example.test","role":"wehrleitung","unitIds":[]}' \
  "$base_url/api/users")" = '{"error":"Diese E-Mail-Adresse wird bereits verwendet"}|409'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="ALTER TABLE units RENAME INDEX units_org_name TO api92_unexpected_unique"
unexpected_duplicate=$(curl --insecure --silent --write-out '|%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --data '{"name":"Löschzug"}' "$base_url/api/units")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="ALTER TABLE units RENAME INDEX api92_unexpected_unique TO units_org_name"
test "$unexpected_duplicate" = '{"error":"Interner Fehler"}|500'

# BIGINT-IDs bis zur gemeinsamen Browsergrenze bleiben exakt; größere native Antwort-Integer liefern 500 statt gerundeter IDs.
API_BASE_URL="$base_url" COOKIE="$session_cookie=$session_token" php -r '
  require "support.php";
  $call=function(string $path): array {
    $process=proc_open(["curl","--insecure","--silent","--show-error","--cookie",getenv("COOKIE"),"--write-out","\n%{http_code}",
      getenv("API_BASE_URL").$path],[0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
    fclose($pipes[0]); $body=stream_get_contents($pipes[1]); stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    if(proc_close($process)!==0) throw new RuntimeException("ID-Grenztest nicht erreichbar");
    return [(int)substr($body,-3),substr($body,0,-4)];
  };
  $before=$call("/api/units");
  $next=(int)one("SELECT AUTO_INCREMENT FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=?",["units"])["AUTO_INCREMENT"];
  try {
    query("INSERT INTO units(id,organization_id,name) VALUES(9007199254740991,1,?)",["API sichere BIGINT-ID"]);
    $safe=$call("/api/units");
    $rows=json_decode($safe[1],false,512,JSON_THROW_ON_ERROR);
    if($safe[0]!==200 || count(array_filter($rows,fn($row)=>$row->id===9007199254740991))!==1
      || $call("/api/units/9007199254740991/resources")!==[200,"{\"members\":[],\"vehicles\":[]}"]) {
      throw new RuntimeException("Sichere BIGINT-ID verändert");
    }
    query("INSERT INTO units(id,organization_id,name) VALUES(9007199254740992,1,?)",["API unsichere BIGINT-ID"]);
    if($call("/api/units")!==[500,"{\"error\":\"Interner Fehler\"}"]) throw new RuntimeException("Unsichere native Antwort-ID ausgegeben");
  } finally {
    query("DELETE FROM units WHERE id IN (9007199254740991,9007199254740992) AND organization_id=1");
    query("ALTER TABLE units AUTO_INCREMENT=$next");
  }
  if($call("/api/units")!==$before) throw new RuntimeException("ID-Grenztest hat fachliche Daten verändert");
'

# Die Systemübersicht enthält Status- und Build-Daten, aber keine Zugangsdaten oder Tokens.
system_json=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/system")
printf '%s' "$system_json" | EXPECTED_BUILD_ID="${EXPECTED_BUILD_ID:-Entwicklung}" php -r '
  $data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
  if (($data["database"]["status"]??"")!=="Bereit" || ($data["application"]["buildId"]??"")!==getenv("EXPECTED_BUILD_ID") || count($data["units"]??[])!==1 || count($data["users"]??[])!==1) exit(1);
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

# Eine fehlende Spalte aus Migration 002 liefert am Bootstrap-Endpunkt HTTP 503.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="ALTER TABLE member_units DROP COLUMN active"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' "$base_url/api/bootstrap")" = 503
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="ALTER TABLE member_units ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE AFTER unit_id"

# Fehlende Einsatz- oder Berichtsrevisionen werden schon beim Bootstrap als unvollständige Migration gemeldet.
for revision_table in incidents reports; do
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="ALTER TABLE $revision_table DROP COLUMN revision"
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' "$base_url/api/bootstrap")" = 503
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="ALTER TABLE $revision_table ADD COLUMN revision INT UNSIGNED NOT NULL DEFAULT 1"
done

# Migration 005 ist erst mit allen drei vorhandenen NOT-NULL-Spalten vollständig; Teil-DDL liefert HTTP 503.
for snapshot_column in 'reports author_name VARCHAR(200)' 'report_crew member_name VARCHAR(200)' 'incidents report_data_frozen TINYINT(1)'; do
  read -r snapshot_table snapshot_name snapshot_type <<< "$snapshot_column"
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="ALTER TABLE $snapshot_table DROP COLUMN $snapshot_name"
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' "$base_url/api/bootstrap")" = 503
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="ALTER TABLE $snapshot_table ADD COLUMN $snapshot_name $snapshot_type NULL"
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' "$base_url/api/bootstrap")" = 503
  snapshot_default=''
  [[ "$snapshot_name" == report_data_frozen ]] && snapshot_default='DEFAULT 0'
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="ALTER TABLE $snapshot_table MODIFY COLUMN $snapshot_name $snapshot_type NOT NULL $snapshot_default"
done
# Das vollständig wiederhergestellte Schema aus Migration 005 ist betriebsbereit.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' "$base_url/api/bootstrap")" = 200

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

# Einladungen speichern Anforderung und Ablauf in UTC, gelten sieben Tage und erlauben mehrere Einheitszuordnungen.
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
      einsatzberichte --execute="SELECT ABS(TIMESTAMPDIFF(SECOND,expires_at,UTC_TIMESTAMP()+INTERVAL 7 DAY))<=2 AND TIMESTAMPDIFF(SECOND,requested_at,expires_at)=604800 FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE u.email='invite@example.test'")" = 1
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

# Die Wehrleitung kann den eigenen Zugang nicht über die Benutzerverwaltung zurücksetzen.
admin_user_id=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT id FROM users WHERE email='admin@example.test'")
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/users/$admin_user_id/invitation")" = 409

# Profiländerungen erhalten Einmallinks; Passwort- und E-Mail-Änderungen widerrufen sie, Passwortänderungen zusätzlich die Sitzungen.
credential_user_id=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
  --execute="INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,1,'Zugangsprüfung','credential@example.test',password_hash,'fuehrungskraft' FROM users WHERE id=$admin_user_id; SET @id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@id,1); SELECT @id")
credential_token=$(php -r 'echo bin2hex(random_bytes(32));')
credential_hash=$(php -r "echo hash('sha256','$credential_token');")
credential_session_hash=$(php -r "echo hash('sha256','credential-session');")
for change in profile password email both; do
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="UPDATE users SET email='credential@example.test' WHERE id=$credential_user_id;
      DELETE FROM password_resets WHERE user_id=$credential_user_id;
      DELETE FROM sessions WHERE user_id=$credential_user_id;
      INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES($credential_user_id,'$credential_hash',UTC_TIMESTAMP()+INTERVAL 7 DAY);
      INSERT INTO sessions(token,user_id,expires_at) VALUES('$credential_session_hash',$credential_user_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR)"
  credential_email='credential@example.test'
  credential_password=''
  expected_sessions=1
  case "$change" in
    password) credential_password='ersetztes-geheimes-passwort'; expected_sessions=0 ;;
    email) credential_email='credential-new@example.test' ;;
    both) credential_email='credential-new@example.test'; credential_password='erneuertes-geheimes-passwort'; expected_sessions=0 ;;
  esac
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
    --data "{\"name\":\"Geändertes Profil\",\"email\":\"$credential_email\",\"password\":\"$credential_password\",\"role\":\"fuehrungskraft\",\"unitIds\":[1]}" \
    "$base_url/api/users/$credential_user_id")" = 200
  test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT COUNT(*) FROM sessions WHERE user_id=$credential_user_id")" = "$expected_sessions"
  if [[ "$change" == profile ]]; then
    test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
      --header 'Content-Type: application/json' --data "{\"token\":\"$credential_token\"}" \
      "$base_url/api/password-reset/context")" = 200
  else
    for endpoint in context confirm; do
      test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
        --header 'Content-Type: application/json' --data "{\"token\":\"$credential_token\",\"password\":\"nicht-erlaubtes-passwort\"}" \
        "$base_url/api/password-reset/$endpoint")" = 400
    done
  fi
done

# Parallele Tokenzugriffe warten auf die eigene users-Primärschlüsselsperre und verwenden nach Kontoänderungen keine veralteten Links oder Adressen.
CREDENTIAL_USER_ID="$credential_user_id" CREDENTIAL_TOKEN="$credential_token" API_BASE_URL="$base_url" php -r '
  require "support.php";
  $id=(int)getenv("CREDENTIAL_USER_ID");
  $token=getenv("CREDENTIAL_TOKEN");
  foreach(["request","confirm"] as $action) {
    query("UPDATE users SET email=? WHERE id=?",["credential@example.test",$id]);
    query("DELETE FROM password_resets WHERE user_id=?",[$id]);
    if($action==="confirm") query("INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 30 MINUTE)",[$id,hash("sha256",$token)]);
    db()->beginTransaction();
    query("SELECT id FROM users WHERE id=? FOR UPDATE",[$id]);
    $payload=$action==="request" ? ["email"=>"credential@example.test"] : ["token"=>$token,"password"=>"nicht-erlaubtes-passwort"];
    $process=proc_open(["curl","--insecure","--silent","--show-error","--max-time","15","--output","/dev/null","--write-out","%{http_code}","--header","Content-Type: application/json","--data",json_encode($payload),getenv("API_BASE_URL")."/api/password-reset/$action"],[0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
    if(!is_resource($process)) throw new RuntimeException("Parallele Anfrage konnte nicht gestartet werden");
    fclose($pipes[0]);
    try {
      $waiting=null;
      $deadline=microtime(true)+5;
      while(microtime(true)<$deadline) {
        $waiting=one("SELECT l.OBJECT_NAME AS table_name,l.INDEX_NAME AS index_name
          FROM performance_schema.data_lock_waits w
          JOIN performance_schema.data_locks l ON l.ENGINE=w.ENGINE AND l.ENGINE_LOCK_ID=w.REQUESTING_ENGINE_LOCK_ID
          JOIN performance_schema.threads t ON t.THREAD_ID=w.BLOCKING_THREAD_ID
          WHERE t.PROCESSLIST_ID=CONNECTION_ID() AND l.OBJECT_SCHEMA=DATABASE()");
        if($waiting) break;
        usleep(250000);
      }
      if(!$waiting || $waiting["table_name"]!=="users" || $waiting["index_name"]!=="PRIMARY") throw new RuntimeException("Tokenzugriff wartet nicht auf den primären Benutzerdatensatz");
      query("UPDATE users SET email=? WHERE id=?",["credential-new@example.test",$id]);
      query("DELETE FROM password_resets WHERE user_id=?",[$id]);
      db()->commit();
      $status=stream_get_contents($pipes[1]);
      $expected=$action==="request" ? "202" : "400";
      if($status!==$expected) throw new RuntimeException("Unerwartete parallele Tokenantwort: $status");
      if((int)query("SELECT COUNT(*) FROM password_resets WHERE user_id=?",[$id])->fetchColumn()!==0) throw new RuntimeException("Veralteter Token wurde erhalten");
    } finally {
      if(db()->inTransaction()) db()->rollBack();
      fclose($pipes[1]);
      fclose($pipes[2]);
      proc_close($process);
    }
  }
'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM users WHERE id=$credential_user_id"

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

  # Neueinladungen speichern UTC-Zeitpunkte und ersetzen den Zugang erst bei Mailannahme; ein Mailfehler lässt den alten Zugang unverändert.
  reinvite_session_token='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
  reinvite_session_hash=$(php -r "echo hash('sha256', '$reinvite_session_token');")
  reinvite_user_id=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) SELECT organization_id,1,'Neu einzuladen','reinvite@example.test',password_hash,'fuehrungskraft' FROM users WHERE email='admin@example.test'; SET @user_id=LAST_INSERT_ID(); INSERT INTO user_units(user_id,unit_id) VALUES(@user_id,1); INSERT INTO sessions(token,user_id,expires_at) VALUES('$reinvite_session_hash',@user_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR); SELECT @user_id")
  old_reinvite_hash=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT password_hash FROM users WHERE id=$reinvite_user_id")
  rm -f reinvite-messages.log
  php test/fake-smtp.php smtp-cert.pem smtp-key.pem 1 reinvite-messages.log >>smtp-server.log 2>&1 &
  smtp_pid=$!
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
    "$base_url/api/users/$reinvite_user_id/invitation")" = 200
  wait "$smtp_pid"
  smtp_pid=''
  new_reinvite_hash=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT password_hash FROM users WHERE id=$reinvite_user_id")
  test "$new_reinvite_hash" != "$old_reinvite_hash"
  test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT CONCAT((SELECT COUNT(*) FROM sessions WHERE user_id=$reinvite_user_id),'|',(SELECT COUNT(*) FROM password_resets WHERE user_id=$reinvite_user_id),'|',(SELECT ABS(TIMESTAMPDIFF(SECOND,expires_at,UTC_TIMESTAMP()+INTERVAL 7 DAY))<=2 AND TIMESTAMPDIFF(SECOND,requested_at,expires_at)=604800 FROM password_resets WHERE user_id=$reinvite_user_id))")" = '0|1|1'
  grep --quiet 'Recipient: reinvite@example.test' reinvite-messages.log
  grep --quiet 'Subject: Konto aktivieren' reinvite-messages.log
  reinvite_token_hash=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT token_hash FROM password_resets WHERE user_id=$reinvite_user_id")
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="INSERT INTO sessions(token,user_id,expires_at) VALUES('$reinvite_session_hash',$reinvite_user_id,UTC_TIMESTAMP()+INTERVAL 1 HOUR)"
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
    "$base_url/api/users/$reinvite_user_id/invitation")" = 503
  test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT password_hash='$new_reinvite_hash' AND EXISTS(SELECT 1 FROM sessions WHERE user_id=$reinvite_user_id) AND (SELECT token_hash FROM password_resets WHERE user_id=$reinvite_user_id)='$reinvite_token_hash' FROM users WHERE id=$reinvite_user_id")" = 1
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="DELETE FROM users WHERE id=$reinvite_user_id"
fi
rm -f invite.json reinvite-messages.log

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
  SECOND_UNIT_ID="$second_unit_id" php -r '$incidents=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $assignments=$incidents[0]["assignments"]; $expected=[1,(int)getenv("SECOND_UNIT_ID")]; sort($expected); assert(array_column($assignments,"unitId")===$expected); assert(is_array($assignments[0]["vehicles"])); assert($incidents[0]["reportStatus"]["key"]==="reports_pending"); assert(count($incidents[0]["reportStatus"]["pendingUnits"])===2);'

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

# Die Einheitsstatistik wahrt Rollen und Mandanten und ordnet lokale Zeitgrenzen sowie tatsächliche Beteiligung korrekt zu.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="SET @leader_id=(SELECT id FROM users WHERE email='leitung1@example.test');
    INSERT INTO incidents(organization_id,title,started_at,message,remark,patient,caller,consolidated_text) VALUES
      (1,'Statistik außerhalb Sommerzeitraum','2026-09-03T21:59:59.000Z','','','','',''),
      (1,'Statistik Sommer Mitternacht','2026-09-03T22:00:00.000Z','','','','',''),
      (1,'Statistik Freitag Tag','2026-09-04T14:59:00.000Z','','','','',''),
      (1,'Statistik Freitag Nacht','2026-09-04T15:00:00.000Z','','','','',''),
      (1,'Statistik Montag Nacht','2026-09-07T04:59:00.000Z','','','','',''),
      (1,'Statistik Montag Tag','2026-09-07T05:00:00.000Z','','','','',''),
      (1,'Statistik außerhalb Winterzeitraum','2025-12-31T22:59:59.000Z','','','','',''),
      (1,'Statistik Winter Mitternacht','2025-12-31T23:00:00.000Z','','','','','');
    SET @outside=LAST_INSERT_ID(); SET @midnight=@outside+1; SET @i1=@outside+2; SET @i2=@outside+3; SET @i3=@outside+4; SET @i4=@outside+5; SET @winter_outside=@outside+6; SET @winter_midnight=@outside+7;
    INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES
      (@outside,1,JSON_ARRAY()),(@midnight,1,JSON_ARRAY()),
      (@i1,1,JSON_ARRAY(JSON_OBJECT('id','lf20','name','LF 20 Statistik','own',TRUE))),
      (@i2,1,JSON_ARRAY(JSON_OBJECT('id','lf20','name','LF 20 Statistik','own',TRUE),JSON_OBJECT('id','mtf','name','MTF Statistik','own',FALSE))),
      (@i3,1,JSON_ARRAY('TLF Statistik')),(@i4,1,JSON_ARRAY()),
      (@winter_outside,1,JSON_ARRAY()),(@winter_midnight,1,JSON_ARRAY()),
      (@i1,$second_unit_id,JSON_ARRAY(JSON_OBJECT('name','Gemeinsames Fremdfahrzeug','own',TRUE)));
    INSERT INTO reports(incident_id,unit_id,author_id,author_name,narrative,vehicles,personnel,classification) VALUES
      (@i1,1,@leader_id,'Einheitsleitung Eins','Statistik','','',JSON_OBJECT()),(@i2,1,@leader_id,'Einheitsleitung Eins','Statistik','','',JSON_OBJECT()),
      (@i1,$second_unit_id,1,'Wehrführung','Fremder Einheitsbericht','','',JSON_OBJECT());
    SET @r1=LAST_INSERT_ID(); SET @r2=@r1+1;
    SET @foreign_report=@r1+2;
    UPDATE incidents SET report_data_frozen=1 WHERE id IN (@i1,@i2);
    INSERT INTO members(organization_id,divera_id,name) VALUES(1,'statistics-active','Aktives Statistikmitglied'),(1,'statistics-inactive','Historisches Statistikmitglied'),(1,'statistics-foreign-unit','Fremdes Statistikmitglied');
    SET @m1=LAST_INSERT_ID(); SET @m2=@m1+1; SET @foreign_member=@m1+2;
    INSERT INTO member_units(member_id,unit_id,active) VALUES(@m1,1,TRUE),(@m2,1,FALSE),(@foreign_member,$second_unit_id,TRUE);
    INSERT INTO report_crew(report_id,member_id,member_name,vehicle,role) VALUES(@r1,@m1,'Aktives Statistikmitglied','LF 20 Statistik','maschinist'),(@r1,@m2,'Historisches Statistikmitglied','','besatzung'),(@foreign_report,@foreign_member,'Fremdes Statistikmitglied','','besatzung');
    INSERT INTO report_additional_vehicles(report_id,vehicle) VALUES(@r1,'ELW Statistik');
    INSERT INTO organizations(name) VALUES('Fremde Statistikwehr'); SET @foreign_org=LAST_INSERT_ID();
    INSERT INTO units(organization_id,name) VALUES(@foreign_org,'Fremde Einheit'); SET @foreign_unit=LAST_INSERT_ID();
    INSERT INTO incidents(organization_id,title,started_at,message,remark,patient,caller,consolidated_text) VALUES(@foreign_org,'Fremder Statistikeinsatz','2026-09-04T15:00:00.000Z','','','','',''); SET @foreign_incident=LAST_INSERT_ID();
    INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(@foreign_incident,@foreign_unit,JSON_ARRAY(JSON_OBJECT('name','Mandantenfahrzeug','own',TRUE)))"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/statistics?from=2026-09-04&to=2026-09-07")" = 403
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" "$base_url/api/statistics?from=2026-09-04&to=2026-09-07")" = 403
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$leader_token" "$base_url/api/statistics?from=2026-09-08&to=2026-09-07")" = 400
# Statistikgrenzen akzeptieren keine Query-Arrays statt eines Datumsstrings.
for date_field in from to; do
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$leader_token" \
    "$base_url/api/statistics?$date_field%5B%5D=2026-09-04")" = 400
done
# Alarmierte Fahrzeuge anderer Einheiten erscheinen nicht in der Statistik.
curl --insecure --silent --fail --cookie "$session_cookie=$leader_token" "$base_url/api/statistics?from=2026-09-04&to=2026-09-07" |
  php -r '
    $data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
    assert($data["unit"]["name"]==="Löschzug");
    assert($data["totals"]===["incidents"=>5,"reports"=>2,"crewAssignments"=>2,"averageCrew"=>1]);
    assert($data["workPeriods"]===["workday"=>3,"weekend"=>2]);
    assert($data["dayPeriods"]===["day"=>2,"night"=>3]);
    assert($data["years"]===[["key"=>"2026","count"=>5]]);
    assert($data["months"]===[["key"=>"2026-09","count"=>5]]);
    assert($data["weekdays"]===[["key"=>"1","count"=>2],["key"=>"5","count"=>3]]);
    assert($data["alarmedVehicles"]===[
      ["name"=>"LF 20 Statistik","own"=>true,"count"=>2],
      ["name"=>"TLF Statistik","own"=>true,"count"=>1]
    ]);
    assert($data["additionalVehicles"]===[["name"=>"ELW Statistik","count"=>1]]);
    assert(array_column($data["members"],"name")===["Aktives Statistikmitglied","Historisches Statistikmitglied"]);
    assert(!isset($data["members"][0]["id"]));
    assert(!str_contains(json_encode($data,JSON_THROW_ON_ERROR),"Mandantenfahrzeug"));
    assert(!str_contains(json_encode($data,JSON_THROW_ON_ERROR),"Fremdes Statistikmitglied"));
  '
curl --insecure --silent --fail --cookie "$session_cookie=$leader_token" "$base_url/api/statistics?from=2026-01-01&to=2026-01-01" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($data["totals"]["incidents"]===1);'
curl --insecure --silent --fail --cookie "$session_cookie=$leader_token" "$base_url/api/statistics?from=2024-01-01&to=2024-12-31" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($data["totals"]["incidents"]===0); assert($data["totals"]["averageCrew"]===null); assert($data["alarmedVehicles"]===[]); assert($data["members"]===[]);'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM incidents WHERE organization_id=1 AND title LIKE 'Statistik %';
    DELETE FROM members WHERE organization_id=1 AND divera_id IN ('statistics-active','statistics-inactive','statistics-foreign-unit');
    DELETE FROM incidents WHERE organization_id=(SELECT id FROM organizations WHERE name='Fremde Statistikwehr');
    DELETE FROM units WHERE organization_id=(SELECT id FROM organizations WHERE name='Fremde Statistikwehr');
    DELETE FROM organizations WHERE name='Fremde Statistikwehr'"

# Nicht-Wehrführungen sehen nur aktuell zugeordnete Einheiten, Fahrzeuge und rollenbezogene Berichtsstatus.
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units" |
  php -r '$units=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(array_column($units,"id")===[1]);'
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '
    $items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
    $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0];
    $assignments=$incident["assignments"];
    assert(array_column($assignments,"unitId")===[1]);
    assert($incident["units"]==="Löschzug");
    assert(!str_contains(json_encode($incident),"Fremdfahrzeug"));
  '
test "$(incident_status "$force_token" "$incident_id")" = report_required
test "$(incident_status "$leader_token" "$incident_id")" = report_required

# Berichte starten rollenabhängig, bleiben bis zur jeweiligen Übergabe verborgen und speichern die Fachdaten.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO vehicles(unit_id,divera_id,name) VALUES(1,'manual-extra','Zusatzfahrzeug'),($second_unit_id,'foreign-extra','Fremdfahrzeug');
    INSERT INTO members(id,organization_id,divera_id,name) VALUES(100,1,'test-100','Person 100');
    INSERT INTO member_units(member_id,unit_id) VALUES(100,1)"
report_payload='{"unitId":1,"foreign_id":"manipuliert","divera_id":"manipuliert","runningNumber":"69/2026","damagedParty":{"name":"Max Mustermann","phone":"02733 123","address":"Musterweg 1"},"damagingParty":{"name":"Erika Beispiel","phone":"","address":"Beispielweg 2"},"incidentCommand":{"rank":"BOI","name":"D. Gerlach","additionalRank":"BI","additionalName":"A. Busch"},"narrative":"Ursprünglich","departedAt":"2026-08-22T18:05:00.000Z","arrivedAt":"2026-08-22T18:10:00.000Z","endedAt":"2026-08-22T19:00:00.000Z","incidentType":"Technische Hilfe","classification":{"site":[],"cause":[],"technical":[]},"crew":[]}'
base_report_payload="$report_payload"
report_with_additional_vehicle="${report_payload/\"crew\":[]/\"additionalVehicles\":[\"Zusatzfahrzeug\"],\"crew\":[{\"memberId\":100,\"vehicle\":\"Zusatzfahrzeug\",\"role\":\"maschinist\"}]}"
report_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --data "$report_with_additional_vehicle" \
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

# Ungültige Kontakt-, Aufgliederungs-, Besatzungs-, Fahrzeug- und Datumstypen liefern 400 ohne Änderungen, auch bei später Textvalidierung.
API_BASE_URL="$base_url" COOKIE="$session_cookie=$force_token" INCIDENT_ID="$incident_id" REPORT_ID="$report_id" \
  PAYLOAD="$report_with_additional_vehicle" php -r '
  $call=function(string $path, ?object $payload=null): array {
    $args=["curl","--insecure","--silent","--show-error","--cookie",getenv("COOKIE"),"--write-out","\n%{http_code}",getenv("API_BASE_URL").$path];
    if($payload!==null) array_push($args,"--header","Content-Type: application/json","--request","PUT","--data",json_encode($payload,JSON_THROW_ON_ERROR|JSON_PRESERVE_ZERO_FRACTION));
    $process=proc_open($args,[0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
    fclose($pipes[0]); $body=stream_get_contents($pipes[1]); stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    if(proc_close($process)!==0) throw new RuntimeException("API-Testtransport fehlgeschlagen");
    return [(int)substr($body,-3),substr($body,0,-4)];
  };
  $path="/api/reports/".getenv("REPORT_ID");
  $read="/api/incidents/".getenv("INCIDENT_ID")."/reports";
  $before=$call($read);
  $loaded=json_decode($before[1],false,512,JSON_THROW_ON_ERROR)[0];
  foreach(["damaged_party","damaging_party","incident_command","classification"] as $field) {
    if(!$loaded->$field instanceof stdClass) throw new RuntimeException("Berichtsfeld ist kein natives Objekt");
  }
  if(!is_array($loaded->crew) || !is_array($loaded->history) || !is_array($loaded->additionalVehicles)) throw new RuntimeException("Berichtsliste ist nicht nativ");
  foreach(["created_at","updated_at","alarmed_at","ended_at"] as $field) {
    if(!preg_match("/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/D",$loaded->$field)) throw new RuntimeException("Berichtszeit ist nicht ISO-UTC");
  }
  // Typfehler benennen die Objektgruppe, nicht das darin enthaltene Namens- oder Dienstgradfeld.
  foreach(["damagedParty"=>"Geschädigte Person","damagingParty"=>"Schädiger","incidentCommand"=>"Einsatzleitung"] as $group=>$label) {
    $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
    $data->$group=[]; $data->revision=$loaded->revision;
    [$status,$body]=$call($path,$data);
    if($status!==400 || json_decode($body,true,512,JSON_THROW_ON_ERROR)!==["error"=>$label." muss ein Objekt sein"]
      || $call($read)!==$before) throw new RuntimeException("Irreführende Objektfehlermeldung oder Teilmutation");
  }
  $invalid=[
    "{\"damagedParty\":[]}", "{\"damagedParty\":\"Text\"}", "{\"damagedParty\":{\"name\":[]}}",
    "{\"damagingParty\":{\"phone\":{}}}", "{\"incidentCommand\":{\"rank\":[]}}",
    "{\"classification\":[]}", "{\"classification\":true}", "{\"classification\":{\"site\":{}}}",
    "{\"classification\":{\"cause\":\"Brand\"}}", "{\"classification\":{\"technical\":[{}]}}",
    "{\"crew\":{}}", "{\"crew\":\"[]\"}", "{\"crew\":[[]]}", "{\"crew\":[true]}",
    "{\"crew\":[{\"memberId\":100,\"vehicle\":[]}]}","{\"crew\":[{\"memberId\":100,\"role\":{}}]}",
    "{\"crew\":[{\"memberId\":100,\"vehicle\":0}]}",
    "{\"additionalVehicles\":{}}", "{\"additionalVehicles\":[[]]}",
    "{\"endedAt\":[]}", "{\"departedAt\":{}}", "{\"arrivedAt\":true}", "{\"endedAt\":\"2026-02-30T19:00:00.000Z\"}",
    "{\"runningNumber\":{}}", "{\"narrative\":[],\"crew\":[],\"additionalVehicles\":[]}"
  ];
  foreach(["true","100.0","100.5","\"100x\"","\"1e2\"","\"0100\"","0","-1","9223372036854775808","\"18446744073709551616\""] as $id) {
    $invalid[]="{\"crew\":[{\"memberId\":$id,\"vehicle\":\"\",\"role\":\"besatzung\"}]}";
  }
  foreach($invalid as $index=>$override) {
    $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
    foreach(json_decode($override,false,512,JSON_THROW_ON_ERROR) as $key=>$value) $data->$key=$value;
    $data->revision=$loaded->revision;
    if($call($path,$data)[0]!==400) throw new RuntimeException("Ungültiger Berichtstyp akzeptiert: Test ".$index);
    if($call($read)!==$before) throw new RuntimeException("Teilmutation bei ungültigem Bericht: Test ".$index);
  }
'

# Fehlend, null und leere Objekte leeren optionale Kontakte; leere Listen bleiben Listen, gültige Textskalare und kanonische ID-Strings bleiben verwendbar.
API_BASE_URL="$base_url" COOKIE="$session_cookie=$force_token" INCIDENT_ID="$incident_id" REPORT_ID="$report_id" \
  PAYLOAD="$report_with_additional_vehicle" php -r '
  $call=function(?object $payload=null): array {
    $path=$payload===null ? "/api/incidents/".getenv("INCIDENT_ID")."/reports" : "/api/reports/".getenv("REPORT_ID");
    $args=["curl","--insecure","--silent","--show-error","--fail","--cookie",getenv("COOKIE"),getenv("API_BASE_URL").$path];
    if($payload!==null) array_push($args,"--header","Content-Type: application/json","--request","PUT","--data",json_encode($payload,JSON_THROW_ON_ERROR));
    $process=proc_open($args,[0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
    fclose($pipes[0]); $body=stream_get_contents($pipes[1]); stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    if(proc_close($process)!==0) throw new RuntimeException("Gültige Leerwerte abgelehnt");
    return (array)json_decode($body,false,512,JSON_THROW_ON_ERROR);
  };
  foreach(["missing","null","object"] as $mode) {
    $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
    foreach(["damagedParty","damagingParty","incidentCommand","classification"] as $field) {
      if($mode==="missing") unset($data->$field);
      else $data->$field=$mode==="null" ? null : new stdClass();
    }
    $data->departedAt=null; $data->arrivedAt=""; $data->crew=[]; $data->additionalVehicles=[];
    $data->revision=$call()[0]->revision; $call($data);
    $saved=$call()[0];
    if($saved->damaged_party->name!=="" || $saved->classification->site!==[] || $saved->crew!==[] || $saved->departed_at!==null || $saved->arrived_at!==null) {
      throw new RuntimeException("Leerwertsemantik geändert");
    }
  }
  $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
  $data->damagedParty->name=123; $data->damagedParty->phone=0; $data->damagedParty->address=false;
  $data->crew[0]->memberId="100"; $data->revision=$call()[0]->revision; $call($data);
  $saved=$call()[0];
  if($saved->damaged_party->name!=="123" || $saved->damaged_party->phone!=="0" || $saved->damaged_party->address!=="" || $saved->crew[0]->memberId!==100) {
    throw new RuntimeException("Gültige skalare Eingabe verändert");
  }
  $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
  // Gültige kürzere Sekundenbruchteile bleiben erlaubt und erscheinen kanonisch mit drei Millisekundenstellen.
  foreach(["1","12","123"] as $fraction) {
    $prefix=substr($data->endedAt,0,20);
    $data->endedAt=$prefix.$fraction."Z";
    $data->revision=$call()[0]->revision; $call($data);
    $saved=$call()[0];
    if($saved->ended_at!==$prefix.str_pad($fraction,3,"0")."Z") throw new RuntimeException("Gültiger Sekundenbruch verändert");
  }
  $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
  $data->revision=$saved->revision; $call($data);
'

# Zwei geladene Editoren: Der erste speichert, der zweite darf weder Text noch native Besatzungslisten oder Zusatzfahrzeuge überschreiben.
editor_one=$(report_data "$report_with_additional_vehicle")
editor_two=$(report_data "${base_report_payload/Ursprünglich/Veralteter Text}")
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --request PUT --data "$editor_one" "$base_url/api/reports/$report_id" >/dev/null
saved_report=$(curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports")
EDITOR_ONE="$editor_one" SAVED_REPORT="$saved_report" php -r '
  $loaded=json_decode(getenv("EDITOR_ONE"),true,512,JSON_THROW_ON_ERROR);
  $saved=json_decode(getenv("SAVED_REPORT"),true,512,JSON_THROW_ON_ERROR)[0];
  assert($saved["revision"]===$loaded["revision"]+1);
  assert($saved["narrative"]==="Ursprünglich");
  assert($saved["additionalVehicles"]===["Zusatzfahrzeug"]);
  assert($saved["crew"][0]["memberId"]===100);
'
# Eine veraltete Berichtsrevision meldet HTTP 409 mit einem kontextneutralen Hinweis auf den geladenen Stand.
test "$(curl --insecure --silent --write-out '|%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --request PUT --data "$editor_two" "$base_url/api/reports/$report_id")" = '{"error":"Der geladene Stand wurde inzwischen geändert."}|409'
test "$(curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports")" = "$saved_report"

# Eine wartende Bearbeitung sperrt zuerst den Einsatz und prüft die Revision erst nach dem konkurrierenden Commit erneut.
REPORT_ID="$report_id" INCIDENT_ID="$incident_id" COOKIE="$session_cookie=$force_token" \
  PAYLOAD="$(report_data "$base_report_payload")" API_BASE_URL="$base_url" php -r '
  require "support.php";
  $reportId=(int)getenv("REPORT_ID");
  $incidentId=(int)getenv("INCIDENT_ID");
  db()->beginTransaction();
  query("SELECT id FROM incidents WHERE id=? FOR UPDATE",[$incidentId]);
  $process=proc_open(["curl","--insecure","--silent","--show-error","--max-time","15","--output","/dev/null","--write-out","%{http_code}",
    "--cookie",getenv("COOKIE"),"--header","Content-Type: application/json","--request","PUT","--data",getenv("PAYLOAD"),
    getenv("API_BASE_URL")."/api/reports/$reportId"],[0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
  if(!is_resource($process)) throw new RuntimeException("Parallele Bearbeitung konnte nicht gestartet werden");
  fclose($pipes[0]);
  try {
    $waiting=null;
    $deadline=microtime(true)+5;
    while(microtime(true)<$deadline) {
      $waiting=one("SELECT l.OBJECT_NAME AS table_name,l.INDEX_NAME AS index_name
        FROM performance_schema.data_lock_waits w
        JOIN performance_schema.data_locks l ON l.ENGINE=w.ENGINE AND l.ENGINE_LOCK_ID=w.REQUESTING_ENGINE_LOCK_ID
        JOIN performance_schema.threads t ON t.THREAD_ID=w.BLOCKING_THREAD_ID
        WHERE t.PROCESSLIST_ID=CONNECTION_ID() AND l.OBJECT_SCHEMA=DATABASE()");
      if($waiting) break;
      usleep(100000);
    }
    if(!$waiting || $waiting["table_name"]!=="incidents" || $waiting["index_name"]!=="PRIMARY") throw new RuntimeException("Bearbeitung wartet nicht auf den primären Einsatzdatensatz");
    query("UPDATE reports SET revision=revision+1 WHERE id=?",[$reportId]);
    query("UPDATE incidents SET revision=revision+1 WHERE id=?",[$incidentId]);
    db()->commit();
    if(stream_get_contents($pipes[1])!=="409") throw new RuntimeException("Wartende Bearbeitung hat die veraltete Revision akzeptiert");
    $saved=one("SELECT narrative,revision FROM reports WHERE id=?",[$reportId]);
    $loaded=json_decode(getenv("PAYLOAD"),true,512,JSON_THROW_ON_ERROR);
    assert($saved["narrative"]==="Ursprünglich" && (int)$saved["revision"]===$loaded["revision"]+1);
    assert((int)query("SELECT COUNT(*) FROM report_crew WHERE report_id=?",[$reportId])->fetchColumn()===1);
    assert((int)query("SELECT COUNT(*) FROM report_additional_vehicles WHERE report_id=?",[$reportId])->fetchColumn()===1);
  } finally {
    if(db()->inTransaction()) db()->rollBack();
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($process);
  }
'
saved_report=$(curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports")

# Fehlende und ungültige Revisionen werden vor jeder fachlichen Mutation abgewiesen.
for invalid_revision in null 0 -1 1.5 true '"1"' '[]' '{}' 4294967296; do
  invalid_payload=$(PAYLOAD="$report_with_additional_vehicle" REVISION="$invalid_revision" php -r '
    $data=json_decode(getenv("PAYLOAD"),true,512,JSON_THROW_ON_ERROR);
    $data["revision"]=json_decode(getenv("REVISION"),true,512,JSON_THROW_ON_ERROR);
    echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
  ')
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
    --header 'Content-Type: application/json' --request PUT --data "$invalid_payload" "$base_url/api/reports/$report_id")" = 400
done
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --request PUT --data "$report_with_additional_vehicle" "$base_url/api/reports/$report_id")" = 400
test "$(curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports")" = "$saved_report"

# Zusätzliche Fahrzeuge stammen aus dem aktuellen Stamm der Berichtseinheit, sind Besatzungsziele und für fremde Rollen sowie Einheiten gesperrt.
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT((SELECT GROUP_CONCAT(vehicle) FROM report_additional_vehicles WHERE report_id=$report_id_int),'|',(SELECT vehicle FROM report_crew WHERE report_id=$report_id_int AND member_id=100))")" = 'Zusatzfahrzeug|Zusatzfahrzeug'
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($reports[0]["additionalVehicles"]===["Zusatzfahrzeug"]);'
assert_pdf "$force_token" "/api/reports/$report_id/pdf" 'Zusätzliche Fahrzeuge: Zusatzfahrzeug|Zusatzfahrzeug | Maschinist: Person 100'
foreign_vehicle_payload="${report_payload/\"crew\":[]/\"additionalVehicles\":[\"Fremdfahrzeug\"],\"crew\":[]}"
# Eine aktuelle Revision umgeht nicht die Fremdfahrzeugprüfung.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$foreign_vehicle_payload")" "$base_url/api/reports/$report_id")" = 400
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$other_force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$report_with_additional_vehicle" "$base_url/api/reports/$report_id")" = 403

# Ein aus dem aktuellen Stamm verschwundenes Zusatzfahrzeug bleibt unverändert erhalten, kann aber keiner anderen Person neu zugeordnet werden.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM vehicles WHERE unit_id=1 AND divera_id='manual-extra';
    INSERT INTO members(id,organization_id,divera_id,name) VALUES(99,1,'test-99','Person 99');
    INSERT INTO member_units(member_id,unit_id) VALUES(99,1)"
# Die geladene Revision erlaubt den Erhalt der historischen Fahrzeugzuordnung.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$report_with_additional_vehicle")" "$base_url/api/reports/$report_id")" = 200
historical_new_assignment=$(printf '%s' "$report_with_additional_vehicle" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $data["crew"][0]["memberId"]=99; echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);')
# Auch mit aktueller Revision bleibt eine neue historische Fahrzeugzuordnung unzulässig.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$historical_new_assignment")" "$base_url/api/reports/$report_id")" = 400

# Ein zusätzliches Fahrzeug kann erst entfernt werden, nachdem seine Besatzung im selben Speichervorgang entfernt wurde.
vehicle_removed_with_crew=$(printf '%s' "$report_with_additional_vehicle" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $data["additionalVehicles"]=[]; echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);')
# Die aktuelle Revision ersetzt nicht die Prüfung verbliebener Besatzung.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$vehicle_removed_with_crew")" "$base_url/api/reports/$report_id")" = 400
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM members WHERE id=99"

# Wird das Zusatzfahrzeug später von DIVERA alarmiert, wird der doppelte Berichtseintrag beim Speichern entfernt, ohne die Besatzung zu blockieren.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE incident_units SET vehicles=JSON_ARRAY(JSON_OBJECT('id','manual-extra','name','Zusatzfahrzeug','own',TRUE)) WHERE incident_id=$incident_id AND unit_id=1"
# Mit aktueller Revision kann das inzwischen alarmierte Zusatzfahrzeug bereinigt werden.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$report_with_additional_vehicle")" "$base_url/api/reports/$report_id")" = 200
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT COUNT(*) FROM report_additional_vehicles WHERE report_id=$report_id_int")" = 0
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE incident_units SET vehicles=JSON_ARRAY() WHERE incident_id=$incident_id AND unit_id=1;
    INSERT INTO vehicles(unit_id,divera_id,name) VALUES(1,'manual-extra','Zusatzfahrzeug')"
# Das erneut verfügbare Zusatzfahrzeug wird mit aktueller Revision gespeichert.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$report_with_additional_vehicle")" "$base_url/api/reports/$report_id" >/dev/null

report_payload=$(printf '%s' "$base_report_payload" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $data["additionalVehicles"]=["Zusatzfahrzeug"]; echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);')
# Eine aktuelle Bearbeitung darf die Besatzung entfernen und das Zusatzfahrzeug behalten.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$report_payload")" "$base_url/api/reports/$report_id" >/dev/null
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM members WHERE id=100"

# Ausrücke- und Eintreffzeit können bei einem abgebrochenen Einsatz geleert werden.
report_without_travel_times="${report_payload/\"departedAt\":\"2026-08-22T18:05:00.000Z\",\"arrivedAt\":\"2026-08-22T18:10:00.000Z\"/\"departedAt\":null,\"arrivedAt\":null}"
# Auch das Leeren optionaler Zeiten verlangt die aktuelle Berichtsrevision.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "$(report_data "$report_without_travel_times")" \
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
    INSERT INTO reports(id,incident_id,unit_id,author_id,author_name,narrative,vehicles,personnel,classification,status) VALUES(900,900,900,900,'Fremde Wehrführung','Fremder Bericht','','',JSON_OBJECT(),'wehr_review');
    UPDATE incidents SET report_data_frozen=1 WHERE id=900;
    INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,created_at) VALUES(900,NULL,'wehr_review',900,'Fremde Wehrführung','wehrleitung',UTC_TIMESTAMP())"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/incidents/900/pdf")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/reports/900/pdf")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/incidents/900/consolidation/pdf")" = 404

# Versionsangaben eröffnen weder fremde Mandanten noch zusätzliche Rollenrechte auf schreibende Berichtswege.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data '{"revision":1}' "$base_url/api/reports/900")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request POST --data '{"revision":1,"comment":"Unzulässig"}' "$base_url/api/reports/900/return-to-unit")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data '{"revision":1,"reportVersions":[{"id":900,"revision":1}],"text":"Unzulässig"}' "$base_url/api/incidents/900/consolidation")" = 404
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --request PUT --data '{"revision":1,"reportVersions":[],"text":"Unzulässig"}' "$base_url/api/incidents/$incident_id/consolidation")" = 403

# Native Besatzungslisten werden unabhängig von der Einfügereihenfolge stabil nach Mitglieds-ID sortiert ausgegeben.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO members(id,organization_id,divera_id,name) VALUES(101,1,'test-101','Person 101'),(102,1,'test-102','Person 102'); INSERT INTO member_units(member_id,unit_id) VALUES(101,1),(102,1); INSERT INTO report_crew(report_id,member_id,member_name) VALUES($report_id_int,102,'Person 102'),($report_id_int,101,'Person 101')"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $crew=$reports[0]["crew"]; assert(array_column($crew,"memberId")===[101,102]);'

# Auch aus umgekehrt eingesendeter Besatzung entstehen stabile Personal- und Fahrzeugzusammenfassungen.
reverse_crew="${report_payload/\"crew\":[]/\"crew\":[{\"memberId\":102},{\"memberId\":\"101\"}]}"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --request PUT --data "$(report_data "$reverse_crew")" "$base_url/api/reports/$report_id" >/dev/null
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$report=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR)[0]; assert($report["personnel"]==="Person 101, Person 102"); assert($report["vehicles"]===""); assert(array_column($report["crew"],"memberId")===[101,102]);'

# Laufende Nummern sind pro Einheit und Kalenderjahr eindeutig und erhalten eine eigene fachliche 409-Meldung.
duplicate_incident_id=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --data '{"title":"Zweiter Testeinsatz","startedAt":"2026-08-22T18:00:00.000Z","address":"","unitIds":[1]}' \
  "$base_url/api/incidents" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); echo $data["id"];')
test "$(curl --insecure --silent --write-out '|%{http_code}' \
  --header 'Content-Type: application/json' \
  --cookie "$session_cookie=$force_token" \
  --data "$report_payload" \
  "$base_url/api/incidents/$duplicate_incident_id/reports")" = '{"error":"Diese laufende Nummer wird in dieser Einheit und diesem Kalenderjahr bereits verwendet"}|409'

# Pro alarmierter Einheit gibt es genau einen Bericht; dieser Konflikt wird nicht als Nummernkonflikt ausgegeben.
test "$(curl --insecure --silent --write-out '|%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --data "$report_payload" \
  "$base_url/api/incidents/$incident_id/reports")" = '{"error":"Für diese Einheit existiert bereits ein Einsatzbericht"}|409'

# Eine späte Besatzungsvalidierung bei der Neuanlage rollt auch den zuvor eingefügten Bericht und alle Revisionen zurück.
before_invalid_creation=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents")
invalid_creation="${base_report_payload/69\/2026/97\/2026}"
invalid_creation="${invalid_creation/\"crew\":[]/\"crew\":[{\"memberId\":true}]}"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --data "$invalid_creation" \
  "$base_url/api/incidents/$duplicate_incident_id/reports")" = 400
test "$(curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/incidents/$duplicate_incident_id/reports")" = '[]'
test "$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents")" = "$before_invalid_creation"

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
# Der Autor kann den Entwurf mit seiner geladenen Revision bearbeiten.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "$(report_data "${report_payload/Ursprünglich/Manipuliert}")" \
  "$base_url/api/reports/$report_id")" = 200
# Die erste Übergabe verwendet die nach dem Speichern neu geladene Revision.
stale_author_submit=$(report_data '{}')
stale_author_edit=$(report_data "${report_payload/Ursprünglich/Veralteter Autorenstand}")
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$stale_author_submit" \
  "$base_url/api/reports/$report_id/submit-to-unit" >/dev/null
# Ein bereits geöffneter Autoreneditor erhält auch nach einer Übergabe einen Konflikt statt den Prüfstand zu überschreiben.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --request PUT --data "$stale_author_edit" "$base_url/api/reports/$report_id")" = 409
test "$(incident_status "$force_token" "$incident_id")" = submitted
test "$(incident_status "$other_force_token" "$incident_id")" = report_exists
test "$(incident_status "$leader_token" "$incident_id")" = review_required
assert_pdf "$leader_token" "/api/reports/$report_id/pdf" 'Einzelbericht|Einheitsleitung Eins|Rolle: Einheitsführung|Manipuliert'
# Auch mit aktueller Revision ist die wiederholte Übergabe im falschen Status ein Konflikt.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$(report_data '{}')" \
  "$base_url/api/reports/$report_id/submit-to-unit")" = 409
# Eine gültige Revision ersetzt nicht den Pflichtkommentar bei einer Rückgabe.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$(report_data '{}')" \
  "$base_url/api/reports/$report_id/return-to-author")" = 400

# Die Rückgabe verlangt eine weiterhin bestehende Autorenzuordnung und bleibt in der Historie sichtbar.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE uu FROM user_units uu JOIN users u ON u.id=uu.user_id WHERE u.email='fuehrungskraft@example.test' AND uu.unit_id=1"
# Die Einheitsführung kann trotz aktueller Revision nicht an einen nicht mehr zugeordneten Autor zurückgeben.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$(report_data '{"comment":"Bitte ergänzen"}' "$leader_token")" \
  "$base_url/api/reports/$report_id/return-to-author")" = 409
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO user_units(user_id,unit_id) SELECT id,1 FROM users WHERE email='fuehrungskraft@example.test'"
# Nach Wiederherstellung der Zuordnung gelingt die Rückgabe mit aktueller Revision.
stale_author_return=$(report_data '{"comment":"Bitte ergänzen"}')
curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$stale_author_return" \
  "$base_url/api/reports/$report_id/return-to-author" >/dev/null
curl --insecure --silent --fail --cookie "$session_cookie=$leader_token" "$base_url/api/incidents/$incident_id/reports" |
  php -r '$reports=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($reports[0]["status"]==="author_draft"); assert($reports[0]["editable"]===false); assert(end($reports[0]["history"])["comment"]==="Bitte ergänzen");'
# Nach author_draft → unit_review → author_draft scheitert die alte Übergabe trotz identischem Status.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --request POST --data "$stale_author_submit" "$base_url/api/reports/$report_id/submit-to-unit")" = 409
# Der Autor reicht die zurückgegebene neue Revision erneut ein.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' --request POST --data "$(report_data '{}')" \
  "$base_url/api/reports/$report_id/submit-to-unit" >/dev/null
# Die alte Rückgabe an den Autor bleibt nach der erneuten Einreichung gesperrt; ohne Revision geht es ebenfalls nicht.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' --request POST --data "$stale_author_return" "$base_url/api/reports/$report_id/return-to-author")" = 409
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' --request POST --data '{}' "$base_url/api/reports/$report_id/submit-to-command")" = 400
# Die Einheitsführung übergibt genau den geladenen Berichtsstand an die Wehrführung.
stale_command_submit=$(report_data '{}')
curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" --header 'Content-Type: application/json' --request POST --data "$stale_command_submit" \
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
second_report_payload="${base_report_payload/\"unitId\":1/\"unitId\":$second_unit_id}"
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' \
  --data "$second_report_payload" \
  "$base_url/api/incidents/$incident_id/reports" >/dev/null
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '$items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0]; assert($incident["reportStatus"]["key"]==="ready");'
# Zwei Wehrführungseditoren dürfen einen neueren Gesamttext nicht mit derselben geladenen Revision überschreiben.
stale_consolidation=$(consolidation_data 'Veralteter Gesamttext')
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(consolidation_data 'Konsolidiert: Nicht freigegebene Angaben der anderen Einheit')" "$base_url/api/incidents/$incident_id/consolidation" >/dev/null
saved_consolidation=$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents")
# Derselbe Konflikthinweis passt auch zu einer veralteten Einsatz-/Gesamtstandsrevision und erhält HTTP 409.
test "$(curl --insecure --silent --write-out '|%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data "$stale_consolidation" "$base_url/api/incidents/$incident_id/consolidation")" = '{"error":"Der geladene Stand wurde inzwischen geändert."}|409'
test "$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents")" = "$saved_consolidation"
# Die Quellenrevisionen sind zusätzlich zur Gesamtstandsrevision verpflichtend.
missing_sources=$(consolidation_data 'Ohne Quellen' | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); unset($data["reportVersions"]); echo json_encode($data,JSON_THROW_ON_ERROR);')
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data "$missing_sources" "$base_url/api/incidents/$incident_id/consolidation")" = 400
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data '{"text":"Ohne Revision"}' "$base_url/api/incidents/$incident_id/consolidation")" = 400
# Revisionsquellen müssen eine Liste von Objekten mit gültigen IDs und ganzzahligen Revisionen sein; ungültige Formen verändern den Gesamtstand nicht.
for invalid_sources in '{}' '"[]"' '[[]]' '[{"id":true,"revision":1}]' '[{"id":1.0,"revision":1}]' \
  '[{"id":"1x","revision":1}]' '[{"id":9223372036854775808,"revision":1}]' '[{"id":1,"revision":true}]' \
  '[{"id":1,"revision":1},{"id":"1","revision":1}]'; do
  invalid_consolidation=$(SOURCES="$invalid_sources" PAYLOAD="$(consolidation_data 'Ungültige Quellen')" php -r '
    $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
    $data->reportVersions=json_decode(getenv("SOURCES"),false,512,JSON_THROW_ON_ERROR);
    echo json_encode($data,JSON_THROW_ON_ERROR|JSON_PRESERVE_ZERO_FRACTION);
  ')
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
    --header 'Content-Type: application/json' --request PUT --data "$invalid_consolidation" "$base_url/api/incidents/$incident_id/consolidation")" = 400
done
test "$(curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents")" = "$saved_consolidation"
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE incidents SET consolidated_at='2026-08-24 09:00:00' WHERE id=$incident_id"
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '$items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0]; assert($incident["reportStatus"]["key"]==="completed");'
assert_pdf "$session_token" "/api/incidents/$incident_id/consolidation/pdf" 'Abgeschlossener Gesamtbericht|Konsolidiert|Admin|Rolle: Wehrführung|Manipuliert|24.08.2026 11:00 Uhr'

# Ein abgeschlossener Mehr-Einheiten-Gesamttext bleibt für Führungskraft und Einheitsführung unsichtbar.
assert_consolidated_visibility "$incident_id"

# Eine Rückgabe durch die Wehrführung invalidiert die Konsolidierung bis zur erneuten Übergabe.
stale_command_return=$(report_data '{"comment":"Bitte durch die Einheit prüfen"}')
before_return_consolidation=$(consolidation_data 'Veraltete Quellen')
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  --data "$stale_command_return" "$base_url/api/reports/$report_id/return-to-unit" >/dev/null
# Nach unit_review → wehr_review → unit_review ist die alte Übergabe ohne jede Mutation ein Konflikt.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' --request POST --data "$stale_command_submit" "$base_url/api/reports/$report_id/submit-to-command")" = 409
curl --insecure --silent --fail --cookie "$session_cookie=$session_token" "$base_url/api/incidents" |
  INCIDENT_ID="$incident_id" php -r '$items=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $incident=array_values(array_filter($items,fn($item)=>$item["id"]===(int)getenv("INCIDENT_ID")))[0]; assert($incident["reportStatus"]["key"]==="reports_pending"); assert($incident["reportStatus"]["pendingUnits"]===["Löschzug"]);'
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" "$base_url/api/incidents/$incident_id/consolidation/pdf")" = 409
test "$(incident_status "$leader_token" "$incident_id")" = review_required
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(status,'|',consolidated_at IS NULL,'|',(SELECT COUNT(*) FROM report_transitions WHERE report_id=$report_id_int)) FROM reports JOIN incidents ON incidents.id=reports.incident_id WHERE reports.id=$report_id_int")" = 'unit_review|1|6'
# Auch der nach einer Rückgabe zurückbehaltene Gesamttext ist ausschließlich für die Wehrführung sichtbar.
assert_consolidated_visibility "$incident_id"

# Solange der zurückgegebene Bericht noch nicht erneut freigegeben wurde, bleibt die Konsolidierung gesperrt.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(consolidation_data 'Zu früh')" "$base_url/api/incidents/$incident_id/consolidation")" = 409
# Die Einheitsführung überarbeitet die zurückgegebene Quelle; ein alter Gesamtstand darf diese Änderung nicht übergehen.
curl --insecure --silent --fail --cookie "$session_cookie=$leader_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "${report_payload/Ursprünglich/Manipuliert – neue Quellenfassung}" "$leader_token")" "$base_url/api/reports/$report_id" >/dev/null
# Erst die aktuelle Berichtsrevision darf wieder an die Wehrführung übergeben werden.
curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" --header 'Content-Type: application/json' --request POST --data "$(report_data '{}')" \
  "$base_url/api/reports/$report_id/submit-to-command" >/dev/null

# Auch die alte Wehrführungsrückgabe scheitert nach einem vollständigen ABA-Zyklus.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request POST --data "$stale_command_return" "$base_url/api/reports/$report_id/return-to-unit")" = 409
# Weder alte Gesamtstände noch alte Quellen mit einer nachgeladenen Gesamtstandsrevision dürfen konsolidieren.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data "$before_return_consolidation" "$base_url/api/incidents/$incident_id/consolidation")" = 409
mixed_consolidation=$(consolidation_data 'Veraltete Quellen' | OLD="$before_return_consolidation" php -r '
  $current=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
  $old=json_decode(getenv("OLD"),true,512,JSON_THROW_ON_ERROR);
  $current["reportVersions"]=$old["reportVersions"];
  echo json_encode($current,JSON_THROW_ON_ERROR);
')
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data "$mixed_consolidation" "$base_url/api/incidents/$incident_id/consolidation")" = 409
assert_consolidated_visibility "$incident_id"

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
# Benachrichtigungen werden erst nach einer erfolgreichen revisionierten Übergabe versendet.
notification_submit_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$(report_data '{}' "$force_token" "$notification_incident_id" "$notification_report_id")" \
  "$base_url/api/reports/$notification_report_id/submit-to-unit")
# Auch die Wehrführungsübergabe verwendet die aktuelle Revision.
notification_command_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$leader_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$(report_data '{}' "$force_token" "$notification_incident_id" "$notification_report_id")" \
  "$base_url/api/reports/$notification_report_id/submit-to-command")
# Eine kommentierte Rückgabe mit aktueller Revision benachrichtigt die zuständige Einheitsführung.
notification_return_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' \
  --request POST --data "$(report_data '{"comment":"Rückfrage"}' "$force_token" "$notification_incident_id" "$notification_report_id")" \
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

# Fremde Alarmfahrzeuge werden nur aus einem eindeutigen Fahrzeugstamm derselben Wehr ergänzt.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO vehicles(unit_id,divera_id,name,shortname,fullname) VALUES
    ($second_unit_id,'external-1','LF Nachbareinheit','LF','Löschgruppenfahrzeug'),
    (900,'external-1','Fahrzeug fremder Wehr','FW','Fremdes Fahrzeug')"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/divera" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(count($data["alarms"])===2); assert(count($data["vehicles"])===2); $vehicles=array_column($data["alarms"][0]["vehicles"],null,"id"); assert($vehicles["external-1"]===["id"=>"external-1","name"=>"LF Nachbareinheit","shortname"=>"LF","fullname"=>"Löschgruppenfahrzeug","own"=>false]);'

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
# Die Zusammenfassungsoption akzeptiert nur 0/1 und keine Query-Arrays oder erratenen Wahrheitswerte.
for summary in 'summary%5B%5D=1' 'summary=true' 'summary=2'; do
  test "$(curl --insecure --silent --write-out '|%{http_code}' --cookie "$session_cookie=$force_token" \
    "$base_url/api/units/1/divera?$summary")" = '{"error":"Zusammenfassungsoption ist ungültig"}|400'
done
# Die Zusammenfassungsabfrage liefert weiterhin Alarme und eine native leere Fahrzeugliste.
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

# Ein erneuter Import aktualisiert ergänzte Fahrzeugnamen; mehrdeutige IDs fallen auf die DIVERA-ID zurück.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE vehicles SET name='LF Nachbareinheit neu' WHERE unit_id=$second_unit_id AND divera_id='external-1'"
curl --insecure --silent --fail \
  --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --data '{"id":"alarm-1"}' "$base_url/api/units/1/divera/import" >/dev/null
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT JSON_UNQUOTE(JSON_EXTRACT(vehicles,'\$[1].name')) FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.divera_id='alarm-1' AND iu.unit_id=1")" = "LF Nachbareinheit neu"
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO units(organization_id,name) VALUES(1,'Dritte Einheit'); SET @third_unit=LAST_INSERT_ID();
    INSERT INTO vehicles(unit_id,divera_id,name,shortname,fullname) VALUES(@third_unit,'external-1','Mehrdeutiges Fahrzeug','MF','Mehrdeutiges Fahrzeug')"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/divera" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $vehicles=array_column($data["alarms"][0]["vehicles"],null,"id"); assert($vehicles["external-1"]===["id"=>"external-1","name"=>"external-1","shortname"=>"","fullname"=>"","own"=>false]);'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM units WHERE organization_id=1 AND name='Dritte Einheit'"

# Eine nachträglich importierte Einheitenzuordnung invalidiert einen bestehenden Gesamtbericht.
imported_incident_id=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT id FROM incidents WHERE organization_id=1 AND divera_id='alarm-1'")
before_assignment=$(consolidation_data 'Vor zusätzlicher Einheit' "$imported_incident_id")
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
# Die zusätzliche Zuordnung erhöht die Einsatzrevision genau einmal.
after_assignment=$(consolidation_data 'Nach zusätzlicher Einheit' "$imported_incident_id")
BEFORE="$before_assignment" AFTER="$after_assignment" php -r '
  $before=json_decode(getenv("BEFORE"),true,512,JSON_THROW_ON_ERROR);
  $after=json_decode(getenv("AFTER"),true,512,JSON_THROW_ON_ERROR);
  assert($after["revision"]===$before["revision"]+1);
'
# Der alte Gesamtstand bleibt nach einer zusätzlichen Einheitenzuordnung ungültig, auch bevor deren Bericht existiert.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data "$before_assignment" "$base_url/api/incidents/$imported_incident_id/consolidation")" = 409

# Bereits der erste Bericht friert die Quellen ein; identische Neuimporte lassen seine Revision und den Gesamtstand unverändert.
import_report_payload="${base_report_payload/69\/2026/86\/2026}"
imported_report_id=$(curl --insecure --silent --fail --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --data "$import_report_payload" "$base_url/api/incidents/$imported_incident_id/reports" |
  php -r 'echo json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR)["id"];')
before_import=$(report_data "$import_report_payload" "$force_token" "$imported_incident_id" "$imported_report_id")
before_import_consolidation=$(consolidation_data 'Vor Neuimport' "$imported_incident_id")
BEFORE="$after_assignment" AFTER="$before_import_consolidation" REPORT="$before_import" php -r '
  $before=json_decode(getenv("BEFORE"),true,512,JSON_THROW_ON_ERROR);
  $after=json_decode(getenv("AFTER"),true,512,JSON_THROW_ON_ERROR);
  $report=json_decode(getenv("REPORT"),true,512,JSON_THROW_ON_ERROR);
  assert($report["revision"]===1 && $after["revision"]===$before["revision"]+1);
'
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" --header 'Content-Type: application/json' \
  --data '{"id":"alarm-1"}' "$base_url/api/units/1/divera/import" >/dev/null
after_import=$(report_data "$import_report_payload" "$force_token" "$imported_incident_id" "$imported_report_id")
BEFORE="$before_import" AFTER="$after_import" php -r '
  $before=json_decode(getenv("BEFORE"),true,512,JSON_THROW_ON_ERROR);
  $after=json_decode(getenv("AFTER"),true,512,JSON_THROW_ON_ERROR);
  assert($after["revision"]===$before["revision"]);
'
# Ein identischer Neuimport lässt einen geladenen Editor gültig; erst dessen echte Speicherung widerruft alte Stände.
test "$(consolidation_data 'Vor Neuimport' "$imported_incident_id")" = "$before_import_consolidation"
before_import=$(PAYLOAD="$before_import" php -r '
  $data=json_decode(getenv("PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
  $data->narrative="Tatsächlich bearbeiteter Bericht nach identischem Neuimport";
  echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
')
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --request PUT --data "$before_import" "$base_url/api/reports/$imported_report_id")" = 200
# Die tatsächliche Berichtsspeicherung macht eine zuvor geladene Konsolidierung weiterhin ungültig.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$session_token" \
  --header 'Content-Type: application/json' --request PUT --data "$before_import_consolidation" "$base_url/api/incidents/$imported_incident_id/consolidation")" = 409

# Der Gesamtabgleich lädt jede Quelle einmal, ersetzt Stammdaten und importiert alle Einsätze idempotent.
: > "$divera_log"
sync_response=$(curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync")
printf '%s' "$sync_response" | php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($data["members"]===2); assert($data["qualifications"]===2); assert($data["vehicles"]===2); assert($data["incidentsCreated"]===1); assert($data["incidentsUpdated"]===0); assert($data["incidentsUnchanged"]===1); assert($data["incidentsWithDifferences"]===0); assert($data["assignmentsCreated"]===1);'
# Eine tatsächlich überschriebene Berichtsrevision bleibt auch nach einem identischen Gesamtabgleich ungültig.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --cookie "$session_cookie=$force_token" \
  --header 'Content-Type: application/json' --request PUT --data "$after_import" "$base_url/api/reports/$imported_report_id")" = 409
test "$(grep --count '^GET /api/v2/pull/all$' "$divera_log")" = 1
test "$(grep --count '^GET /api/v2/alarms$' "$divera_log")" = 1
! grep --extended-regexp --quiet '^(POST|PUT|PATCH|DELETE) ' "$divera_log"
curl --insecure --silent --fail --cookie "$session_cookie=$force_token" "$base_url/api/units/1/resources" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); $members=array_column($data["members"],null,"divera_id"); assert(count($members)===4); assert(count($data["vehicles"])===2); assert($members["m1"]["active"]===1 && $members["m1"]["qualifications"]==="AGT"); assert($members["m2"]["active"]===1 && $members["m2"]["qualifications"]==="MA"); assert($members["test-101"]["active"]===0 && $members["test-102"]["active"]===0);'

# Ein identischer Gesamtabgleich lässt vorhandene Einsatz- und Berichtsrevisionen unverändert, ohne Duplikate oder Abweichungen zu melden.
: > "$divera_log"
before_identical_sync=$(consolidation_data 'Identischer Gesamtabgleich' "$imported_incident_id")
curl --insecure --silent --fail \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync" |
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert($data["incidentsCreated"]===0); assert($data["incidentsUpdated"]===0); assert($data["incidentsUnchanged"]===2); assert($data["incidentsWithDifferences"]===0); assert($data["assignmentsCreated"]===0); assert(!isset($data["warning"]));'
test "$(consolidation_data 'Identischer Gesamtabgleich' "$imported_incident_id")" = "$before_identical_sync"
test "$(grep --count '^GET /api/v2/pull/all$' "$divera_log")" = 1
test "$(grep --count '^GET /api/v2/alarms$' "$divera_log")" = 1

# Ein DIVERA-Neuimport entfernt kein zusätzlich im Bericht gespeichertes Fahrzeug.
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT COUNT(*) FROM report_additional_vehicles WHERE report_id=$report_id_int AND vehicle='Zusatzfahrzeug'")" = 1

# Apache kann zwei API-Anfragen gleichzeitig bearbeiten; der lokale PHP-Einzelprozess kann dies nicht.
# Gesamtabgleich mit leerem JSON-Objekt und Berichte mit echter Besatzung warten in beiden Startreihenfolgen ohne Deadlock auf Einsatz-/Mitgliedssperren.
# Die Zuordnung folgt InnoDB-Transaktions- und Sperr-IDs, nicht der Thread-/Schlüsseldarstellung impliziter Insertsperren.
if [[ -n "${TEST_BASE_URL:-}" ]]; then
  REPORT_ID="$imported_report_id" INCIDENT_ID="$imported_incident_id" REPORT_PAYLOAD="$import_report_payload" \
    UNRELATED_INCIDENT_ID="$duplicate_incident_id" FORCE_COOKIE="$session_cookie=$force_token" \
    COMMAND_COOKIE="$session_cookie=$session_token" API_BASE_URL="$base_url" php -r '
    require "support.php";
    $memberId=(int)one("SELECT id FROM members WHERE organization_id=1 AND divera_id=?",["m1"])["id"];
    $creationIncidentId=(int)one("SELECT id FROM incidents WHERE organization_id=1 AND divera_id=?",["alarm-2"])["id"];
    $start=function(string $path, array $payload, string $cookie, string $method): array {
      $process=proc_open(["curl","--insecure","--silent","--show-error","--max-time","20",
        "--write-out","\n%{http_code}","--cookie",$cookie,"--header","Content-Type: application/json",
        "--request",$method,"--data",json_encode($payload ?: new stdClass(),JSON_THROW_ON_ERROR),getenv("API_BASE_URL").$path],
        [0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
      if(!is_resource($process)) throw new RuntimeException("Parallele Anfrage konnte nicht gestartet werden");
      fclose($pipes[0]);
      return ["process"=>$process,"pipes"=>$pipes];
    };
    // Explicit table intention locks reliably identify the owner, unlike converted implicit record locks.
    $ownTransaction=function(): string {
      $lock=one("SELECT l.ENGINE_TRANSACTION_ID AS transaction_id
        FROM performance_schema.data_locks l JOIN performance_schema.threads t ON t.THREAD_ID=l.THREAD_ID
        WHERE t.PROCESSLIST_ID=CONNECTION_ID() AND l.OBJECT_SCHEMA=DATABASE()
          AND l.LOCK_TYPE=? AND l.LOCK_MODE=? AND l.LOCK_STATUS=? LIMIT 1",["TABLE","IX","GRANTED"]);
      if(!$lock) throw new RuntimeException("Explizite Tabellensperre der Testtransaktion fehlt");
      return (string)$lock["transaction_id"];
    };
    $lockWaits=function(string $blockingTransaction): array {
      return query("SELECT w.REQUESTING_ENGINE_TRANSACTION_ID AS requesting_trx,w.BLOCKING_ENGINE_TRANSACTION_ID AS blocking_trx,
        w.BLOCKING_THREAD_ID AS reported_blocking_thread,
        l.ENGINE_LOCK_ID AS requested_lock,l.OBJECT_NAME AS requested_table,l.INDEX_NAME AS requested_index,
        l.LOCK_TYPE AS requested_type,l.LOCK_STATUS AS requested_status,l.LOCK_MODE AS requested_mode,l.LOCK_DATA AS requested_key,
        held.ENGINE_LOCK_ID AS held_lock,held.OBJECT_NAME AS held_table,held.INDEX_NAME AS held_index,
        held.LOCK_TYPE AS held_type,held.LOCK_STATUS AS held_status,held.LOCK_MODE AS held_mode,held.LOCK_DATA AS held_key
        FROM performance_schema.data_lock_waits w
        JOIN performance_schema.data_locks l ON l.ENGINE=w.ENGINE AND l.ENGINE_LOCK_ID=w.REQUESTING_ENGINE_LOCK_ID
          AND l.ENGINE_TRANSACTION_ID=w.REQUESTING_ENGINE_TRANSACTION_ID
        JOIN performance_schema.data_locks held ON held.ENGINE=w.ENGINE AND held.ENGINE_LOCK_ID=w.BLOCKING_ENGINE_LOCK_ID
          AND held.ENGINE_TRANSACTION_ID=w.BLOCKING_ENGINE_TRANSACTION_ID
        WHERE w.BLOCKING_ENGINE_TRANSACTION_ID=? AND l.OBJECT_SCHEMA=DATABASE() AND held.OBJECT_SCHEMA=DATABASE()",
        [$blockingTransaction])->fetchAll();
    };
    $wait=function(string $blockingTransaction, string $table, int $rowId, bool $inserted=false) use ($lockWaits,$ownTransaction): string {
      if($inserted) {
        assert($blockingTransaction===$ownTransaction());
        assert($table==="incidents" && (int)query("SELECT COUNT(*) FROM incidents WHERE id=? AND organization_id=1 AND divera_id=?",
          [$rowId,"alarm-2"])->fetchColumn()===1);
      }
      $deadline=microtime(true)+5;
      $observed=[];
      while(microtime(true)<$deadline) {
        $observed=$lockWaits($blockingTransaction);
        foreach($observed as $waiting) {
          if($waiting["requested_table"]!==$table || $waiting["held_table"]!==$table
            || $waiting["requested_index"]!==$waiting["held_index"]
            || $waiting["requested_type"]!=="RECORD" || $waiting["held_type"]!=="RECORD"
            || $waiting["requested_status"]!=="WAITING" || $waiting["held_status"]!=="GRANTED"
            || !in_array($waiting["held_mode"],$inserted ? ["S","S,REC_NOT_GAP","X","X,REC_NOT_GAP"] : ["X","X,REC_NOT_GAP"],true)) continue;
          // Only this incident key is inserted: duplicate checks may hold S on its delete-marked predecessor.
          if($inserted
            ? (in_array($waiting["held_index"],["PRIMARY","incidents_org_divera"],true)
              && in_array($waiting["requested_mode"],["X","X,REC_NOT_GAP"],true))
            : ($waiting["held_index"]==="PRIMARY" && $waiting["held_key"]===(string)$rowId)) {
            return (string)$waiting["requesting_trx"];
          }
        }
        usleep(50000);
      }
      fwrite(STDERR,"Sperrdiagnose der Testtransaktion $blockingTransaction: ".json_encode($observed,JSON_THROW_ON_ERROR)."\n");
      throw new RuntimeException("Erwartete Wartebeziehung auf $table für Testdatensatz $rowId fehlt");
    };
    $finish=function(array $request, int $expected): array {
      $output=stream_get_contents($request["pipes"][1]);
      $error=stream_get_contents($request["pipes"][2]);
      fclose($request["pipes"][1]);
      fclose($request["pipes"][2]);
      $exit=proc_close($request["process"]);
      if($exit!==0 || substr($output,-3)!==(string)$expected) {
        throw new RuntimeException("Parallele Anfrage: erwartet HTTP $expected, erhalten ".substr($output,-3).", curl=$exit $error");
      }
      return json_decode(substr($output,0,-4),true,512,JSON_THROW_ON_ERROR);
    };
    // Ohne Quellenänderung gelingen beide Startreihenfolgen; nur der echte Berichtsschreibzugriff erhöht Revisionen.
    foreach(["save","create"] as $action) foreach(["report","sync"] as $first) {
      $incidentId=$action==="save" ? (int)getenv("INCIDENT_ID") : $creationIncidentId;
      $reportId=(int)getenv("REPORT_ID");
      $before=one("SELECT narrative,revision FROM reports WHERE id=?",[$reportId]);
      $payload=(array)json_decode(getenv("REPORT_PAYLOAD"),false,512,JSON_THROW_ON_ERROR);
      $payload["narrative"]="Parallel geprüft: $action/$first";
      $payload["crew"]=[["memberId"=>$memberId,"vehicle"=>"","role"=>"besatzung"]];
      if($action==="save") {
        $payload["revision"]=(int)$before["revision"];
        $path="/api/reports/$reportId";
      } else {
        $payload["runningNumber"]="87/2026";
        $payload["departedAt"]=$payload["arrivedAt"]=null;
        $payload["endedAt"]="2026-08-22T21:00:00.000Z";
        $path="/api/incidents/$incidentId/reports";
      }
      $requests=[];
      db()->beginTransaction();
      query("SELECT id FROM members WHERE id=? FOR UPDATE",[$memberId]);
      $blockingTransaction=$ownTransaction();
      try {
        $reportRequest=fn()=>$start($path,$payload,getenv("FORCE_COOKIE"),$action==="save" ? "PUT" : "POST");
        $syncRequest=fn()=>$start("/api/units/1/divera/sync",[],getenv("COMMAND_COOKIE"),"POST");
        $requests[$first]=$first==="report" ? $reportRequest() : $syncRequest();
        $firstTransaction=$wait($blockingTransaction,"members",$memberId);
        $second=$first==="report" ? "sync" : "report";
        $requests[$second]=$second==="report" ? $reportRequest() : $syncRequest();
        $wait($firstTransaction,"incidents",$incidentId);
        db()->commit();
        $expected=$action==="create" ? 201 : 200;
        $saved=$finish($requests["report"],$expected);
        unset($requests["report"]);
        $synced=$finish($requests["sync"],200);
        unset($requests["sync"]);
        assert($synced["incidentsUpdated"]===0 && $synced["incidentsCreated"]===0 && $synced["incidentsUnchanged"]===2 && $synced["incidentsWithDifferences"]===0);
        if($action==="create") $reportId=(int)$saved["id"];
        $stored=one("SELECT narrative,revision FROM reports WHERE id=?",[$reportId]);
        $expectedRevision=$action==="create" ? 1 : (int)$before["revision"]+1;
        assert($stored["narrative"]===$payload["narrative"] && (int)$stored["revision"]===$expectedRevision);
        assert((int)query("SELECT COUNT(*) FROM report_crew WHERE report_id=? AND member_id=? AND vehicle=? AND role=?",
          [$reportId,$memberId,"","besatzung"])->fetchColumn()===1);
        if($action==="create") query("DELETE FROM reports WHERE id=? AND incident_id=?",[$reportId,$incidentId]);
      } finally {
        if(db()->inTransaction()) db()->rollBack();
        foreach($requests as $request) {
          if(is_resource($request["process"])) proc_terminate($request["process"]);
          foreach($request["pipes"] as $pipe) if(is_resource($pipe)) fclose($pipe);
          if(is_resource($request["process"])) proc_close($request["process"]);
        }
      }
    }

    // Ein gleichzeitig angelegter Alarm muss vor Mitgliedern gesperrt werden, auch wenn er in einer Bestandsabfrage noch fehlt.
    assert((int)query("SELECT COUNT(*) FROM reports WHERE incident_id=?",[$creationIncidentId])->fetchColumn()===0);
    query("DELETE FROM incidents WHERE id=? AND organization_id=1",[$creationIncidentId]);
    db()->beginTransaction();
    query("INSERT INTO incidents(organization_id,divera_id,title,started_at,message,remark,patient,caller,consolidated_text)
      VALUES(1,?,?,?,?,?,?,?,?)",["alarm-2","Paralleler Import","2026-08-22T19:00:00.000Z","","","","",""]);
    $createdIncidentId=(int)db()->lastInsertId();
    query("INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,1,?)",[$createdIncidentId,"[]"]);
    $blockingTransaction=$ownTransaction();
    $requests=[];
    try {
      $requests["sync"]=$start("/api/units/1/divera/sync",[],getenv("COMMAND_COOKIE"),"POST");
      $wait($blockingTransaction,"incidents",$createdIncidentId,true);
      $payload["runningNumber"]="88/2026";
      $payload["narrative"]="Bericht während paralleler Alarmanlage";
      unset($payload["revision"]);
      $unrelatedIncidentId=(int)getenv("UNRELATED_INCIDENT_ID");
      $requests["report"]=$start("/api/incidents/$unrelatedIncidentId/reports",$payload,getenv("FORCE_COOKIE"),"POST");
      $created=$finish($requests["report"],201);
      unset($requests["report"]);
      $wait($blockingTransaction,"incidents",$createdIncidentId,true);
      db()->commit();
      $synced=$finish($requests["sync"],200);
      unset($requests["sync"]);
      assert($synced["incidentsUpdated"]===1 && $synced["incidentsCreated"]===0 && $synced["incidentsUnchanged"]===1 && $synced["incidentsWithDifferences"]===0);
      assert((int)query("SELECT COUNT(*) FROM report_crew WHERE report_id=? AND member_id=?",[$created["id"],$memberId])->fetchColumn()===1);
      query("DELETE FROM reports WHERE id=? AND incident_id=?",[$created["id"],$unrelatedIncidentId]);
    } finally {
      if(db()->inTransaction()) db()->rollBack();
      foreach($requests as $request) {
        if(is_resource($request["process"])) proc_terminate($request["process"]);
        foreach($request["pipes"] as $pipe) if(is_resource($pipe)) fclose($pipe);
        if(is_resource($request["process"])) proc_close($request["process"]);
      }
    }
  '
fi

# Fehlerhafte Stammdaten rollen auch eine zuvor wirklich geänderte, noch nicht historisierte Alarmquelle zurück.
before_failed_sync=$(consolidation_data 'Unverändert' "$imported_incident_id")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE units SET divera_access_key='malformed' WHERE id=1;
    UPDATE incidents SET title='Vor fehlerhaftem Abgleich' WHERE organization_id=1 AND divera_id='alarm-2'"
before_failed_alarm=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(title,'|',revision,'|',report_data_frozen) FROM incidents WHERE organization_id=1 AND divera_id='alarm-2'")
test "${before_failed_alarm##*|}" = 0
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$session_token" --header 'Content-Type: application/json' --request POST \
  "$base_url/api/units/1/divera/sync")" = 502
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT((SELECT COUNT(*) FROM vehicles WHERE unit_id=1),'|',(SELECT COUNT(*) FROM member_units WHERE unit_id=1))")" = '2|4'
# Auch die bereits vor den Stammdaten ausgeführten Importe und Revisionserhöhungen werden bei einem Abgleichfehler zurückgerollt.
test "$(consolidation_data 'Unverändert' "$imported_incident_id")" = "$before_failed_sync"
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT CONCAT(title,'|',revision,'|',report_data_frozen) FROM incidents WHERE organization_id=1 AND divera_id='alarm-2'")" = "$before_failed_alarm"

# Nicht mehr gelieferte Mitglieder werden inaktiv, bleiben in historischen Berichten und sind nicht neu auswählbar.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT IGNORE INTO report_crew(report_id,member_id,member_name) SELECT $report_id_int,id,name FROM members WHERE organization_id=1 AND divera_id='m2';
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
  php -r '$data=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR); assert(in_array("Bernd Beispiel",array_column($data[0]["crew"],"name"),true));'

inactive_member_id=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT m.id FROM members m JOIN member_units mu ON mu.member_id=m.id WHERE mu.unit_id=1 AND mu.active=0 AND m.divera_id='m2'")

# Ein bereits zugeordnetes inaktives Mitglied kann auch im selben Bericht nicht manipuliert umgeordnet werden.
inactive_reassignment="${report_without_travel_times/\"crew\":[]/\"crew\":[{\"memberId\":$inactive_member_id,\"vehicle\":\"HLF 20\",\"role\":\"besatzung\"}]}"
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="UPDATE reports SET status='unit_review' WHERE id=$report_id_int"
# Die aktuelle Revision erlaubt keine manipulierte Umordnung eines inaktiven Mitglieds.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie "$session_cookie=$leader_token" --header 'Content-Type: application/json' --request PUT \
  --data "$(report_data "$inactive_reassignment")" "$base_url/api/reports/$report_id")" = 400
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

# Namens- und Zeitgleichstände werden über IDs stabil aufgelöst; Qualifikationen und sämtliche JSON-Felder bleiben deterministisch und nativ.
API_BASE_URL="$base_url" COOKIE="$session_cookie=$session_token" SECOND_UNIT_ID="$second_unit_id" \
  SESSION_COOKIE="$session_cookie" php -r '
  require "support.php";
  $unitId=(int)getenv("SECOND_UNIT_ID");
  $token=str_repeat("c1",32);
  $call=function(string $path, ?string $cookie=null): mixed {
    $args=["curl","--insecure","--silent","--show-error","--fail","--cookie",$cookie ?? getenv("COOKIE"),getenv("API_BASE_URL").$path];
    $process=proc_open($args,[0=>["pipe","r"],1=>["pipe","w"],2=>["pipe","w"]],$pipes);
    fclose($pipes[0]); $body=stream_get_contents($pipes[1]); stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    if(proc_close($process)!==0) throw new RuntimeException("Sortiertest nicht erreichbar");
    return json_decode($body,false,512,JSON_THROW_ON_ERROR);
  };
  $ids=fn($rows)=>array_values(array_map(fn($row)=>$row->id,array_filter($rows,fn($row)=>$row->id>=92001 && $row->id<=92002)));
  transaction(function() use($unitId,$token) {
    foreach([92002,92001] as $id) {
      query("INSERT INTO users(id,organization_id,unit_id,name,email,password_hash,role) VALUES(?,1,1,?,?,?,?)",
        [$id,"API gleicher Name","api-$id@example.test","kein-passwort-hash","fuehrungskraft"]);
      query("INSERT INTO members(id,organization_id,divera_id,name) VALUES(?,1,?,?)",[$id,"api-$id","API gleicher Name"]);
      query("INSERT INTO member_units(member_id,unit_id) VALUES(?,1)",[$id]);
      query("INSERT INTO vehicles(id,unit_id,divera_id,name) VALUES(?,1,?,?)",[$id,"api-$id","API gleicher Name"]);
      query("INSERT INTO qualifications(id,unit_id,divera_id,name,shortname) VALUES(?,1,?,?,?)",[$id,"api-$id","API gleicher Name",$id===92001 ? "Q1" : "Q2"]);
      query("INSERT INTO incidents(id,organization_id,title,started_at,message,remark,patient,caller,consolidated_text) VALUES(?,1,?,?,?,?,?,?,?)",
        [$id,"API gleicher Zeitpunkt","2026-08-22T18:00:00.000Z","","","","",""]);
    }
    query("INSERT INTO qualifications(id,unit_id,divera_id,name,shortname) VALUES(92003,1,?,?,?)",["api-92003","ZZ spätere Qualifikation","Q1"]);
    query("INSERT INTO member_qualifications(member_id,qualification_id) VALUES(92001,92002),(92001,92001),(92001,92003)");
    query("INSERT INTO user_units(user_id,unit_id) VALUES(92001,?),(92001,1),(92002,1)",[$unitId]);
    query("INSERT INTO sessions(token,user_id,expires_at) VALUES(?,92001,UTC_TIMESTAMP()+INTERVAL 1 HOUR)",[hash("sha256",$token)]);
    query("INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(92001,?,JSON_ARRAY(?)),(92001,1,JSON_ARRAY(JSON_OBJECT(?,?,?,?)))",
      [$unitId,"LF","id","opaque-id","name","HLF"]);
    foreach([92002=>$unitId,92001=>1] as $id=>$unit) query(
      "INSERT INTO reports(id,incident_id,unit_id,author_id,author_name,narrative,vehicles,personnel,classification,status,created_at) VALUES(?,92001,?,1,?,?,?,?,?,?,?)",
      [$id,$unit,"Admin","Sortiertest","","","{}","wehr_review","2026-08-22 18:00:00"]);
    query("UPDATE incidents SET report_data_frozen=1 WHERE id=92001");
    foreach([92002,92001] as $id) query(
      "INSERT INTO report_transitions(id,report_id,to_status,actor_id,actor_name,actor_role,comment,created_at) VALUES(?,92001,?,1,?,?,?,?)",
      [$id,"wehr_review","Admin","wehrleitung",(string)$id,"2026-08-22 18:00:00"]);
    query("INSERT INTO report_transitions(id,report_id,to_status,actor_id,actor_name,actor_role,created_at) VALUES(92003,92002,?,1,?,?,?)",
      ["wehr_review","Admin","wehrleitung","2026-08-22 18:00:00"]);
  });
  try {
    $users=$call("/api/users");
    if($ids($users)!==[92001,92002] || $ids($call("/api/system")->users)!==[92001,92002]) throw new RuntimeException("Benutzergleichstand instabil");
    $user=array_values(array_filter($users,fn($row)=>$row->id===92001))[0];
    $expected=[1,$unitId]; sort($expected,SORT_NUMERIC);
    if($user->unit_ids!==$expected || $call("/api/me",getenv("SESSION_COOKIE")."=$token")->unitIds!==$expected) throw new RuntimeException("Einheits-IDs unsortiert");
    $resources=$call("/api/units/1/resources");
    if($ids($resources->members)!==[92001,92002] || $ids($resources->vehicles)!==[92001,92002]) throw new RuntimeException("Ressourcengleichstand instabil");
    $member=array_values(array_filter($resources->members,fn($row)=>$row->id===92001))[0];
    if($member->qualifications!=="Q1, Q2") throw new RuntimeException("Qualifikationsaggregation instabil");
    $incidents=$call("/api/incidents");
    if($ids($incidents)!==[92002,92001]) throw new RuntimeException("Einsatzgleichstand instabil");
    $incident=array_values(array_filter($incidents,fn($row)=>$row->id===92001))[0];
    if(!is_array($incident->assignments) || !$incident->assignments[0]->vehicles[0] instanceof stdClass
      || $incident->assignments[0]->vehicles[0]->id!=="opaque-id" || $incident->assignments[1]->vehicles!==["LF"]) {
      throw new RuntimeException("Fahrzeugsnapshots sind nicht nativ oder wurden umgeschrieben");
    }
    $reports=$call("/api/incidents/92001/reports");
    if($ids($reports)!==[92001,92002] || array_column($reports[0]->history,"comment")!==["92001","92002"]) throw new RuntimeException("Berichtszeitgleichstand instabil");
    if(!$reports[0]->damaged_party instanceof stdClass || get_object_vars($reports[0]->damaged_party)!==[]
      || !$reports[0]->classification instanceof stdClass || $reports[0]->crew!==[]) throw new RuntimeException("Historische Leerwerte sind keine nativen Objekte/Listen");
  } finally {
    query("DELETE FROM incidents WHERE id IN (92001,92002)");
    query("DELETE FROM qualifications WHERE id IN (92001,92002,92003)");
    query("DELETE FROM vehicles WHERE id IN (92001,92002)");
    query("DELETE FROM members WHERE id IN (92001,92002)");
    query("DELETE FROM users WHERE id IN (92001,92002)");
  }
'

# Neu ausgestellte Wiederherstellungslinks verwenden UTC für die 30-Minuten-Gültigkeit und erhalten ihren Token bei sofortiger Wiederholung.
if [[ -z "${TEST_BASE_URL:-}" ]]; then
  php test/fake-smtp.php smtp-cert.pem smtp-key.pem 1 reset-messages.log >>smtp-server.log 2>&1 &
  smtp_pid=$!
  sleep 0.25
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    --header 'Content-Type: application/json' --data '{"email":"admin@example.test"}' \
    "$base_url/api/password-reset/request")" = 202
  wait "$smtp_pid"
  smtp_pid=''
  test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT TIMESTAMPDIFF(SECOND,requested_at,expires_at)=1800 FROM password_resets WHERE user_id=$admin_user_id")" = 1
  issued_reset_hash=$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT token_hash FROM password_resets WHERE user_id=$admin_user_id")
  test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    --header 'Content-Type: application/json' --data '{"email":"admin@example.test"}' \
    "$base_url/api/password-reset/request")" = 202
  test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
    --execute="SELECT COUNT(*) FROM password_resets WHERE user_id=$admin_user_id AND token_hash='$issued_reset_hash'")" = 1
  MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
    --execute="DELETE FROM password_resets WHERE user_id=$admin_user_id"
  rm -f reset-messages.log
fi

# Historische Quellen und Namen bleiben ab dem ersten Bericht stabil; verworfene Abweichungen werden ohne fremde Inhaltskopien gemeldet.
historical_ids=$(FORCE_COOKIE="$session_cookie=$force_token" COMMAND_COOKIE="$session_cookie=$session_token" \
  LEADER_COOKIE="$session_cookie=$leader_token" OTHER_COOKIE="$session_cookie=$other_force_token" \
  SECOND_UNIT_ID="$second_unit_id" API_BASE_URL="$base_url" php -r '
  require "support.php";
  $call=function(string $path, string $method="GET", ?array $payload=null, ?string $cookie=null, int $expected=200): array {
    $context=stream_context_create(["ssl"=>["verify_peer"=>false,"verify_peer_name"=>false],
      "http"=>["method"=>$method,"timeout"=>20,"ignore_errors"=>true,
        "header"=>"Content-Type: application/json\r\nCookie: ".($cookie ?? getenv("FORCE_COOKIE"))."\r\n",
        "content"=>$payload===null ? "" : json_encode($payload ?: new stdClass(),JSON_THROW_ON_ERROR)]]);
    $stream=fopen(getenv("API_BASE_URL").$path,"r",false,$context);
    if(!$stream) throw new RuntimeException("Testanfrage konnte nicht geöffnet werden");
    $body=stream_get_contents($stream);
    $status=(int)explode(" ",stream_get_meta_data($stream)["wrapper_data"][0])[1];
    fclose($stream);
    assert($status===$expected,"$method $path: erwartet $expected, erhalten $status: $body");
    return json_decode($body,true,512,JSON_THROW_ON_ERROR);
  };
  $command=getenv("COMMAND_COOKIE");
  $leader=getenv("LEADER_COOKIE");
  $setKey=fn($key,$unit=1)=>$call("/api/units/$unit/divera","PUT",["accessKey"=>$key],$command);
  $import=fn($unit=1)=>$call("/api/units/$unit/divera/import","POST",["id"=>"historical-89"],$command,201);
  $state=fn($id)=>[
    "incident"=>one("SELECT * FROM incidents WHERE id=? AND organization_id=1",[$id]),
    "assignments"=>query("SELECT * FROM incident_units WHERE incident_id=? ORDER BY unit_id",[$id])->fetchAll(),
    "reports"=>query("SELECT * FROM reports WHERE incident_id=? ORDER BY id",[$id])->fetchAll(),
    "crew"=>query("SELECT rc.* FROM report_crew rc JOIN reports r ON r.id=rc.report_id WHERE r.incident_id=? ORDER BY rc.report_id,rc.member_id",[$id])->fetchAll(),
    "additional"=>query("SELECT av.* FROM report_additional_vehicles av JOIN reports r ON r.id=av.report_id WHERE r.incident_id=? ORDER BY av.report_id,av.vehicle",[$id])->fetchAll(),
    "history"=>query("SELECT rt.* FROM report_transitions rt JOIN reports r ON r.id=rt.report_id WHERE r.incident_id=? ORDER BY rt.id",[$id])->fetchAll()
  ];
  $readReport=fn($id)=>$call("/api/incidents/$id/reports")[0];
  $aggregate=function($id) use($call,$command): array {
    $matches=array_values(array_filter($call("/api/incidents","GET",null,$command),fn($row)=>$row["id"]===$id));
    assert(count($matches)===1);
    return ["revision"=>$matches[0]["revision"],"text"=>"Historischer Gesamtbericht 89",
      "reportVersions"=>array_map(fn($row)=>["id"=>$row["id"],"revision"=>$row["revision"]],$call("/api/incidents/$id/reports","GET",null,$command))];
  };
  $warn=function(array $result, int $id): void {
    assert(str_contains($result["warning"],"Einsatz #$id:"));
    assert(str_contains($result["warning"],"Einsatzdaten") && str_contains($result["warning"],"nicht übernommen"));
    assert(!str_contains(json_encode($result,JSON_THROW_ON_ERROR),"Quellpatient"));
    assert(!str_contains(json_encode($result,JSON_THROW_ON_ERROR),"Quellmelder"));
    assert(!str_contains(json_encode($result,JSON_THROW_ON_ERROR),"historical-"));
  };

  // Vor dem ersten Bericht werden echte Quellen-/Fahrzeugänderungen genau einmal übernommen.
  $setKey("historical-before");
  $id=$import()["id"];
  $before=$state($id);
  assert((int)$before["incident"]["report_data_frozen"]===0);
  $setKey("historical-updated");
  assert(!isset($import()["warning"]));
  $updated=$state($id);
  assert((int)$updated["incident"]["revision"]===(int)$before["incident"]["revision"]+1);
  assert($updated["incident"]["started_at"]==="2026-12-31T22:45:00.000Z" && $updated["incident"]["title"]==="Historischer Einsatz");
  assert(count(json_decode($updated["assignments"][0]["vehicles"],true,512,JSON_THROW_ON_ERROR))===2);
  assert(!isset($import()["warning"]) && $state($id)===$updated);
  $earlyUnit=$call("/api/units","POST",["name"=>"Historisch alarmierte Einheit"],$command,201)["id"];
  $setKey("historical-updated",$earlyUnit);
  $import($earlyUnit);
  $call("/api/units/1/divera/members/sync","POST",[],$command);
  $call("/api/units/1/divera/vehicles/sync","POST",[],$command);
  $anna=(int)one("SELECT id FROM members WHERE organization_id=1 AND divera_id=?",["m1"])["id"];
  $bernd=(int)one("SELECT id FROM members WHERE organization_id=1 AND divera_id=?",["m2"])["id"];
  $payload=["unitId"=>1,"runningNumber"=>"89/Archiv","narrative"=>"Historischer Bericht 89",
    "endedAt"=>"2027-01-01T02:00:00.000Z","incidentType"=>"Technische Hilfe","classification"=>new stdClass(),
    "additionalVehicles"=>["Reserve Historisch"],"crew"=>[["memberId"=>$anna,"vehicle"=>"HLF 20","role"=>"besatzung","name"=>"Manipuliert"]]];
  // Eine erst beim Besatzungsspeichern ungültige Erstanlage hinterlässt weder Bericht noch Freeze-Marker oder Revision.
  $failedPayload=$payload;
  $failedPayload["crew"][0]["memberId"]=900000;
  $beforeFailed=$state($id);
  $call("/api/incidents/$id/reports","POST",$failedPayload,null,400);
  assert($state($id)===$beforeFailed);
  $reportId=$call("/api/incidents/$id/reports","POST",$payload,null,201)["id"];
  $frozen=$state($id);
  assert((int)$frozen["incident"]["report_data_frozen"]===1 && (int)$frozen["reports"][0]["report_year"]===2026);
  assert($frozen["reports"][0]["status"]==="author_draft" && $frozen["reports"][0]["personnel"]==="Anna Beispiel");

  // Dieselbe Nummer ist im Folgejahr belegt; ein verworfener Jahreswechsel darf weder Alarmzeit noch Berichtsjahr verschieben.
  $next=$call("/api/incidents","POST",["title"=>"Jahresnummernvergleich","startedAt"=>"2026-12-31T23:30:00.000Z","unitIds"=>[1]],$command,201)["id"];
  $nextPayload=$payload;
  $nextPayload["crew"]=$nextPayload["additionalVehicles"]=[];
  $call("/api/incidents/$next/reports","POST",$nextPayload,null,201);
  assert($readReport($next)["report_year"]===2027);
  $setKey("historical-after");
  $warning=$import();
  $warn($warning,$id);
  assert(str_contains($warning["warning"],"Fahrzeugliste") && $state($id)===$frozen);
  // Auch die bereits alarmierte Einheit ohne eigenen Bericht behält ab dem allerersten Bericht ihren Snapshot.
  $setKey("historical-after",$earlyUnit);
  $earlyWarning=$import($earlyUnit);
  $warn($earlyWarning,$id);
  assert(str_contains($earlyWarning["warning"],"Fahrzeugliste") && $state($id)===$frozen);
  $payload["revision"]=$readReport($id)["revision"];
  $call("/api/reports/$reportId","PUT",$payload);
  assert($readReport($id)["report_year"]===2026 && $readReport($id)["alarmed_at"]==="2026-12-31T22:45:00.000Z");

  // Konto-/Stammdatenänderungen ändern weder historischen Autor noch bestehende Besatzung, Zusammenfassungen oder Übergangsakteure.
  $force=one("SELECT id,name,email,role FROM users WHERE organization_id=1 AND email=?",["fuehrungskraft@example.test"]);
  $call("/api/users/".$force["id"],"PUT",["name"=>"Führungskraft Heute","email"=>$force["email"],"role"=>$force["role"],"unitIds"=>[1]],$command);
  $setKey("historical-renamed");
  $namesBefore=$state($id);
  $call("/api/units/1/divera/members/sync","POST",[],$command);
  $call("/api/units/1/divera/vehicles/sync","POST",[],$command);
  assert($state($id)===$namesBefore);
  $resources=$call("/api/units/1/resources");
  assert(in_array("Anna Jetzt",array_column($resources["members"],"name"),true));
  $report=$readReport($id);
  assert($report["author_name"]===$force["name"] && $report["personnel"]==="Anna Beispiel");
  assert($report["history"][0]["actor_name"]===$force["name"]);
  $otherIncidents=$call("/api/incidents","GET",null,getenv("OTHER_COOKIE"));
  $other=array_values(array_filter($otherIncidents,fn($row)=>$row["id"]===$id))[0];
  $assignment=$other["assignments"][0];
  assert($assignment["reportAuthorName"]===$force["name"]);

  // Beibehaltene Personen behalten ihre Namen; neu aufgenommene Personen erhalten den aktuellen serverseitigen Namen.
  $payload["revision"]=$report["revision"];
  $payload["crew"][0]["vehicle"]="";
  $payload["crew"][]=["memberId"=>$bernd,"vehicle"=>"","role"=>"besatzung","name"=>"Manipuliert"];
  $call("/api/reports/$reportId","PUT",$payload);
  $report=$readReport($id);
  assert($report["personnel"]==="Anna Beispiel, Bernd Jetzt");
  assert(array_column($report["crew"],"name")===["Anna Beispiel","Bernd Jetzt"]);
  query("UPDATE members SET name=? WHERE id=? AND organization_id=1",["Bernd Später",$bernd]);
  $payload["revision"]=$report["revision"];
  $call("/api/reports/$reportId","PUT",$payload);
  assert($readReport($id)["personnel"]==="Anna Beispiel, Bernd Jetzt");
  $crew=$payload["crew"];
  $payload["crew"]=[$crew[0]];
  $payload["revision"]=$readReport($id)["revision"];
  $call("/api/reports/$reportId","PUT",$payload);
  $payload["crew"]=$crew;
  $payload["revision"]=$readReport($id)["revision"];
  $call("/api/reports/$reportId","PUT",$payload);
  assert($readReport($id)["personnel"]==="Anna Beispiel, Bernd Später");
  $call("/api/reports/$reportId/submit-to-unit","POST",["revision"=>$readReport($id)["revision"]]);
  $call("/api/reports/$reportId/submit-to-command","POST",["revision"=>$readReport($id)["revision"]],$leader);
  $earlyPayload=$nextPayload;
  $earlyPayload["unitId"]=$earlyUnit;
  $call("/api/incidents/$id/reports","POST",$earlyPayload,$command,201);
  $call("/api/incidents/$id/consolidation","PUT",$aggregate($id),$command);
  $completed=$state($id);
  assert($completed["incident"]["consolidated_at"]!==null);
  assert($completed["history"][0]["actor_name"]===$force["name"] && $completed["history"][1]["actor_name"]==="Führungskraft Heute");

  // Identische oder nur umsortierte Fahrzeugquellen bewahren Abschlüsse und alle Revisionen auch beim vollständigen Abgleich.
  $setKey("historical-reordered");
  assert(!isset($import()["warning"]) && $state($id)===$completed);
  $synced=$call("/api/units/1/divera/sync","POST",[],$command);
  assert($synced["incidentsUpdated"]===0 && $synced["incidentsUnchanged"]===1 && $synced["incidentsWithDifferences"]===0);
  assert(!isset($synced["warning"]) && $state($id)===$completed);
  $statistics=$call("/api/statistics?from=2026-12-31&to=2026-12-31","GET",null,$leader);
  assert(in_array("Anna Beispiel",array_column($statistics["members"],"name"),true));
  assert(in_array("Bernd Später",array_column($statistics["members"],"name"),true));

  // Abweichender Vollimport eines abgeschlossenen Einsatzes meldet nur Kategorien und erhält auch Besatzung, Zusatzfahrzeuge und Übergänge.
  $setKey("historical-after");
  $loaded=$aggregate($id);
  $synced=$call("/api/units/1/divera/sync","POST",[],$command);
  $warn($synced,$id);
  assert($synced["incidentsUpdated"]===0 && $synced["incidentsUnchanged"]===1 && $synced["incidentsWithDifferences"]===1);
  assert($state($id)===$completed);
  $call("/api/incidents/$id/consolidation","PUT",$loaded,$command);
  $completed=$state($id);

  // Eine neue Einheit erhält ihren eigenen Snapshot trotz Abweichung; nur der Gesamtstand wird ungültig, bestehende Berichte bleiben gleich.
  $loaded=$aggregate($id);
  $second=(int)getenv("SECOND_UNIT_ID");
  $setKey("historical-after",$second);
  // Neue Zuordnungen warnen zugleich vor verworfenen Quelldaten und einem fehlgeschlagenen Mailversand.
  $mailRecipient=function(int $unit): int {
    query("INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(1,?,?,?,?,?)",
      [$unit,"Historienprüfung","historie-$unit@example.test","unbenutzbar","einheitsleitung"]);
    $recipient=(int)db()->lastInsertId();
    query("INSERT INTO user_units(user_id,unit_id) VALUES(?,?)",[$recipient,$unit]);
    return $recipient;
  };
  $recipient=$mailRecipient($second);
  $assignmentWarning=$import($second);
  $warn($assignmentWarning,$id);
  assert(str_contains($assignmentWarning["warning"],"Benachrichtigungs-E-Mails"));
  query("DELETE FROM users WHERE id=?",[$recipient]);
  $assigned=$state($id);
  assert((int)$assigned["incident"]["revision"]===(int)$completed["incident"]["revision"]+1);
  assert($assigned["incident"]["consolidated_at"]===null && $assigned["incident"]["consolidated_text"]===$completed["incident"]["consolidated_text"]);
  foreach(["reports","crew","additional","history"] as $part) assert($assigned[$part]===$completed[$part]);
  assert(count($assigned["assignments"])===3 && $assigned["assignments"][0]===$completed["assignments"][0]);
  assert($assigned["assignments"][2]===$completed["assignments"][1]);
  assert(array_column(json_decode($assigned["assignments"][1]["vehicles"],true,512,JSON_THROW_ON_ERROR),"id")===["v2"]);
  $call("/api/incidents/$id/consolidation","PUT",$loaded,$command,409);
  $nextPayload["unitId"]=$second;
  $secondReport=$call("/api/incidents/$id/reports","POST",$nextPayload,$command,201)["id"];
  $secondStored=one("SELECT alarmed_at,report_year FROM reports WHERE id=?",[$secondReport]);
  assert((int)$secondStored["report_year"]===2026 && $secondStored["alarmed_at"]==="2026-12-31T22:45:00.000Z");
  $call("/api/incidents/$id/consolidation","PUT",$aggregate($id),$command);

  // Auch der Vollabgleich kombiniert beide Warnungen; eine neue Einheit zählt als geändert und invalidiert nur den Gesamtabschluss.
  $completed=$state($id);
  $mailUnit=$call("/api/units","POST",["name"=>"Nachalarmierte Historieneinheit"],$command,201)["id"];
  $setKey("historical-after",$mailUnit);
  $recipient=$mailRecipient($mailUnit);
  $synced=$call("/api/units/$mailUnit/divera/sync","POST",[],$command);
  $warn($synced,$id);
  assert(str_contains($synced["warning"],"Benachrichtigungs-E-Mails"));
  assert($synced["incidentsUpdated"]===1 && $synced["incidentsUnchanged"]===0
    && $synced["incidentsWithDifferences"]===1 && $synced["assignmentsCreated"]===1);
  $assigned=$state($id);
  assert((int)$assigned["incident"]["revision"]===(int)$completed["incident"]["revision"]+1);
  assert($assigned["incident"]["consolidated_at"]===null);
  foreach(["reports","crew","additional","history"] as $part) assert($assigned[$part]===$completed[$part]);
  query("DELETE FROM users WHERE id=?",[$recipient]);
  $nextPayload["unitId"]=$mailUnit;
  $call("/api/incidents/$id/reports","POST",$nextPayload,$command,201);
  $call("/api/incidents/$id/consolidation","PUT",$aggregate($id),$command);
  echo "$id|$reportId";
')
IFS='|' read -r historical_incident_id historical_report_id <<< "$historical_ids"
# Einzel- und Gesamt-PDFs verwenden historische Autor-/Besatzungs-/Fahrzeugnamen und niemals verworfene DIVERA-Inhalte.
assert_pdf "$session_token" "/api/reports/$historical_report_id/pdf" 'Historischer Bericht 89|Führungskraft Test|Anna Beispiel|Bernd Später|HLF 20|Reserve Historisch' 'Quellpatient'
assert_pdf "$session_token" "/api/incidents/$historical_incident_id/consolidation/pdf" 'Historischer Gesamtbericht 89|Historischer Einsatz|Anna Beispiel|Bernd Später|Reserve Historisch' 'Quellpatient'

# Passwort-Wiederherstellung verrät keine Konten und begrenzt neue Token anhand der UTC-Anforderungszeit.
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"email":"nicht-registriert@example.test"}' \
  "$base_url/api/password-reset/request")" = 202
rate_limit_hash=$(php -r "echo hash('sha256', 'rate-limit');")
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM password_resets WHERE user_id=(SELECT id FROM users WHERE email='admin@example.test');
    INSERT INTO password_resets(user_id,token_hash,requested_at,expires_at) SELECT id,'$rate_limit_hash',UTC_TIMESTAMP(),UTC_TIMESTAMP()+INTERVAL 30 MINUTE FROM users WHERE email='admin@example.test'"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"email":"admin@example.test"}' \
  "$base_url/api/password-reset/request")" = 202
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" --batch --skip-column-names \
  einsatzberichte --execute="SELECT COUNT(*) FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE u.email='admin@example.test'")" = 1
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM password_resets WHERE user_id=(SELECT id FROM users WHERE email='admin@example.test')"

# Abgelaufene Reset-Tokens geben keinen Zugriff auf den Wiederherstellungskontext.
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

# Reset-Anforderungen entfernen abgelaufene Token anderer Konten, erhalten gültige Links und verraten auch bei unbekannten Adressen keine Konten.
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --default-character-set=utf8mb4 --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="INSERT INTO password_resets(user_id,token_hash,expires_at) SELECT id,'$reset_hash',UTC_TIMESTAMP()+INTERVAL 30 MINUTE FROM users WHERE email='fuehrungskraft@example.test'"
test "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data '{"email":"nicht-registriert@example.test"}' \
  "$base_url/api/password-reset/request")" = 202
test "$(MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" --batch --skip-column-names einsatzberichte \
  --execute="SELECT CONCAT((SELECT COUNT(*) FROM password_resets WHERE token_hash='$expired_hash'),'|',(SELECT COUNT(*) FROM password_resets WHERE token_hash='$reset_hash'))")" = '0|1'
MYSQL_PWD="$DB_PASSWORD" mysql "${mysql_tls_args[@]}" --host="$db_host" --user="$DB_USER" einsatzberichte \
  --execute="DELETE FROM password_resets WHERE token_hash='$reset_hash'"

# Unbekannte Token werden abgelehnt; ein gültiger Link ist einmalig und beendet bestehende Sitzungen.
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

#!/usr/bin/env bash
set -euo pipefail

project="democheck-$$"
compose=(docker compose -p "$project")
mysql=("${compose[@]}" exec -T db mysql --user=root --password=test-password --database=einsatzberichte --batch --skip-column-names)
trap '"${compose[@]}" --profile demo down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT
export HTTP_PORT=0 HTTPS_PORT=0
export DIVERA_API_BASE_URL=http://divera:8090

"${compose[@]}" --profile demo up --build --detach --wait divera web
[[ "$("${mysql[@]}" --execute='SELECT COUNT(*) FROM organizations')" == 0 ]]

"${mysql[@]}" --execute="
  INSERT INTO organizations(name) VALUES('Freiwillige Feuerwehr Amt Keppel');
  SET @real_org=LAST_INSERT_ID();
  INSERT INTO users(organization_id,unit_id,name,email,password_hash,role)
  VALUES(@real_org,NULL,'Nicht-Demo-Wehrführung','real@example.test','unbenutzbar','wehrleitung');"

"${compose[@]}" --profile demo run --rm demo-seed
"${compose[@]}" --profile demo run --rm demo-seed

[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM users WHERE email='real@example.test'")" == 1 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM organizations WHERE name='Freiwillige Feuerwehr Amt Keppel'")" == 2 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM users WHERE email='wehrleitung@demo.local'")" == 1 ]]

demo_org_id=$("${mysql[@]}" --execute="SELECT organization_id FROM users WHERE email='wehrleitung@demo.local'")
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM units WHERE organization_id=$demo_org_id AND divera_access_key LIKE 'demo-local-%'")" == 3 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incidents WHERE organization_id=$demo_org_id AND (divera_id LIKE 'demo-flow-%' OR title LIKE '%Demo%' OR remark LIKE '%Demo%' OR title LIKE '%Fake%' OR remark LIKE '%Fake%')")" == 0 ]]
[[ "$("${mysql[@]}" --execute="SELECT GROUP_CONCAT(CONCAT(u.email,':',u.role,':',(SELECT COUNT(*) FROM user_units uu WHERE uu.user_id=u.id)) ORDER BY u.email SEPARATOR '|') FROM users u WHERE u.organization_id=$demo_org_id AND u.email IN ('wehrleitung@demo.local','leitung.mitte@demo.local','leitung.nord@demo.local','fuehrung.mitte@demo.local','fuehrung.nord@demo.local','fuehrung.springer@demo.local')")" == 'fuehrung.mitte@demo.local:fuehrungskraft:1|fuehrung.nord@demo.local:fuehrungskraft:1|fuehrung.springer@demo.local:fuehrungskraft:2|leitung.mitte@demo.local:einheitsleitung:1|leitung.nord@demo.local:einheitsleitung:1|wehrleitung@demo.local:wehrleitung:0' ]]

"${compose[@]}" exec -T web php -r '
  require "constants.php";
  require "support.php";
  foreach (query("SELECT r.incident_type,r.classification FROM reports r JOIN incidents i ON i.id=r.incident_id JOIN users u ON u.organization_id=i.organization_id WHERE u.email=? GROUP BY r.id", ["wehrleitung@demo.local"])->fetchAll() as $report) {
      if (!in_array($report["incident_type"], INCIDENT_TYPES, true)) exit(1);
      foreach (json_decode($report["classification"], true, 512, JSON_THROW_ON_ERROR) as $group => $values) {
          foreach ($values as $value) if (!in_array($value, CLASSIFICATIONS[$group] ?? [], true)) exit(1);
      }
  }'

for email in wehrleitung leitung.mitte leitung.nord fuehrung.mitte fuehrung.nord fuehrung.springer; do
  [[ "$("${compose[@]}" exec -T web curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    --header 'Content-Type: application/json' --data "{\"email\":\"$email@demo.local\",\"password\":\"Demo-Feuerwehr-2026!\"}" \
    https://localhost/api/login)" == 200 ]]
done

# Fake-DIVERA weist schreibende externe Aufrufe auch im Demo-Profil zurück.
[[ "$("${compose[@]}" exec -T web curl --silent --output /dev/null --write-out '%{http_code}' --request POST \
  'http://divera:8090/api/v2/alarms?accesskey=demo-local-mitte')" == 405 ]]

# Wehrführung kann alle drei vorkonfigurierten Demo-Einheiten gegen den lokalen Fake synchronisieren.
[[ "$("${compose[@]}" exec -T web curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie-jar /tmp/wehr-demo-cookie --header 'Content-Type: application/json' \
  --data '{"email":"wehrleitung@demo.local","password":"Demo-Feuerwehr-2026!"}' \
  https://localhost/api/login)" == 200 ]]
mitte_id=$("${mysql[@]}" --execute="SELECT id FROM units WHERE organization_id=$demo_org_id AND divera_access_key='demo-local-mitte'")
mapfile -t demo_unit_ids < <("${mysql[@]}" --execute="SELECT id FROM units WHERE organization_id=$demo_org_id ORDER BY name")
for unit_id in "${demo_unit_ids[@]}"; do
  "${compose[@]}" exec -T web curl --insecure --silent --fail --cookie /tmp/wehr-demo-cookie \
    "https://localhost/api/units/$unit_id/divera?summary=1" >/dev/null
done

# Einzelimport und zweimalige Gesamtsynchronisation bleiben ohne Bestandsverlust oder Duplikate.
"${compose[@]}" exec -T web curl --insecure --silent --fail --cookie /tmp/wehr-demo-cookie \
  --header 'Content-Type: application/json' --data '{"id":"demo-live-mitte"}' \
  "https://localhost/api/units/$mitte_id/divera/import" >/dev/null
for round in 1 2; do
  for unit_id in "${demo_unit_ids[@]}"; do
    "${compose[@]}" exec -T web curl --insecure --silent --fail --cookie /tmp/wehr-demo-cookie \
      --header 'Content-Type: application/json' --data '{}' \
      "https://localhost/api/units/$unit_id/divera/sync" >/dev/null
  done
done
[[ "$("${mysql[@]}" --execute="SELECT GROUP_CONCAT(CONCAT((SELECT COUNT(*) FROM member_units mu WHERE mu.unit_id=u.id),':',(SELECT COUNT(*) FROM qualifications q WHERE q.unit_id=u.id),':',(SELECT COUNT(*) FROM vehicles v WHERE v.unit_id=u.id)) ORDER BY u.divera_access_key SEPARATOR '|') FROM units u WHERE u.organization_id=$demo_org_id")" == '8:4:3|8:4:2|8:4:3' ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incidents WHERE organization_id=$demo_org_id AND divera_id LIKE 'demo-live-%'")" == 4 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id LIKE 'demo-live-%'")" == 5 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id='demo-live-shared'")" == 2 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incidents WHERE organization_id=$demo_org_id AND (title LIKE '%Demo%' OR remark LIKE '%Demo%' OR title LIKE '%Fake%' OR remark LIKE '%Fake%')")" == 0 ]]

[[ "$("${compose[@]}" exec -T web curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
  --cookie-jar /tmp/daniel-demo-cookie --header 'Content-Type: application/json' \
  --data '{"email":"fuehrung.springer@demo.local","password":"Demo-Feuerwehr-2026!"}' \
  https://localhost/api/login)" == 200 ]]
"${compose[@]}" exec -T web curl --insecure --silent --fail --cookie /tmp/daniel-demo-cookie https://localhost/api/incidents |
  "${compose[@]}" exec -T web php -r '
    $incidents=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
    $single=array_values(array_filter($incidents,fn($item)=>$item["foreign_id"]==="D-2026-015"))[0];
    $singleAssignments=json_decode($single["assignments"],true,512,JSON_THROW_ON_ERROR);
    assert(array_column($singleAssignments,"reportAuthorName")===["Franziska Roth"]);
    $multi=array_values(array_filter($incidents,fn($item)=>$item["foreign_id"]==="D-2026-005"))[0];
    $visibleAuthors=array_values(array_filter(array_column(json_decode($multi["assignments"],true,512,JSON_THROW_ON_ERROR),"reportAuthorName")));
    assert($visibleAuthors===["Nils Weber"]);
    foreach (["D-2026-012","D-2026-014"] as $number) {
      $incident=array_values(array_filter($incidents,fn($item)=>$item["foreign_id"]===$number))[0];
      assert($incident["reportStatus"]["key"]==="report_exists");
    }
  '
demo_015_id=$("${mysql[@]}" --execute="SELECT id FROM incidents WHERE foreign_id='D-2026-015'")
[[ "$("${compose[@]}" exec -T web curl --insecure --silent --fail --cookie /tmp/daniel-demo-cookie \
  "https://localhost/api/incidents/$demo_015_id/reports")" == '[]' ]]

#!/usr/bin/env bash
set -euo pipefail

project="democheck-$$"
compose=(docker compose -p "$project")
mysql=("${compose[@]}" exec -T db mysql --user=root --password=test-password --database=einsatzberichte --batch --skip-column-names)
trap '"${compose[@]}" --profile demo down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT
export HTTP_PORT=0 HTTPS_PORT=0

"${compose[@]}" up --build --detach --wait web
[[ "$("${mysql[@]}" --execute='SELECT COUNT(*) FROM organizations')" == 0 ]]

"${mysql[@]}" --execute="
  INSERT INTO organizations(name) VALUES('Freiwillige Feuerwehr Musterstadt');
  SET @real_org=LAST_INSERT_ID();
  INSERT INTO users(organization_id,unit_id,name,email,password_hash,role)
  VALUES(@real_org,NULL,'Nicht-Demo-Wehrführung','real@example.test','unbenutzbar','wehrleitung');"

"${compose[@]}" --profile demo run --rm demo-seed
"${compose[@]}" --profile demo run --rm demo-seed

[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM users WHERE email='real@example.test'")" == 1 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM organizations WHERE name='Freiwillige Feuerwehr Musterstadt'")" == 2 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM users WHERE email='wehrleitung@demo.local'")" == 1 ]]

demo_org_id=$("${mysql[@]}" --execute="SELECT organization_id FROM users WHERE email='wehrleitung@demo.local'")
[[ "$("${mysql[@]}" --execute="SELECT GROUP_CONCAT(CONCAT(divera_id,':',amount) ORDER BY divera_id SEPARATOR '|') FROM (SELECT divera_id,COUNT(*) amount FROM incidents WHERE organization_id=$demo_org_id AND divera_id IN ('demo-flow-single','demo-flow-multi') GROUP BY divera_id) flow")" == 'demo-flow-multi:1|demo-flow-single:1' ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id='demo-flow-single'")" == 1 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id='demo-flow-multi'")" == 2 ]]
[[ "$("${mysql[@]}" --execute="SELECT GROUP_CONCAT(CONCAT(i.divera_id,':',u.email) ORDER BY i.divera_id,u.email SEPARATOR '|') FROM incidents i JOIN incident_units iu ON iu.incident_id=i.id JOIN user_units uu ON uu.unit_id=iu.unit_id JOIN users u ON u.id=uu.user_id WHERE i.organization_id=$demo_org_id AND i.divera_id IN ('demo-flow-single','demo-flow-multi') AND u.email IN ('fuehrung.mitte@demo.local','fuehrung.nord@demo.local')")" == 'demo-flow-multi:fuehrung.mitte@demo.local|demo-flow-multi:fuehrung.nord@demo.local|demo-flow-single:fuehrung.mitte@demo.local' ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id IN ('demo-flow-single','demo-flow-multi') AND JSON_LENGTH(iu.vehicles)>0")" == 3 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id IN ('demo-flow-single','demo-flow-multi')")" == 0 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM report_transitions rt JOIN reports r ON r.id=rt.report_id JOIN incidents i ON i.id=r.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id IN ('demo-flow-single','demo-flow-multi')")" == 0 ]]
[[ "$("${mysql[@]}" --execute="SELECT COUNT(*) FROM incidents WHERE organization_id=$demo_org_id AND divera_id IN ('demo-flow-single','demo-flow-multi') AND (consolidated_at IS NOT NULL OR consolidated_text<>'')")" == 0 ]]
[[ "$("${mysql[@]}" --execute="SELECT GROUP_CONCAT(CONCAT((SELECT COUNT(*) FROM members m JOIN member_units mu ON mu.member_id=m.id WHERE mu.unit_id=u.id),':',(SELECT COUNT(*) FROM qualifications q WHERE q.unit_id=u.id),':',(SELECT COUNT(*) FROM vehicles v WHERE v.unit_id=u.id)) ORDER BY (SELECT COUNT(*) FROM vehicles v WHERE v.unit_id=u.id) SEPARATOR '|') FROM units u WHERE u.id IN (SELECT DISTINCT iu.unit_id FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.organization_id=$demo_org_id AND i.divera_id IN ('demo-flow-single','demo-flow-multi'))")" == '8:4:2|8:4:3' ]]
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

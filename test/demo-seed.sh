#!/usr/bin/env bash
set -euo pipefail

compose=(docker compose)
mysql=("${compose[@]}" exec -T db mysql --user=root --password=test-password --database=einsatzberichte --batch --skip-column-names)

"${compose[@]}" --profile demo down --volumes
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

"${compose[@]}" exec -T web php -r '
  require "constants.php";
  require "support.php";
  foreach (query("SELECT r.incident_type,r.classification FROM reports r JOIN incidents i ON i.id=r.incident_id JOIN users u ON u.organization_id=i.organization_id WHERE u.email=? GROUP BY r.id", ["wehrleitung@demo.local"])->fetchAll() as $report) {
      if (!in_array($report["incident_type"], INCIDENT_TYPES, true)) exit(1);
      foreach (json_decode($report["classification"], true, 512, JSON_THROW_ON_ERROR) as $group => $values) {
          foreach ($values as $value) if (!in_array($value, CLASSIFICATIONS[$group] ?? [], true)) exit(1);
      }
  }'

[[ "$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --header 'Content-Type: application/json' \
  --data '{"email":"wehrleitung@demo.local","password":"Demo-Feuerwehr-2026!"}' https://localhost:8443/api/login)" == 200 ]]

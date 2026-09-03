#!/usr/bin/env bash
set -euo pipefail

project="migrationcheck-$$"
compose=(docker compose -p "$project")
migration_name="999-test-$project.sql"
migration_file="migrations/$migration_name"
trap 'rm -f "$migration_file"; "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT

printf 'CREATE TABLE migration_test (id INT PRIMARY KEY);\n' > "$migration_file"
"${compose[@]}" up --detach --wait db
# The temporary init server only accepts socket connections, so TCP identifies the final server.
for _ in {1..60}; do
  if "${compose[@]}" exec -T db mysql --host=127.0.0.1 --user=root -ptest-password einsatzberichte --execute="SELECT 1" >/dev/null 2>&1; then break; fi
  sleep 1
done
"${compose[@]}" exec -T db mysql --host=127.0.0.1 --user=root -ptest-password einsatzberichte --execute="SELECT 1" >/dev/null

# Eine Installation vor den Migrationen erhält Workflow, Stammdaten, Aktivstatus und zusätzliche Berichtsfahrzeuge genau einmal.
"${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte --execute="
  DROP TABLE report_additional_vehicles;
  DELETE FROM schema_migrations WHERE name='003-report-additional-vehicles.sql';
  ALTER TABLE member_units DROP COLUMN active;
  DELETE FROM schema_migrations WHERE name='002-inactive-unit-members.sql';
  DROP TABLE report_transitions;
  DROP TABLE vehicles;
  DELETE FROM schema_migrations WHERE name='001-report-workflow-and-vehicles.sql';
  ALTER TABLE reports MODIFY status ENUM('draft','released') NOT NULL DEFAULT 'draft';
  INSERT INTO organizations(id,name) VALUES(10,'Migrationstest'),(11,'Fremdmandant');
  INSERT INTO units(id,organization_id,name) VALUES(10,10,'Einheit');
  INSERT INTO users(id,organization_id,unit_id,name,email,password_hash,role) VALUES
    (10,10,10,'Führungskraft','migration-force@example.test','x','fuehrungskraft'),
    (11,10,10,'Einheitsführung','migration-unit@example.test','x','einheitsleitung'),
    (12,10,NULL,'Wehrführung','migration-command@example.test','x','wehrleitung');
  INSERT INTO incidents(id,organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text) VALUES
    (10,10,'A','2026-01-01','','','','','',''),(11,10,'B','2026-01-01','','','','','',''),
    (12,10,'C','2026-01-01','','','','','',''),(13,10,'D','2026-01-01','','','','','','');
  INSERT INTO reports(id,incident_id,unit_id,author_id,narrative,vehicles,personnel,classification,status,released_at) VALUES
    (10,10,10,10,'','','',JSON_OBJECT(),'draft',NULL),
    (11,11,10,11,'','','',JSON_OBJECT(),'draft',NULL),
    (12,12,10,12,'','','',JSON_OBJECT(),'draft',NULL),
    (13,13,10,10,'','','',JSON_OBJECT(),'released','2026-01-02');
  INSERT INTO members(id,organization_id,divera_id,name) VALUES
    (10,10,'historisch','Historisches Mitglied'),
    (11,11,'fremd','Fremdes Mitglied');
  INSERT INTO report_crew(report_id,member_id) VALUES(10,10),(10,11);"
"${compose[@]}" run --rm migrate
"${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte \
  --execute="DELETE FROM schema_migrations WHERE name='001-report-workflow-and-vehicles.sql'"
"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm migrate

result="$("${compose[@]}" exec -T db mysql --user=root -ptest-password --batch --skip-column-names einsatzberichte --execute="
  SELECT CONCAT(
    (SELECT COUNT(*) FROM schema_migrations WHERE name='$migration_name'),'|',
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='migration_test'),'|',
    (SELECT GROUP_CONCAT(status ORDER BY id) FROM reports WHERE id BETWEEN 10 AND 13),'|',
    (SELECT COUNT(*) FROM report_transitions WHERE report_id BETWEEN 10 AND 13),'|',
    (SELECT COUNT(*) FROM schema_migrations WHERE name='001-report-workflow-and-vehicles.sql'),'|',
    (SELECT COUNT(*) FROM schema_migrations WHERE name='002-inactive-unit-members.sql'),'|',
    (SELECT COUNT(*) FROM schema_migrations WHERE name='003-report-additional-vehicles.sql'),'|',
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='report_additional_vehicles'),'|',
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='member_units' AND column_name='active'),'|',
    (SELECT CONCAT(COUNT(*),':',COALESCE(MAX(active),9)) FROM member_units WHERE member_id=10 AND unit_id=10)
  )")"
test "$result" = '1|1|author_draft,unit_review,wehr_review,wehr_review|4|1|1|1|1|1|1:0'

# Migration 002 stellt keine historische Einheitszuordnung über Mandantengrenzen hinweg her.
test "$("${compose[@]}" exec -T db mysql --user=root -ptest-password --batch --skip-column-names einsatzberichte \
  --execute="SELECT COUNT(*) FROM member_units WHERE member_id=11 AND unit_id=10")" = 0

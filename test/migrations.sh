#!/usr/bin/env bash
set -euo pipefail

project="migrationcheck-$$"
compose=(docker compose -p "$project")
migration_name="999-test-$project.sql"
migration_file="migrations/$migration_name"
trap 'rm -f "$migration_file"; "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT

printf 'CREATE TABLE migration_test (id INT PRIMARY KEY);\n' > "$migration_file"
"${compose[@]}" up --detach --wait db
until "${compose[@]}" exec -T db mysqladmin --user=root -ptest-password ping --silent; do sleep 1; done

# Simulate an installation from before the report workflow and vehicle catalog.
"${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte --execute="
  DROP TABLE report_transitions;
  DROP TABLE vehicles;
  DELETE FROM schema_migrations WHERE name='001-report-workflow-and-vehicles.sql';
  ALTER TABLE reports MODIFY status ENUM('draft','released') NOT NULL DEFAULT 'draft';
  INSERT INTO organizations(id,name) VALUES(10,'Migrationstest');
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
    (13,13,10,10,'','','',JSON_OBJECT(),'released','2026-01-02');"
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
    (SELECT COUNT(*) FROM schema_migrations WHERE name='001-report-workflow-and-vehicles.sql')
  )")"
test "$result" = '1|1|author_draft,unit_review,wehr_review,wehr_review|4|1'

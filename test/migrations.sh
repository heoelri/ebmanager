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

# Eine Altinstallation erhält Workflow, Stammdaten, Revisionen, historische Namens-Snapshots, Soft-Delete und Übungskennzeichnung genau einmal.
"${compose[@]}" exec -T db mysql --default-character-set=utf8mb4 --user=root -ptest-password einsatzberichte --execute="
  DROP TABLE incident_exercise_changes;
  ALTER TABLE incidents DROP COLUMN is_exercise;
  DELETE FROM schema_migrations WHERE name='007-incident-exercises.sql';
  DROP TABLE incident_deletions;
  ALTER TABLE incidents DROP COLUMN deleted_at;
  DELETE FROM schema_migrations WHERE name='006-incident-soft-delete.sql';
  ALTER TABLE reports DROP COLUMN author_name;
  ALTER TABLE report_crew DROP COLUMN member_name;
  ALTER TABLE incidents DROP COLUMN report_data_frozen;
  DELETE FROM schema_migrations WHERE name='005-historical-report-snapshots.sql';
  ALTER TABLE incidents DROP COLUMN revision;
  ALTER TABLE reports DROP COLUMN revision;
  DELETE FROM schema_migrations WHERE name='004-report-revisions.sql';
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
    (10,10,10,10,'','','Nicht rekonstruierbarer alter Name',JSON_OBJECT(),'draft',NULL),
    (11,11,10,11,'','','',JSON_OBJECT(),'draft',NULL),
    (12,12,10,12,'','','',JSON_OBJECT(),'draft',NULL),
    (13,13,10,10,'','','',JSON_OBJECT(),'released','2026-01-02');
  INSERT INTO members(id,organization_id,divera_id,name) VALUES
    (10,10,'historisch','Historisches Mitglied'),
    (11,11,'fremd','Fremdes Mitglied');
  INSERT INTO report_crew(report_id,member_id) VALUES(10,10),(10,11);"
"${compose[@]}" run --rm migrate
# Der Snapshot-Backfill erhöht Bestandsrevisionen einmal; spätere Stammdatenänderungen dürfen weder Namen noch Revisionen zurücksetzen.
"${compose[@]}" exec -T db mysql --default-character-set=utf8mb4 --user=root -ptest-password einsatzberichte --execute="
  UPDATE reports SET revision=7 WHERE id=10;
  UPDATE incidents SET revision=9 WHERE id=10;
  UPDATE users SET name='Heute umbenannte Führungskraft' WHERE id=10;
  UPDATE members SET name='Heute umbenanntes Mitglied' WHERE id=10;"
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
    (SELECT COUNT(*) FROM schema_migrations WHERE name='004-report-revisions.sql'),'|',
    (SELECT COUNT(*) FROM schema_migrations WHERE name='006-incident-soft-delete.sql'),'|',
    (SELECT COUNT(*) FROM schema_migrations WHERE name='007-incident-exercises.sql'),'|',
    (SELECT GROUP_CONCAT(revision ORDER BY id) FROM reports WHERE id BETWEEN 10 AND 13),'|',
    (SELECT GROUP_CONCAT(revision ORDER BY id) FROM incidents WHERE id BETWEEN 10 AND 13),'|',
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='report_additional_vehicles'),'|',
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='member_units' AND column_name='active'),'|',
    (SELECT CONCAT(COUNT(*),':',COALESCE(MAX(active),9)) FROM member_units WHERE member_id=10 AND unit_id=10),'|',
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='incidents' AND column_name='deleted_at'),'|',
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='incident_deletions'),'|',
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='incidents' AND column_name='is_exercise'),'|',
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='incident_exercise_changes'),'|',
    (SELECT SUM(is_exercise) FROM incidents WHERE id BETWEEN 10 AND 13)
  )")"
test "$result" = '1|1|author_draft,unit_review,wehr_review,wehr_review|4|1|1|1|1|1|1|7,2,2,2|9,2,2,2|1|1|1:0|1|1|1|1|0'

# Migration 005 bewahrt heutige Namen, synchronisiert Zusammenfassungen und übernimmt keine Namen aus Fremdmandanten.
test "$("${compose[@]}" exec -T db mysql --default-character-set=utf8mb4 --user=root -ptest-password --batch --skip-column-names einsatzberichte --execute="
  SELECT CONCAT(
    (SELECT COUNT(*) FROM schema_migrations WHERE name='005-historical-report-snapshots.sql'),'|',
    (SELECT SUM(report_data_frozen) FROM incidents WHERE id BETWEEN 10 AND 13),'|',
    (SELECT author_name FROM reports WHERE id=10),'|',
    (SELECT personnel FROM reports WHERE id=10),'|',
    (SELECT member_name FROM report_crew WHERE report_id=10 AND member_id=10),'|',
    (SELECT member_name='' FROM report_crew WHERE report_id=10 AND member_id=11)
  )")" = '1|4|Führungskraft|Historisches Mitglied|Historisches Mitglied|1'

# Migration 002 stellt keine historische Einheitszuordnung über Mandantengrenzen hinweg her.
test "$("${compose[@]}" exec -T db mysql --user=root -ptest-password --batch --skip-column-names einsatzberichte \
  --execute="SELECT COUNT(*) FROM member_units WHERE member_id=11 AND unit_id=10")" = 0

# Eine Wiederaufnahme nach den ADD COLUMN-Anweisungen überschreibt keine Snapshots und erhöht Revisionen nicht erneut.
sed -n '/^SET @previous_sql_mode=/,$p' migrations/005-historical-report-snapshots.sql |
  "${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte
test "$("${compose[@]}" exec -T db mysql --default-character-set=utf8mb4 --user=root -ptest-password --batch --skip-column-names einsatzberichte \
  --execute="SELECT CONCAT(r.author_name,'|',r.personnel,'|',r.revision,'|',i.revision) FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE r.id=10")" = 'Führungskraft|Historisches Mitglied|7|9'

# Zu lange UTF-8-Zusammenfassungen brechen ohne Trunkierung ab und rollen den gesamten Backfill zurück, auch ohne serverseitigen Strict-Mode.
"${compose[@]}" exec -T db mysql --default-character-set=utf8mb4 --user=root -ptest-password einsatzberichte --execute="
  ALTER TABLE reports MODIFY author_name VARCHAR(200) NULL;
  ALTER TABLE report_crew MODIFY member_name VARCHAR(200) NULL;
  INSERT INTO incidents(id,organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text)
    VALUES(20,10,'Grenzwert','2026-01-01','','','','','','');
  INSERT INTO reports(id,incident_id,unit_id,author_id,author_name,narrative,vehicles,personnel,classification)
    VALUES(20,20,10,10,NULL,'','','Alt',JSON_OBJECT());
  INSERT INTO members(id,organization_id,divera_id,name)
    WITH RECURSIVE numbers AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM numbers WHERE n<100)
    SELECT 100+n,10,CONCAT('lang-',n),REPEAT('😀',200) FROM numbers;
  INSERT INTO report_crew(report_id,member_id,member_name) SELECT 20,id,NULL FROM members WHERE id BETWEEN 101 AND 200;"
if { printf "SET SESSION sql_mode='';\n"; sed -n '/^SET @previous_sql_mode=/,$p' migrations/005-historical-report-snapshots.sql; } |
  "${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte; then
  echo "Migration hat überlanges Personal still gekürzt" >&2
  exit 1
fi
test "$("${compose[@]}" exec -T db mysql --user=root -ptest-password --batch --skip-column-names einsatzberichte --execute="
  SELECT CONCAT(
    (SELECT COUNT(*) FROM report_crew WHERE report_id=20 AND member_name IS NULL),'|',
    (SELECT CONCAT(author_name IS NULL,':',revision,':',personnel) FROM reports WHERE id=20),'|',
    (SELECT CONCAT(report_data_frozen,':',revision) FROM incidents WHERE id=20)
  )")" = '100|1:1:Alt|0:1'

# Nach fachlicher Klärung passt der vollständige Text in TEXT; der Backfill läuft ohne GROUP_CONCAT-Standardkürzung und ohne fremden Autorennamen.
"${compose[@]}" exec -T db mysql --default-character-set=utf8mb4 --user=root -ptest-password einsatzberichte --execute="
  UPDATE members SET name=CONCAT(LPAD(id,3,'0'),REPEAT('😀',100)) WHERE id BETWEEN 101 AND 200;
  INSERT INTO users(id,organization_id,name,email,password_hash,role) VALUES(20,11,'Fremder Autor','foreign-migration@example.test','x','wehrleitung');
  UPDATE reports SET author_id=20,updated_at='2026-01-02 03:04:05' WHERE id=20;"
sed -n '/^SET @previous_sql_mode=/,$p' migrations/005-historical-report-snapshots.sql |
  "${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte
test "$("${compose[@]}" exec -T db mysql --user=root -ptest-password --batch --skip-column-names einsatzberichte --execute="
  SELECT CONCAT(
    (SELECT CONCAT(author_name='',':',revision,':',OCTET_LENGTH(personnel),':',LEFT(personnel,3),':',updated_at='2026-01-02 03:04:05') FROM reports WHERE id=20),'|',
    (SELECT CONCAT(report_data_frozen,':',revision) FROM incidents WHERE id=20),'|',
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND is_nullable='NO'
      AND ((table_name='reports' AND column_name='author_name') OR (table_name='report_crew' AND column_name='member_name')
        OR (table_name='incidents' AND column_name='report_data_frozen')))
  )")" = '1:2:40498:101:1|1:2|3'

# Alte Anwendungsschreiber ohne Namenssnapshot scheitern ausdrücklich statt unbemerkte leere Historien anzulegen.
"${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte --execute="
  INSERT INTO incidents(id,organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text)
  VALUES(21,10,'Pflichtsnapshot','2026-01-01','','','','','','');"
if "${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte --execute="
  INSERT INTO reports(incident_id,unit_id,author_id,narrative,vehicles,personnel,classification)
  VALUES(21,10,10,'','','',JSON_OBJECT())"; then
  echo "Bericht ohne Autorensnapshot akzeptiert" >&2
  exit 1
fi
if "${compose[@]}" exec -T db mysql --user=root -ptest-password einsatzberichte --execute="
  INSERT INTO report_crew(report_id,member_id) VALUES(20,10)"; then
  echo "Besatzung ohne Namenssnapshot akzeptiert" >&2
  exit 1
fi

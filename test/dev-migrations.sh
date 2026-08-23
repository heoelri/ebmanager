#!/usr/bin/env bash
set -euo pipefail

project="migrationcheck-$$"
compose=(docker compose -p "$project")
trap '"${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT

"${compose[@]}" up --detach --wait db
# The healthcheck can briefly report "healthy" while MySQL's entrypoint is
# still restarting from its temporary init server to the final one, so wait
# until the socket-based client actually connects before issuing commands.
until "${compose[@]}" exec -T db mysqladmin --user=root --password=test-password ping --silent; do sleep 1; done
"${compose[@]}" exec -T db mysql --user=root --password=test-password einsatzberichte <<'SQL'
DROP TABLE schema_migrations, divera_imports, login_history, password_resets;
ALTER TABLE reports
  ADD KEY reports_unit_legacy (unit_id),
  DROP INDEX reports_unit_year_number,
  DROP COLUMN incident_command,
  DROP COLUMN damaging_party,
  DROP COLUMN damaged_party,
  DROP COLUMN running_number,
  DROP COLUMN report_year;
SQL

"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm migrate

result="$("${compose[@]}" exec -T db mysql --user=root --password=test-password --batch --skip-column-names einsatzberichte --execute="
  SELECT CONCAT(
    (SELECT COUNT(*) FROM schema_migrations),'|',
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name IN ('password_resets','login_history','divera_imports')),'|',
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='reports' AND column_name IN ('report_year','running_number','damaged_party','damaging_party','incident_command'))
  )")"
test "$result" = '5|3|5'

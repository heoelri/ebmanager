#!/usr/bin/env bash
set -euo pipefail

project="migrationcheck-$$"
compose=(docker compose -p "$project")
migration_file=migrations/999-test.sql
trap 'rm -f "$migration_file"; "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT

printf 'CREATE TABLE migration_test (id INT PRIMARY KEY);\n' > "$migration_file"
"${compose[@]}" up --detach --wait db
until "${compose[@]}" exec -T db mysqladmin --user=root -ptest-password ping --silent; do sleep 1; done

"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm migrate

result="$("${compose[@]}" exec -T db mysql --user=root -ptest-password --batch --skip-column-names einsatzberichte --execute="
  SELECT CONCAT(
    (SELECT COUNT(*) FROM schema_migrations WHERE name='999-test.sql'),'|',
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='migration_test')
  )")"
test "$result" = '1|1'

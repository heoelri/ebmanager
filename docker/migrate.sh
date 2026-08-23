#!/usr/bin/env bash
set -euo pipefail

export MYSQL_PWD="$DB_PASSWORD"
mysql=(mysql --host="$DB_HOST" --user="$DB_USER" --database="$DB_NAME" --batch --skip-column-names)
query() { "${mysql[@]}" --execute="$1"; }
mark() { query "INSERT INTO schema_migrations(name,applied_at) VALUES('$1',UTC_TIMESTAMP())"; }
applied() { [[ "$(query "SELECT COUNT(*) FROM schema_migrations WHERE name='$1'")" == 1 ]]; }

until mysqladmin --host="$DB_HOST" --user="$DB_USER" ping --silent; do sleep 1; done

had_history="$(query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='schema_migrations'")"
query "CREATE TABLE IF NOT EXISTS schema_migrations (
  name VARCHAR(255) PRIMARY KEY,
  applied_at DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

if [[ "$had_history" == 0 ]]; then
  if [[ "$(query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='password_resets'")" == 0 ]]; then
    "${mysql[@]}" < /migrations/001-password-resets.sql
  fi
  mark 001-password-resets.sql

  # Existing local tokens may already be hashed; invalidating dev sessions avoids double hashing.
  query "DELETE FROM sessions"
  mark 002-hash-session-tokens.sql

  report_columns="$(query "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='reports' AND column_name IN ('report_year','running_number','damaged_party','damaging_party','incident_command')")"
  if [[ "$report_columns" == 0 ]]; then
    "${mysql[@]}" < /migrations/003-report-details.sql
  elif [[ "$report_columns" != 5 ]]; then
    echo "Die lokale reports-Tabelle ist nur teilweise migriert. Setze das Dev-Volume zurück oder vervollständige die Migration." >&2
    exit 1
  fi
  mark 003-report-details.sql

  if [[ "$(query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='login_history'")" == 0 ]]; then
    "${mysql[@]}" < /migrations/004-login-history.sql
  fi
  mark 004-login-history.sql
fi

for file in /migrations/*.sql; do
  name="${file##*/}"
  [[ "$name" =~ ^[0-9]{3}-[a-z0-9-]+\.sql$ ]] || {
    echo "Ungültiger Migrationsname: $name" >&2
    exit 1
  }
  if ! applied "$name"; then
    echo "Wende $name an"
    "${mysql[@]}" < "$file"
    mark "$name"
  fi
done

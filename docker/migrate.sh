#!/usr/bin/env bash
set -euo pipefail

export MYSQL_PWD="$DB_PASSWORD"
mysql=(mysql --host="$DB_HOST" --user="$DB_USER" --database="$DB_NAME" --batch --skip-column-names)
query() { "${mysql[@]}" --execute="$1"; }
mark() { query "INSERT INTO schema_migrations(name,applied_at) VALUES('$1',UTC_TIMESTAMP())"; }
applied() { [[ "$(query "SELECT COUNT(*) FROM schema_migrations WHERE name='$1'")" == 1 ]]; }

until mysqladmin --host="$DB_HOST" --user="$DB_USER" ping --silent; do sleep 1; done

query "CREATE TABLE IF NOT EXISTS schema_migrations (
  name VARCHAR(255) PRIMARY KEY,
  applied_at DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

shopt -s nullglob
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

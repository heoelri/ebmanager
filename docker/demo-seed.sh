#!/usr/bin/env bash
set -euo pipefail

export MYSQL_PWD="$DB_PASSWORD"
mysql=(mysql --host="$DB_HOST" --user="$DB_USER" --database="$DB_NAME" --batch --skip-column-names)

until mysqladmin --host="$DB_HOST" --user="$DB_USER" ping --silent; do sleep 1; done

summary=$("${mysql[@]}" < /demo/seed.sql)

[[ "$summary" == '3|8|24|8|17|17|3|3|2|1' ]] || {
  echo "Demo-Daten sind unvollständig: $summary" >&2
  exit 1
}

echo 'Demofeuerwehr wurde zurückgesetzt und vollständig importiert.'

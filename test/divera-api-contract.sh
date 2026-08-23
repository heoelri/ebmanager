#!/usr/bin/env bash
set -euo pipefail

directory="$(mktemp -d)"
trap 'rm -rf "$directory"' EXIT
alarm="$directory/api_v2_alarm.yaml"
pull="$directory/api_v2_pull.yaml"

curl --fail --silent --show-error --retry 3 https://api.divera247.com/docs/api_v2_alarm.yaml --output "$alarm"
curl --fail --silent --show-error --retry 3 https://api.divera247.com/docs/api_v2_pull.yaml --output "$pull"

grep -A3 '^  /api/v2/alarms:$' "$alarm" | grep --quiet '^    get:$'
grep -A3 '^  /api/v2/pull/all:$' "$pull" | grep --quiet '^    get:$'

for field in id foreign_id date title text address lat lng caller patient remark; do
  grep --extended-regexp --quiet "^[[:space:]]+$field:" "$alarm"
  grep --fixed-strings --quiet "'$field' =>" test/fake-divera.php
done

for field in consumer qualification vehicle; do
  grep --extended-regexp --quiet "^[[:space:]]+$field:" "$pull"
  grep --fixed-strings --quiet "'$field' =>" test/fake-divera.php
done

grep --fixed-strings --quiet "'data' => ['items'" test/fake-divera.php
grep --fixed-strings --quiet "'data' => ['cluster'" test/fake-divera.php

#!/bin/bash
set -e

enable_experimental_features() {
  local db_url="$1"
  local user_email="${2:-editor@openfn.org}"

  local query="
UPDATE users
SET preferences = jsonb_set(
  COALESCE(preferences, '{}'::jsonb),
  '{experimental_features}',
  'true'::jsonb
)
WHERE email = '$user_email'
RETURNING id, email, preferences->>'experimental_features' as experimental_enabled;
"

  psql "$db_url" -t -c "$query"
}

# Support both sourcing and direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  enable_experimental_features "${1:-$DATABASE_URL}" "${2}"
fi

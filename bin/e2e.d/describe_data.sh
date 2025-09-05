#!/bin/bash
# E2E Test Data Describe - Query database state via psql + jq
set -e

describe_test_data() {
  local db_url="$1"

  # Query projects, users, and workflows in a single psql call
  local query="
SELECT json_build_object(
  'projects', (
    SELECT json_agg(
      json_build_object('id', id, 'name', name) ORDER BY name
    )
    FROM projects
  ),
  'users', (
    SELECT json_agg(
      json_build_object(
        'id', id, 
        'email', email, 
        'first_name', first_name, 
        'last_name', last_name
      ) ORDER BY email
    )
    FROM users
  ),
  'workflows', (
    SELECT json_agg(
      json_build_object(
        'id', id, 
        'name', name, 
        'project_id', project_id
      ) ORDER BY name
    )
    FROM workflows
  ),
  'timestamp', to_json(now()::timestamp)
) as test_data;
"

  # Execute query and format JSON
  psql "$db_url" -t -c "$query" | jq -r '.'
}

# Allow sourcing this file or running directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  describe_test_data "${1:-$DATABASE_URL}"
fi

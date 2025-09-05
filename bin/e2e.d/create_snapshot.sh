#! /usr/bin/env bash
set -e

# Create snapshot of demo data for fast e2e test resets
# Usage: ./priv/repo/create_snapshot.sh $DATABASE_URL
# Or source and call: create_snapshot [DATABASE_URL]

create_snapshot() {
  local database_url="${1:-${DATABASE_URL}}"
  local snapshot_file="${SNAPSHOT_FILE:-/tmp/demo_data_snapshot.sql}"

  if [ -z "$database_url" ]; then
    echo "Error: DATABASE_URL not provided"
    echo "Usage: create_snapshot [DATABASE_URL]"
    return 1
  fi

  # Ensure tmp directory exists
  mkdir -p "$(dirname "$snapshot_file")"

  echo "Creating demo data snapshot..."
  echo "Database: $database_url"
  echo "Output: $snapshot_file"

  # Use pg_dump to create a data-only dump
  # --data-only: Only dump data, not schema
  # --disable-triggers: Speed up restore by disabling triggers
  # --no-owner: Don't include ownership commands
  # --no-privileges: Don't include privilege commands
  # --exclude-table-data: Skip tables that don't contain user data
  # Suppress warnings about circular foreign keys (we handle with --disable-triggers on restore)
  pg_dump "$database_url" \
    --data-only \
    --disable-triggers \
    --no-owner \
    --no-privileges \
    --exclude-table-data=schema_migrations \
    --exclude-table-data=oban_jobs \
    --exclude-table-data=oban_peers \
    >"$snapshot_file" 2>/dev/null

  # Add some metadata to the top of the file
  {
    echo "-- Lightning Demo Data Snapshot"
    echo "-- Generated: $(date)"
    echo "-- Database: $database_url"
    echo "-- Fast restore for e2e testing"
    echo ""
    cat "$snapshot_file"
  } >"${snapshot_file}.tmp" && mv "${snapshot_file}.tmp" "$snapshot_file"

  echo "Snapshot created successfully: $snapshot_file"
  echo "File size: $(du -h "$snapshot_file" | cut -f1)"
}

# Only show restore instructions if called directly (not sourced)
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  create_snapshot "$1"
  echo ""
  echo "To restore this snapshot:"
  echo "  psql \$DATABASE_URL -f $snapshot_file"
fi

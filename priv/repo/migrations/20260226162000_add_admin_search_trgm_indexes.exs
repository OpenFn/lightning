defmodule Lightning.Repo.Migrations.AddAdminSearchTrgmIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS users_first_name_trgm_idx ON users USING GIN (first_name gin_trgm_ops) WHERE first_name IS NOT NULL"

    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS users_last_name_trgm_idx ON users USING GIN (last_name gin_trgm_ops) WHERE last_name IS NOT NULL"

    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS users_email_trgm_idx ON users USING GIN ((email::text) gin_trgm_ops) WHERE email IS NOT NULL"

    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS projects_name_trgm_idx ON projects USING GIN (name gin_trgm_ops) WHERE name IS NOT NULL"

    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS projects_description_trgm_idx ON projects USING GIN (description gin_trgm_ops) WHERE description IS NOT NULL"
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS users_first_name_trgm_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS users_last_name_trgm_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS users_email_trgm_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS projects_name_trgm_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS projects_description_trgm_idx"
  end
end

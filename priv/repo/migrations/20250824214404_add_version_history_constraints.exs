defmodule Lightning.Repo.Migrations.AddVersionHistoryConstraints do
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION hex12_array_ok(arr text[])
    RETURNS boolean
    LANGUAGE SQL
    IMMUTABLE
    AS $$
      SELECT COALESCE(bool_and(v ~ '^[a-f0-9]{12}$'), true)
      FROM unnest(COALESCE(arr, ARRAY[]::text[])) AS v
    $$;
    """)

    execute("""
    ALTER TABLE projects
    ADD CONSTRAINT projects_version_history_all_hex12
    CHECK (hex12_array_ok(version_history));
    """)

    execute("""
    ALTER TABLE workflows
    ADD CONSTRAINT workflows_version_history_all_hex12
    CHECK (hex12_array_ok(version_history));
    """)
  end

  def down do
    execute("ALTER TABLE projects  DROP CONSTRAINT IF EXISTS projects_version_history_all_hex12;")

    execute(
      "ALTER TABLE workflows DROP CONSTRAINT IF EXISTS workflows_version_history_all_hex12;"
    )

    execute("DROP FUNCTION IF EXISTS hex12_array_ok(text[]);")
  end
end

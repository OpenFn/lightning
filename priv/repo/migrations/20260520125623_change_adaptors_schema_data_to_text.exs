defmodule Lightning.Repo.Migrations.ChangeAdaptorsSchemaDataToText do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE adaptors
      ALTER COLUMN schema_data TYPE text
      USING schema_data::text
    """)
  end

  def down do
    execute("""
    ALTER TABLE adaptors
      ALTER COLUMN schema_data TYPE jsonb
      USING schema_data::jsonb
    """)
  end
end

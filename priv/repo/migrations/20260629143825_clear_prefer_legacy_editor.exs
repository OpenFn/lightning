defmodule Lightning.Repo.Migrations.ClearPreferLegacyEditor do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE users SET preferences = preferences - 'prefer_legacy_editor' WHERE preferences ? 'prefer_legacy_editor'
    """)
  end
end

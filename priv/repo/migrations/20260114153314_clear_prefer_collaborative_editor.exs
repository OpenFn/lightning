defmodule Lightning.Repo.Migrations.ClearPreferCollaborativeEditor do
  use Ecto.Migration

  def up do
    # Remove prefer_collaborative_editor from preference of every user
    execute("""
    UPDATE users SET preferences = preferences - 'prefer_collaborative_editor' WHERE preferences ? 'prefer_collaborative_editor'
    """)
  end
end

defmodule Lightning.Repo.Migrations.RemoveAiDisclaimerReadPreference do
  use Ecto.Migration

  def change do
    execute(
      """
      UPDATE users SET preferences = preferences - 'ai_assistant.disclaimer_read_at' WHERE preferences ? 'ai_assistant.disclaimer_read_at'
      """,
      ""
    )
  end
end

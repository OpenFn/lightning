defmodule Lightning.Repo.Migrations.UpdateAiChatSessionTypes do
  use Ecto.Migration

  def change do
    execute("ALTER table ai_chat_sessions ALTER COLUMN session_type DROP DEFAULT", "SELECT true")

    execute(
      "UPDATE ai_chat_sessions SET session_type = 'job_code' WHERE session_type = 'job'",
      "SELECT true"
    )
  end
end

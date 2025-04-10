defmodule Lightning.Repo.Migrations.AddMetaToAiChatSessions do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_sessions) do
      add :meta, :jsonb
    end
  end
end

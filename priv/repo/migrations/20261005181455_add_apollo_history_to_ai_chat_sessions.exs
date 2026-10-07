defmodule Lightning.Repo.Migrations.AddApolloHistoryToAiChatSessions do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_sessions) do
      add :apollo_history, :jsonb
    end
  end
end

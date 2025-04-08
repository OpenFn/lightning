defmodule Lightning.Repo.Migrations.AddRagAndPromptToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :rag_results, :jsonb
      add :prompt, :text
    end
  end
end

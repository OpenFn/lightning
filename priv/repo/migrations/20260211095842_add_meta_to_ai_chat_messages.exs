defmodule Lightning.Repo.Migrations.AddMetaToAiChatMessages do
  use Ecto.Migration

  def up do
    alter table(:ai_chat_messages) do
      add :meta, :map, default: %{}
    end
  end

  def down do
    alter table(:ai_chat_messages) do
      remove :meta
    end
  end
end

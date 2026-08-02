defmodule Lightning.Repo.Migrations.AddResponseSegmentsToAiChatMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :response_segments, {:array, :map}, null: true
    end
  end
end

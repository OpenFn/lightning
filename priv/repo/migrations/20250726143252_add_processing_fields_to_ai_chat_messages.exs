defmodule Lightning.Repo.Migrations.AddProcessingFieldsToAiChatMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :processing_started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
    end
  end
end

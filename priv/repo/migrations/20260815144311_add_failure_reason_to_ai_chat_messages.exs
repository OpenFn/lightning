defmodule Lightning.Repo.Migrations.AddFailureReasonToAiChatMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :failure_category, :string
      add :failure_message, :text
    end
  end
end

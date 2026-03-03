defmodule Lightning.Repo.Migrations.JobIdFromChatSessionToChatMessage do
  use Ecto.Migration

  def up do
    alter table(:ai_chat_messages) do
      add :job_id, references(:jobs, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:ai_chat_messages, [:job_id])

    execute """
    UPDATE ai_chat_messages
    SET job_id = ai_chat_sessions.job_id
    FROM ai_chat_sessions
    WHERE ai_chat_messages.chat_session_id = ai_chat_sessions.id
      AND ai_chat_sessions.job_id IS NOT NULL
    """
  end

  def down do
    drop index(:ai_chat_messages, [:job_id])

    alter table(:ai_chat_messages) do
      remove :job_id
    end
  end
end

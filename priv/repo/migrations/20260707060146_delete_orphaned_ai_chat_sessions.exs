defmodule Lightning.Repo.Migrations.DeleteOrphanedAiChatSessions do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM ai_chat_sessions s
    WHERE s.project_id IS NULL
      AND s.job_id IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM workflows w
        WHERE w.id::text = lower(s.meta -> 'unsaved_job' ->> 'workflow_id')
      )
    """)
  end

  def down, do: :ok
end

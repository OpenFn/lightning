defmodule Lightning.Repo.Migrations.AddWorkflowSupportToAiChat do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :workflow_code, :text
    end

    alter table(:ai_chat_sessions) do
      add :session_type, :string, default: "job"
      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id), null: true

      add :workflow_id, references(:workflows, on_delete: :nilify_all, type: :binary_id),
        null: true
    end

    create index(:ai_chat_sessions, [:project_id])
    create index(:ai_chat_sessions, [:workflow_id])

    execute(
      "ALTER TABLE ai_chat_sessions ALTER COLUMN job_id DROP NOT NULL",
      "ALTER TABLE ai_chat_sessions ALTER COLUMN job_id SET NOT NULL"
    )
  end
end

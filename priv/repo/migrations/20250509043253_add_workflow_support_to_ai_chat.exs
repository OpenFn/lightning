defmodule Lightning.Repo.Migrations.AddWorkflowSupportToAiChat do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :workflow_code, :text
    end

    alter table(:ai_chat_sessions) do
      add :session_type, :string, default: "job"
      add :project_id, references(:projects, on_delete: :delete_all), null: true
      add :workflow_id, references(:workflows, on_delete: :nilify_all), null: true

      modify :job_id, references(:jobs, on_delete: :delete_all), null: true
    end

    create index(:ai_chat_sessions, [:project_id])
    create index(:ai_chat_sessions, [:workflow_id])
  end
end

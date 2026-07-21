defmodule Lightning.Repo.Migrations.CascadeDeleteAiChatSessionsWithJobAndWorkflow do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_sessions) do
      modify :job_id,
             references(:jobs, type: :binary_id, on_delete: :delete_all),
             from: references(:jobs, type: :binary_id, on_delete: :nilify_all)

      modify :workflow_id,
             references(:workflows, type: :binary_id, on_delete: :delete_all),
             from: references(:workflows, type: :binary_id, on_delete: :nilify_all)
    end
  end
end

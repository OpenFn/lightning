defmodule Lightning.Repo.Migrations.AddAiChatCounter do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_sessions) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
      add :msgs_counter, :integer, default: 0
    end
  end
end

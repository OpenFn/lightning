defmodule Lightning.Repo.Migrations.RenameWorkflowCodeToCodeInAiChat do
  use Ecto.Migration

  def change do
    rename table(:ai_chat_messages), :workflow_code, to: :code
  end
end

defmodule Lightning.Repo.Migrations.AddJobCodeToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :job_code, :text
    end
  end
end

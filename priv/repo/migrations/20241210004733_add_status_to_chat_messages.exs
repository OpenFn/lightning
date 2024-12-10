defmodule Lightning.Repo.Migrations.AddStatusToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      add :status, :string, default: "success", null: false
    end
  end
end

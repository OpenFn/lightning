defmodule Lightning.Repo.Migrations.CreateChatSessionsTables do
  use Ecto.Migration

  def change do
    create table(:ai_chat_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :is_public, :boolean
      add :is_deleted, :boolean
      add :job_id, references(:jobs, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create table(:ai_chat_messages, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :chat_session_id,
          references(:ai_chat_sessions, type: :binary_id, on_delete: :delete_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :content, :text
      add :role, :string
      add :is_deleted, :boolean
      add :is_public, :boolean

      timestamps()
    end
  end
end

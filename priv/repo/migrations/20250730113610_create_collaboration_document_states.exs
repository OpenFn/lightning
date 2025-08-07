defmodule Lightning.Repo.Migrations.CreateCollaborationDocumentStates do
  use Ecto.Migration

  def change do
    create table(:collaboration_document_states) do
      add :document_name, :string, null: false
      add :state_data, :binary, null: false
      add :state_vector, :binary
      add :user_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:collaboration_document_states, [:document_name])
  end
end

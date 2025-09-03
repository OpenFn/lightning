defmodule Lightning.Repo.Migrations.CreateCollaborationDocumentStates do
  use Ecto.Migration

  def change do
    create table(:collaboration_document_states) do
      add :document_name, :string, null: false
      add :state_data, :binary, null: false
      add :state_vector, :binary
      # "update", "checkpoint", "state_vector"
      add :version, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Remove unique constraint, allow multiple records per document
    create index(:collaboration_document_states, [:document_name, :version])
    create index(:collaboration_document_states, [:document_name, :inserted_at])
  end
end

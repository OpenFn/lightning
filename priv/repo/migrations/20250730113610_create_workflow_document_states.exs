defmodule Lightning.Repo.Migrations.CreateWorkflowDocumentStates do
  use Ecto.Migration

  def change do
    create table(:workflow_document_states) do
      add :document_name, :string, null: false
      add :state_data, :binary, null: false
      add :state_vector, :binary
      add :user_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workflow_document_states, [:document_name])
  end
end

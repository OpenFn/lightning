defmodule Lightning.Repo.Migrations.CreateWorkflowEdges do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      modify(:trigger_id, :uuid, null: true, from: {:uuid, null: false})
    end

    create(unique_index(:jobs, [:id, :workflow_id]))
    create(unique_index(:triggers, [:id, :workflow_id]))

    create table(:workflow_edges, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:workflow_id, references(:workflows, on_delete: :delete_all, type: :binary_id),
        null: false
      )

      add(
        :source_job_id,
        references(:jobs,
          on_delete: :delete_all,
          type: :binary_id,
          with: [workflow_id: :workflow_id]
        )
      )

      add(
        :source_trigger_id,
        references(:triggers,
          on_delete: :delete_all,
          type: :binary_id,
          with: [workflow_id: :workflow_id]
        )
      )

      add(:condition, :string, null: true)

      add(
        :target_job_id,
        references(:jobs,
          on_delete: :delete_all,
          type: :binary_id,
          with: [workflow_id: :workflow_id]
        )
      )

      timestamps()
    end
  end
end

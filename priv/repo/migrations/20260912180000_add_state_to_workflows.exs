defmodule Lightning.Repo.Migrations.AddStateToWorkflows do
  use Ecto.Migration

  def up do
    alter table(:workflows) do
      add :state, :string, null: false, default: "draft"
    end

    # Backfill so current behaviour is preserved: a workflow that already has an
    # enabled trigger is treated as "live"; everything else stays "draft".
    execute("""
    UPDATE workflows
       SET state = 'live'
     WHERE id IN (SELECT DISTINCT workflow_id FROM triggers WHERE enabled = true)
    """)
  end

  def down do
    alter table(:workflows) do
      remove :state
    end
  end
end

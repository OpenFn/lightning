defmodule Lightning.Repo.Migrations.AddInvocationReasonsTable do
  use Ecto.Migration

  def change do
    create table(:invocation_reasons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, size: 20, null: false

      add :trigger_id, references(:triggers, on_delete: :nothing, type: :binary_id)
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :run_id, references(:runs, on_delete: :nothing, type: :binary_id)
      add :dataclip_id, references(:dataclips, on_delete: :nothing, type: :binary_id)

      timestamps()
    end

    create index(:invocation_reasons, [:trigger_id])
    create index(:invocation_reasons, [:user_id])
    create index(:invocation_reasons, [:run_id])
    create index(:invocation_reasons, [:dataclip_id])
  end
end

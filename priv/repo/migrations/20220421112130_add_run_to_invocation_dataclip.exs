defmodule Lightning.Repo.Migrations.AddRunToInvocationDataclip do
  use Ecto.Migration

  def change do
    alter table(:dataclips) do
      add :run_id, references(:runs, on_delete: :delete_all, type: :binary_id), null: true
    end
  end
end

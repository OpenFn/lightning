defmodule Lightning.Repo.Migrations.CreateInvocationEvents do
  use Ecto.Migration

  def change do
    create table(:invocation_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :dataclip_id, references(:dataclips, on_delete: :nothing, type: :binary_id)

      timestamps()
    end

    create index(:invocation_events, [:dataclip_id])
  end
end

defmodule Lightning.Repo.Migrations.RemoveInvocationReasonsAndConstraints do
  use Ecto.Migration

  def up do
    alter table(:work_orders) do
      remove :reason_id
    end

    alter table(:attempts) do
      remove :reason_id
    end

    drop table(:invocation_reasons)
  end

  def down do
    create table(:invocation_reasons) do
    end

    alter table(:work_orders) do
      add :reason_id, references(:invocation_reasons, type: :binary_id), null: false
    end

    alter table(:attempts) do
      add :reason_id, references(:invocation_reasons, type: :binary_id), null: false
    end
  end
end

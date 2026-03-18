defmodule Lightning.Repo.Migrations.AddQueueToRuns do
  use Ecto.Migration

  def up do
    alter table(:runs) do
      add :queue, :string
    end

    flush()

    execute """
    UPDATE runs SET queue = CASE priority
      WHEN 0 THEN 'manual'
      ELSE 'default'
    END
    """

    alter table(:runs) do
      modify :queue, :string, null: false, default: "default"
    end
  end

  def down do
    alter table(:runs) do
      remove :queue
    end
  end
end

defmodule Lightning.Repo.Migrations.AddExitReasonToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :exit_reason, :string
    end

    create index(:runs, [:exit_reason])

    # set all existing runs exit_reason to from the corresponding exit_code
    execute(
      fn ->
        repo().query!(
          """
          UPDATE runs
          SET exit_reason=
          (
            CASE runs.exit_code
                WHEN 0 THEN 'success'
                ELSE 'error'
            END
          )
          WHERE runs.exit_code IS NOT NULL;
          """,
          [],
          log: :info
        )
      end,
      ""
    )
  end
end

defmodule Lightning.Repo.Migrations.DeleteStepsWithoutRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Steps scanned per statement. Each one walks a slice of the steps primary
  # key and probes run_steps by step_id, so no statement holds much memory or
  # many locks, however many steps or orphans an instance has.
  @chunk_size 1000

  def up do
    delete_orphans_after(Ecto.UUID.dump!("00000000-0000-0000-0000-000000000000"))
  end

  def down, do: :ok

  defp delete_orphans_after(last_id) do
    %{rows: rows} =
      repo().query!(
        """
        WITH chunk AS (
          SELECT id FROM steps WHERE id > $1 ORDER BY id LIMIT $2
        ), deleted AS (
          DELETE FROM steps s
          USING chunk
          WHERE s.id = chunk.id
            AND NOT EXISTS (SELECT 1 FROM run_steps rs WHERE rs.step_id = s.id)
        )
        SELECT id FROM chunk ORDER BY id DESC LIMIT 1
        """,
        [last_id, @chunk_size],
        timeout: :infinity,
        log: false
      )

    case rows do
      [] -> :ok
      [[id]] -> delete_orphans_after(id)
    end
  end
end

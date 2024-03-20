defmodule Lightning.Repo.Migrations.GenerateLogLineSearchVectors do
  require Logger
  use Ecto.Migration

  def change do
    execute(
      # Calculate the search vectors in batches of 2500 rows until all rows have
      # been processed.
      fn ->
        Stream.unfold(1, fn n ->
          if n > 0 do
            %{num_rows: n} = update_search_vector(2500)
            Logger.info("Updated search_vector for #{n} rows")

            {:ok, n}
          else
            nil
          end
        end)
        |> Stream.run()
      end,
      ""
    )
  end

  defp update_search_vector(limit) do
    repo().query!(
      """
      UPDATE log_lines
      SET search_vector = to_tsvector('english', message)
      WHERE id IN (
        SELECT id
        FROM log_lines
        WHERE search_vector IS NULL
        LIMIT $1
      )
      """,
      [limit],
      log: :debug
    )
  end
end

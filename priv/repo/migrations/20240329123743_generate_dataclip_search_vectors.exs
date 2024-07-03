defmodule Lightning.Repo.Migrations.GenerateDataclipSearchVectors do
  require Logger
  use Ecto.Migration

  def change do
    execute(
      # Calculate the search vectors in batches of 1000 rows until all rows have
      # been processed.
      fn ->
        Stream.unfold(1, fn n ->
          if n > 0 do
            %{num_rows: n} = update_search_vector(1000)
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
      UPDATE dataclips
      SET search_vector = jsonb_to_tsvector('english_nostop', body, '"all"')
      WHERE id IN (
        SELECT id
        FROM dataclips
        WHERE search_vector IS NULL
        AND body IS NOT NULL
        LIMIT $1
      )
      """,
      [limit],
      log: :debug
    )
  end
end

defmodule Lightning.QueryCountHelpers do
  @moduledoc """
  Counts the database queries a function costs.
  """

  @doc """
  Runs `fun` and returns `{result, query_count}`.

  Only queries from the calling process count, because other async tests query
  from their own processes. Pass `source` to count only queries on that table.
  """
  def count_queries(fun, source \\ nil) do
    parent = self()
    ref = make_ref()
    handler = {__MODULE__, ref}

    :telemetry.attach(
      handler,
      [:lightning, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == parent and (is_nil(source) or source == meta[:source]),
          do: send(parent, {ref, :query})
      end,
      nil
    )

    result =
      try do
        fun.()
      after
        :telemetry.detach(handler)
      end

    {result, drain(ref, 0)}
  end

  defp drain(ref, count) do
    receive do
      {^ref, :query} -> drain(ref, count + 1)
    after
      0 -> count
    end
  end
end

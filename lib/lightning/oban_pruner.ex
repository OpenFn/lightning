defmodule ObanPruner do
  @moduledoc """
  The Oban Pruner removes completed Oban jobs. It leaves everything else for manual inspection.
  """
  use Oban.Worker,
    queue: :background,
    priority: 1,
    max_attempts: 10,
    unique: [period: 55]

  import Ecto.Query

  alias Lightning.Repo

  require Logger

  @doc """
  Deletes completed Oban jobs, leaving discarded for manual inspection.
  """
  @impl Oban.Worker
  def perform(%Job{}) do
    age_limit = Application.get_env(:lightning, :queue_result_retention_period)

    {pruned, nil} =
      from(j in Oban.Job,
        where:
          j.state == "completed" and
            j.completed_at < ago(^age_limit, "minute")
      )
      |> Repo.delete_all()

    Logger.debug(fn ->
      # coveralls-ignore-start
      "Pruned #{pruned} Oban jobs."
      # coveralls-ignore-stop
    end)

    {:ok, pruned}
  end
end

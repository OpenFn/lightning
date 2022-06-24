defmodule ObanPruner do
  use Oban.Worker,
    queue: :background,
    priority: 1,
    max_attempts: 10,
    unique: [period: 55]

  require Logger

  alias Lightning.Repo
  import Ecto.Query

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

    Logger.debug(fn -> "Pruned #{pruned} Oban jobs." end)
    {:ok, pruned}
  end
end

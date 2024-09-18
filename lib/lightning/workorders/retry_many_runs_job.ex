defmodule Lightning.WorkOrders.RetryManyRunsJob do
  @moduledoc false
  use Oban.Worker,
    queue: :scheduler,
    max_attempts: 3

  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.WorkOrders

  require Logger

  @impl Oban.Worker
  def perform(%{
        args: %{"runs_ids" => runs_ids, "created_by" => creating_user_id}
      }) do
    runs_ids
    |> preload_runs_for_retry()
    |> Enum.each(fn run ->
      starting_job =
        run.starting_job || hd(run.starting_trigger.edges).target_job

      creating_user = Repo.get!(User, creating_user_id)

      # JUST FOR TESTING TO ASSERT DO_RETRY WORKS
      # WILL BE REPLACED WITH enqueue_many
      Multi.new()
      |> Multi.put(:run, run)
      |> Multi.put(:starting_job, starting_job)
      |> Multi.put(:steps, [])
      |> Multi.put(:input_dataclip_id, run.dataclip_id)
      |> WorkOrders.do_retry(creating_user)
      |> case do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Logger.error("Error retrying run #{run.id}: #{inspect(changeset)}")
      end
    end)

    :ok
  end

  defp preload_runs_for_retry(runs_ids) do
    from(r in Run,
      where: r.id in ^runs_ids,
      preload: [
        :starting_job,
        starting_trigger: [edges: :target_job],
        work_order: [:workflow]
      ]
    )
    |> Repo.all()
  end
end

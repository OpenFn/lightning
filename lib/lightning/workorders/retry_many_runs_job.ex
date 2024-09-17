defmodule Lightning.Workorders.RetryManyRunsJob do
  use Oban.Worker,
    queue: :scheduler,
    max_attempts: 3

  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.WorkOrders

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

      WorkOrders.do_retry(
        run.work_order,
        run.dataclip,
        starting_job,
        [],
        creating_user
      )
    end)

    :ok
  end

  defp preload_runs_for_retry(runs_ids) do
    from(r in Run,
      where: r.id in ^runs_ids,
      preload: [
        :work_order,
        :dataclip,
        :starting_job,
        starting_trigger: [edges: :target_job]
      ]
    )
    |> Repo.all()
  end
end

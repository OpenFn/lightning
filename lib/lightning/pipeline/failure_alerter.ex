defmodule Lightning.FailureAlerter do
  @moduledoc """

  """
  use Oban.Worker,
    queue: :workflow_failures,
    max_attempts: 1

  alias Lightning.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "workflow_id" => workflow_id,
          "workflow_name" => workflow_name,
          "run_id" => run_id,
          "project_id" => project_id,
          "work_order_id" => work_order_id
        }
      }) do
    run = Repo.get!(Lightning.Invocation.Run, run_id)

    run_url = LightningWeb.RouteHelpers.show_run_path(project_id, run_id)

    {count, remaining, _, _, _} = ExRated.inspect_bucket(workflow_id, 60_000, 5)

    if(remaining == 0) do
      {:cancel, "Failure notification rate limit is reached"}
    else
      Lightning.Accounts.get_users_to_alert_for_project(%{id: project_id})
      |> Lightning.FailureEmail.deliver_failure_email(%{
        work_order_id: work_order_id,
        count: count + 1,
        run: run,
        workflow_name: workflow_name,
        workflow_id: workflow_id,
        run_url: run_url
      })
      |> case do
        {:ok, _metadata} ->
          # this increments the number of ops.
          ExRated.check_rate(workflow_id, 60_000, 5)
          :ok

        _ ->
          {:cancel, "Failure email was not sent"}
      end
    end
  end
end

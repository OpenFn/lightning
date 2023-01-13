defmodule Lightning.FailureAlerter do
  @moduledoc """

  """
  use Oban.Worker,
    queue: :workflow_failures

  alias Lightning.Repo
  alias Lightning.Accounts.{UserNotifier}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "workflow_id" => _workflow_id,
          "run_id" => run_id,
          "project_id" => project_id
        }
      }) do
    run = Repo.get!(Lightning.Invocation.Run, run_id)

    Lightning.Accounts.get_users_to_alert_for_project(%{id: project_id})
    |> UserNotifier.deliver_failure_email(%{id: run_id})

    :ok
  end
end

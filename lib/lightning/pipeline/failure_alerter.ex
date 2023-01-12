defmodule Lightning.FailureAlerter do
  @moduledoc """

  """
  use Oban.Worker,
    queue: :workflow_failures

  alias Lightning.Repo
  alias Lightning.Accounts.{User, UserNotifier}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{run_id: run_id}}) do
    run = Repo.get!(Lightning.Invocation.Run, run_id)

    # UserQuery.with_project_notifications(run.workflow.project_id)
    User
    |> Repo.all()
    |> UserNotifier.deliver_failure_email(%{id: run_id})

    :ok
  end
end

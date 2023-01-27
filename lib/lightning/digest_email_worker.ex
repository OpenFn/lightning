defmodule Lightning.DigestEmailWorker do
  @moduledoc false

  alias Lightning.Accounts.UserNotifier
  alias Lightning.Projects.ProjectUser
  alias Lightning.{Workflows, Workorders, Repo}

  import Ecto.Query, warn: false

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  @doc """
  Perform, when called with %{"type" => "daily_project_digest"} will find
  project_users with digest set to daily and send a digest email to them
  everyday at 10am
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "daily_project_digest"}}) do
    project_digest(:daily)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "weekly_project_digest"}}) do
    project_digest(:weekly)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "monthly_project_digest"}}) do
    project_digest(:monthly)
  end

  defp project_digest(digest) do
    project_users =
      from(pu in ProjectUser,
        where: pu.digest == ^digest,
        preload: [:project, :user]
      )
      |> Repo.all()

    Enum.each(project_users, fn pu ->
      digest_data =
        Workflows.get_workflows_for(pu.project)
        |> Enum.map(fn workflow ->
          Workorders.get_digest_data(workflow, digest)
        end)

      UserNotifier.deliver_project_digest(
        pu.user,
        pu.project,
        digest_data,
        digest
      )
    end)

    {:ok, %{project_users: project_users}}
  end
end

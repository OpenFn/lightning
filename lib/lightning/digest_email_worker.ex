defmodule Lightning.DigestEmailWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false

  alias Lightning.Accounts.UserNotifier
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.Workflows
  alias Lightning.WorkOrders.SearchParams

  @doc """
  Perform, when called with %{"type" => "daily_project_digest"} will find
  project_users with digest set to daily and send a digest email to them
  everyday at 10am
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "daily_project_digest"}}) do
    start_date = digest_to_date(:daily)
    end_date = Timex.now()
    project_digest(:daily, start_date, end_date)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "weekly_project_digest"}}) do
    start_date = digest_to_date(:weekly)
    end_date = Timex.now()
    project_digest(:weekly, start_date, end_date)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "monthly_project_digest"}}) do
    start_date = digest_to_date(:monthly)
    end_date = Timex.now()
    project_digest(:monthly, start_date, end_date)
  end

  defp project_digest(digest, start_date, end_date) do
    project_users =
      from(pu in ProjectUser,
        join: p in Project,
        on: p.id == pu.project_id and is_nil(p.scheduled_deletion),
        where: pu.digest == ^digest,
        preload: [:project, :user]
      )
      |> Repo.all()

    Enum.each(project_users, fn pu ->
      digest_data =
        Workflows.get_workflows_for(pu.project)
        |> Enum.map(fn workflow ->
          get_digest_data(workflow, start_date, end_date)
        end)

      UserNotifier.deliver_project_digest(
        digest_data,
        %{
          user: pu.user,
          project: pu.project,
          digest: digest,
          start_date: start_date,
          end_date: end_date
        }
      )
    end)

    {:ok, project_users}
  end

  def digest_to_date(digest) do
    case digest do
      :daily ->
        Timex.now() |> Timex.shift(days: -1)

      :weekly ->
        Timex.now() |> Timex.shift(days: -7)

      :monthly ->
        Timex.now() |> Timex.shift(months: -1)
    end
  end

  @doc """
  Get a map of counts for successful, rerun and failed Work Orders for a given
  workflow in a given timeframe.
  """
  def get_digest_data(workflow, start_date, end_date) do
    project = Projects.get_project!(workflow.project_id)

    successful_workorders =
      search_workorders(project, %{
        "success" => true,
        "date_after" => start_date,
        "date_before" => end_date,
        "workflow_id" => workflow.id
      })

    failed_workorders =
      search_workorders(project, %{
        "crashed" => true,
        "failed" => true,
        "pending" => true,
        "killed" => true,
        "date_after" => start_date,
        "date_before" => end_date,
        "workflow_id" => workflow.id
      })

    %{
      workflow: workflow,
      successful_workorders: successful_workorders.total_entries,
      failed_workorders: failed_workorders.total_entries
    }
  end

  defp search_workorders(project, params) do
    search_params = SearchParams.new(params)

    Lightning.Invocation.search_workorders(
      project,
      search_params
    )
  end
end

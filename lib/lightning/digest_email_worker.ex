defmodule Lightning.DigestEmailWorker do
  @moduledoc false

  alias Lightning.Projects
  alias Lightning.Accounts.UserNotifier
  alias Lightning.Projects.ProjectUser
  alias Lightning.{Workflows, Repo}

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
        Timex.now() |> Timex.beginning_of_day()

      :weekly ->
        Timex.now() |> Timex.shift(days: -7) |> Timex.beginning_of_week()

      :monthly ->
        Timex.now() |> Timex.shift(months: -1) |> Timex.beginning_of_month()
    end
  end

  @doc """
  Get a map of counts for successful, rerun and failed Workorders for a given workflow in a given timeframe.
  """
  def get_digest_data(workflow, start_date, end_date) do
    successful_workorders = successful_workorders(workflow, start_date, end_date)
    failed_workorders = failed_workorders(workflow, start_date, end_date)
    rerun_workorders = rerun_workorders(workflow, start_date, end_date)

    %{
      workflow: workflow,
      successful_workorders: successful_workorders.total_entries,
      rerun_workorders: rerun_workorders.total_entries,
      failed_workorders: failed_workorders.total_entries
    }
  end

  defp successful_workorders(workflow, start_date, end_date) do
    Lightning.Invocation.list_work_orders_for_project(
      Projects.get_project!(workflow.project_id),
      [
        status: [:success],
        search_fields: [:body, :log],
        search_term: "",
        workflow_id: workflow.id,
        date_after: start_date,
        date_before: end_date,
        wo_date_after: "",
        wo_date_before: ""
      ],
      %{}
    )
  end

  defp failed_workorders(workflow, start_date, end_date) do
    Lightning.Invocation.list_work_orders_for_project(
      Projects.get_project!(workflow.project_id),
      [
        status: [:failure, :crash, :timeout],
        search_fields: [:body, :log],
        search_term: "",
        workflow_id: workflow.id,
        date_after: start_date,
        date_before: end_date,
        wo_date_after: "",
        wo_date_before: ""
      ],
      %{}
    )
  end

  defp rerun_workorders(workflow, start_date, end_date) do
    probably_reruns =
      from(wo in Lightning.WorkOrder,
        join: workflow in Lightning.Workflows.Workflow,
        where: workflow.id == ^workflow.id,
        join: a in Lightning.Attempt,
        on: a.work_order_id == wo.id,
        join: ar in Lightning.AttemptRun,
        on: ar.attempt_id == a.id,
        join: r in Lightning.Invocation.Run,
        on: r.id == ar.run_id,
        where:
          r.exit_code == 0 and r.finished_at >= ^start_date and
            r.finished_at < ^end_date,
        group_by: [wo.id, wo.workflow_id],
        order_by: [desc: wo.inserted_at],
        select: wo.id
      )

    from(wo in Lightning.WorkOrder,
      where:
        wo.workflow_id == ^workflow.id and wo.id in subquery(probably_reruns),
      join: a in Lightning.Attempt,
      on: a.work_order_id == wo.id,
      join: ar in Lightning.AttemptRun,
      on: ar.attempt_id == a.id,
      join: r in Lightning.Invocation.Run,
      on: r.id == ar.run_id,
      where: r.exit_code != 0
    )
    |> Repo.paginate(%{})
  end
end

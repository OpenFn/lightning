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

    %{
      notified: notified_users,
      skipped: skipped_users,
      suppressed: suppressed_users,
      failed: failed_users
    } =
      project_users
      |> Enum.group_by(& &1.project.id)
      |> Enum.reduce(
        %{notified: [], skipped: [], suppressed: [], failed: []},
        fn {_project_id, project_users}, acc ->
          [%{project: project} | _other] = project_users
          workflows = Workflows.get_workflows_for(project)

          if length(workflows) > 0 do
            project_digest_data =
              Enum.map(workflows, fn workflow ->
                get_digest_data(workflow, start_date, end_date)
              end)

            project_users
            |> deliver_digests(
              project_digest_data,
              digest,
              start_date,
              end_date
            )
            |> Map.merge(acc, fn _outcome, delivered, so_far ->
              so_far ++ delivered
            end)
          else
            Map.update!(acc, :skipped, &(&1 ++ project_users))
          end
        end
      )

    {:ok,
     %{
       notified_users: notified_users,
       skipped_users: skipped_users,
       suppressed_users: suppressed_users,
       failed_users: failed_users
     }}
  end

  # Sorts a project's digest subscribers by what became of their digest:
  # `:notified` for one that was sent, `:suppressed` for one withheld, and
  # `:failed` for one the mailer could not deliver.
  #
  # `UserNotifier.deliver_project_digest/2` refuses anyone who may not be sent
  # the project's contents, and someone refused has not been notified. They are
  # not `skipped` either: that list means the project had no workflows to report
  # on, so it says nothing about the recipient. A failed send is kept apart from
  # both — reporting it as a notification would make a mail outage read as a
  # successful run.
  defp deliver_digests(
         project_users,
         project_digest_data,
         digest,
         start_date,
         end_date
       ) do
    empty = %{notified: [], suppressed: [], failed: []}

    project_users
    |> Enum.map(fn pu ->
      result =
        UserNotifier.deliver_project_digest(
          project_digest_data,
          %{
            user: pu.user,
            project: pu.project,
            digest: digest,
            start_date: start_date,
            end_date: end_date
          }
        )

      {outcome(result), pu}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> then(&Map.merge(empty, &1))
  end

  defp outcome({:ok, :suppressed}), do: :suppressed
  defp outcome({:ok, _email}), do: :notified
  defp outcome(_error), do: :failed

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

    successful_count =
      count_workorders(project, %{
        "success" => true,
        "date_after" => start_date,
        "date_before" => end_date,
        "workflow_id" => workflow.id
      })

    failed_count =
      count_workorders(
        project,
        build_failed_status_params(%{
          "date_after" => start_date,
          "date_before" => end_date,
          "workflow_id" => workflow.id
        })
      )

    %{
      workflow: workflow,
      successful_workorders: successful_count,
      failed_workorders: failed_count
    }
  end

  # Builds search parameters for failed workorders by including all failure states.
  # This ensures new failure states added to Run.final_states() are automatically included.
  defp build_failed_status_params(base_params) do
    failure_states = Lightning.Run.failure_states()

    failure_params =
      failure_states
      |> Enum.map(&{Atom.to_string(&1), true})
      |> Enum.into(%{})

    Map.merge(base_params, failure_params)
  end

  defp count_workorders(project, params) do
    search_params = SearchParams.new(params)

    Lightning.Invocation.count_workorders(
      project,
      search_params
    )
  end
end

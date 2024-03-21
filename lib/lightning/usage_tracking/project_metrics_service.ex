defmodule Lightning.UsageTracking.ProjectMetricsService do
  @moduledoc """
  Builds project-related metrics.


  """
  import Ecto.Query

  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.UsageTracking.UserService
  alias Lightning.UsageTracking.WorkflowMetricsService

  def find_eligible_projects(date) do
    report_time = report_date_as_time(date)

    query =
      from p in Project,
        where: p.inserted_at <= ^report_time,
        preload: [:users, [workflows: [:jobs, runs: [steps: [:job]]]]]

    query |> Repo.all()
  end

  def generate_metrics(project, cleartext_enabled, date) do
    %Project{id: id, users: users} = project

    %{
      no_of_active_users: UserService.no_of_active_users(date, users),
      no_of_users: UserService.no_of_users(date, users),
      workflows: instrument_workflows(project, cleartext_enabled, date)
    }
    |> Map.merge(instrument_identity(id, cleartext_enabled))
  end

  defp instrument_identity(identity, false = _cleartext_enabled) do
    %{
      cleartext_uuid: nil,
      hashed_uuid: identity |> build_hash()
    }
  end

  defp instrument_identity(identity, true = _cleartext_enabled) do
    identity
    |> instrument_identity(false)
    |> Map.merge(%{cleartext_uuid: identity})
  end

  defp build_hash(uuid), do: Base.encode16(:crypto.hash(:sha256, uuid))

  defp instrument_workflows(project, cleartext_enabled, date) do
    project.workflows
    |> WorkflowMetricsService.find_eligible_workflows(date)
    |> Enum.map(fn workflow ->
      WorkflowMetricsService.generate_metrics(workflow, cleartext_enabled, date)
    end)
  end

  defp report_date_as_time(date) do
    {:ok, datetime, _offset} = "#{date}T23:59:59Z" |> DateTime.from_iso8601()

    datetime
  end
end

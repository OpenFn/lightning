defmodule Lightning.UsageTracking.ReportData do
  @moduledoc """
  Builds data set for submission to Usage Tracker


  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.UsageTracking.Configuration
  alias Lightning.Workflows.Workflow

  @lightning_version Lightning.MixProject.project()[:version]

  def generate(configuration, cleartext_enabled) do
    %{
      generated_at: DateTime.utc_now(),
      instance: instrument_instance(configuration, cleartext_enabled),
      projects: instrument_projects(cleartext_enabled),
      version: "1"
    }
  end

  defp instrument_instance(configuration, cleartext_enabled) do
    %Configuration{instance_id: instance_id} = configuration

    instance_id
    |> instrument_identity(cleartext_enabled)
    |> Map.merge(%{
      no_of_users: no_of_users(),
      operating_system: operating_system_name(),
      version: @lightning_version
    })
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

  defp no_of_users do
    User |> where(disabled: false) |> Repo.aggregate(:count)
  end

  defp operating_system_name do
    {_os_family, os_name} = :os.type()

    os_name |> Atom.to_string()
  end

  defp instrument_projects(cleartext_enabled) do
    Repo.all(
      from p in Project,
        preload: [:users, [workflows: [:jobs, runs: [:steps]]]]
    )
    |> Enum.map(&instrument_project(&1, cleartext_enabled))
  end

  defp instrument_project(project, cleartext_enabled) do
    %Project{id: id, users: users, workflows: workflows} = project

    instrument_identity(id, cleartext_enabled)
    |> Map.merge(%{
      no_of_users: count(users),
      workflows:
        workflows
        |> Enum.map(&instrument_workflow(&1, cleartext_enabled))
    })
  end

  defp instrument_workflow(workflow, cleartext_enabled) do
    %Workflow{id: id, jobs: jobs, runs: runs} = workflow

    instrument_identity(id, cleartext_enabled)
    |> Map.merge(%{
      no_of_jobs: count(jobs),
      no_of_runs: count(runs),
      no_of_steps: no_of_steps_for(runs)
    })
  end

  defp no_of_steps_for(runs) do
    runs
    |> Enum.reduce(0, fn run, acc -> acc + count(run.steps) end)
  end

  defp count(collection), do: collection |> Enum.count()
end

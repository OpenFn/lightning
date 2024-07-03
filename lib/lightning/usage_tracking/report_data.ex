defmodule Lightning.UsageTracking.ReportData do
  @moduledoc """
  Builds data set for submission to Usage Tracker


  """
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.UsageTracking.ProjectMetricsService
  alias Lightning.UsageTracking.UserService

  def generate(configuration, cleartext_enabled, date) do
    %{
      generated_at: DateTime.utc_now(),
      instance: instrument_instance(configuration, cleartext_enabled, date),
      projects: instrument_projects(cleartext_enabled, date),
      report_date: date,
      version: "2"
    }
  end

  defp instrument_instance(configuration, cleartext_enabled, date) do
    %DailyReportConfiguration{instance_id: instance_id} = configuration

    instance_id
    |> instrument_identity(cleartext_enabled)
    |> Map.merge(%{
      no_of_active_users: UserService.no_of_active_users(date),
      no_of_users: UserService.no_of_users(date),
      operating_system: operating_system_name(),
      version: UsageTracking.lightning_version()
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

  defp operating_system_name do
    {_os_family, os_name} = :os.type()

    os_name |> Atom.to_string()
  end

  defp instrument_projects(cleartext_enabled, date) do
    date
    |> ProjectMetricsService.find_eligible_projects()
    |> Enum.map(fn project ->
      ProjectMetricsService.generate_metrics(project, cleartext_enabled, date)
    end)
  end
end

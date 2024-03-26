defmodule Lightning.UsageTracking do
  @moduledoc """
  The UsageTracking context.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserToken
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ReportWorker
  alias Lightning.Workflows.Workflow

  @lightning_version Lightning.MixProject.project()[:version]

  def enable_daily_report(enabled_at) do
    start_reporting_after = DateTime.to_date(enabled_at)

    case Repo.one(DailyReportConfiguration) do
      config = %{tracking_enabled_at: nil, start_reporting_after: nil} ->
        enable_config(config, enabled_at, start_reporting_after)

      nil ->
        create_enabled_config(enabled_at, start_reporting_after)

      config ->
        config
    end
  end

  def disable_daily_report do
    if config = Repo.one(DailyReportConfiguration) do
      config
      |> DailyReportConfiguration.changeset(%{
        tracking_enabled_at: nil,
        start_reporting_after: nil
      })
      |> Repo.update!()
    end
  end

  defp create_enabled_config(enabled_at, start_reporting_after) do
    %DailyReportConfiguration{
      tracking_enabled_at: enabled_at,
      start_reporting_after: start_reporting_after
    }
    |> Repo.insert!()
  end

  defp enable_config(config, enabled_at, start_reporting_after) do
    config
    |> DailyReportConfiguration.changeset(%{
      tracking_enabled_at: enabled_at,
      start_reporting_after: start_reporting_after
    })
    |> Repo.update!()
  end

  def start_reporting_after(date) do
    case Repo.one(DailyReportConfiguration) do
      %{tracking_enabled_at: nil} ->
        :error

      nil ->
        :error

      config ->
        config
        |> DailyReportConfiguration.changeset(%{start_reporting_after: date})
        |> Repo.update!()

        :ok
    end
  end

  def reportable_dates(start_after, today, batch_size) do
    case Date.diff(today, start_after) do
      diff when diff > 2 ->
        build_reportable_dates(start_after, today, batch_size)

      _too_small_a_diff ->
        []
    end
  end

  defp build_reportable_dates(start_after, today, batch_size) do
    start_after
    |> candidate_dates(today)
    |> remove_existing_dates()
    |> Enum.sort(Date)
    |> Enum.take(batch_size)
  end

  defp candidate_dates(start_after, today) do
    start_date = start_after |> Date.add(1)
    end_date = today |> Date.add(-1)

    Date.range(start_date, end_date)
  end

  defp remove_existing_dates(candidate_dates) do
    candidate_dates
    |> MapSet.new()
    |> MapSet.difference(existing_report_dates(candidate_dates))
  end

  defp existing_report_dates(candidate_dates) do
    [start_date, end_date] = find_boundaries(candidate_dates)

    query =
      from r in Report,
        where: r.report_date >= ^start_date and r.report_date < ^end_date,
        select: r.report_date,
        order_by: [asc: r.report_date]

    Repo.all(query) |> MapSet.new()
  end

  defp find_boundaries(date_range) do
    date_range
    |> Enum.to_list()
    |> then(fn [start | other_dates] -> [start, other_dates] end)
    |> then(fn [start, dates] -> [start, hd(Enum.reverse(dates))] end)
  end

  def enqueue_reports(true = _enabled, reference_time, batch_size) do
    %{start_reporting_after: start_after} =
      enable_daily_report(reference_time)

    today = DateTime.to_date(reference_time)

    start_after
    |> reportable_dates(today, batch_size)
    |> update_configuration()
    |> Enum.each(&enqueue/1)

    :ok
  end

  def enqueue_reports(false = _enabled, _reference_time, _batch_size) do
    disable_daily_report()

    :ok
  end

  defp update_configuration([earliest_report_date | _other] = dates) do
    earliest_report_date
    |> Date.add(-1)
    |> start_reporting_after()

    dates
  end

  defp update_configuration([] = dates), do: dates

  defp enqueue(date) do
    Oban.insert(Lightning.Oban, ReportWorker.new(%{date: date}))
  end

  def find_enabled_daily_report_config do
    case Repo.one(DailyReportConfiguration) do
      %{tracking_enabled_at: nil} -> nil
      possible_config -> possible_config
    end
  end

  def find_eligible_projects(date) do
    report_time = report_date_as_time(date)

    query =
      from p in Project,
        where: p.inserted_at <= ^report_time,
        preload: [:users, [workflows: [:jobs, runs: [steps: [:job]]]]]

    query |> Repo.all()
  end

  defp report_date_as_time(date) do
    {:ok, datetime, _offset} = "#{date}T23:59:59Z" |> DateTime.from_iso8601()

    datetime
  end

  def generate_metrics(%Project{} = project, cleartext_enabled, date) do
    %Project{id: id, users: users} = project

    %{
      no_of_active_users: active_users(date, users) |> Repo.aggregate(:count),
      no_of_users: existing_users(date, users) |> Repo.aggregate(:count),
      workflows: instrument_workflows(project, cleartext_enabled, date)
    }
    |> Map.merge(instrument_identity(id, cleartext_enabled))
  end

  def generate_metrics(%Workflow{} = workflow, cleartext_enabled, date) do
    runs = finished_runs(workflow.runs, date)
    steps = finished_steps(workflow.runs, date)
    active_jobs = unique_jobs(steps, date)

    %{
      no_of_active_jobs: Enum.count(active_jobs),
      no_of_jobs: Enum.count(workflow.jobs),
      no_of_runs: Enum.count(runs),
      no_of_steps: Enum.count(steps)
    }
    |> Map.merge(instrument_identity(workflow.id, cleartext_enabled))
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
    |> find_eligible_workflows(date)
    |> Enum.map(fn workflow ->
      generate_metrics(workflow, cleartext_enabled, date)
    end)
  end

  def find_eligible_workflows(workflows, date) do
    workflows
    |> Enum.filter(fn workflow -> eligible_workflow?(workflow, date) end)
  end

  defp eligible_workflow?(%{deleted_at: nil, inserted_at: inserted_at}, date) do
    Date.compare(inserted_at, date) != :gt
  end

  defp eligible_workflow?(
         %{deleted_at: deleted_at, inserted_at: inserted_at},
         date
       ) do
    Date.compare(inserted_at, date) != :gt &&
      Date.compare(deleted_at, date) == :gt
  end

  def finished_runs(all_runs, date) do
    all_runs
    |> finished_on(date)
  end

  def finished_steps(runs, date) do
    runs
    |> Enum.flat_map(& &1.steps)
    |> finished_on(date)
  end

  def unique_jobs(steps, date) do
    steps
    |> finished_on(date)
    |> Enum.map(& &1.job)
    |> Enum.uniq_by(& &1.id)
  end

  defp finished_on(collection, date) do
    collection
    |> Enum.filter(fn
      %{finished_at: nil} ->
        false

      %{finished_at: finished_at} ->
        finished_at |> DateTime.to_date() == date
    end)
  end

  def existing_users(date) do
    report_time = report_date_as_time(date)

    from u in User, where: u.inserted_at <= ^report_time
  end

  def existing_users(date, user_list) do
    list_ids = user_list |> Enum.map(& &1.id)

    from eu in existing_users(date), where: eu.id in ^list_ids
  end

  def active_users(date) do
    report_time = report_date_as_time(date)

    {:ok, threshold_time, _offset} =
      date
      |> Date.add(-90)
      |> then(&"#{&1}T23:59:59Z")
      |> DateTime.from_iso8601()

    from eu in existing_users(date),
      distinct: eu.id,
      join: ut in UserToken,
      on: ut.user_id == eu.id,
      where: ut.context == "session",
      where: ut.inserted_at > ^threshold_time and ut.inserted_at <= ^report_time
  end

  def active_users(date, user_list) do
    list_ids = user_list |> Enum.map(& &1.id)

    from au in active_users(date), where: au.id in ^list_ids
  end

  def generate_report_data(configuration, cleartext_enabled, date) do
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
      no_of_active_users: active_users(date) |> Repo.aggregate(:count),
      no_of_users: existing_users(date) |> Repo.aggregate(:count),
      operating_system: operating_system_name(),
      version: @lightning_version
    })
  end

  defp operating_system_name do
    {_os_family, os_name} = :os.type()

    os_name |> Atom.to_string()
  end

  defp instrument_projects(cleartext_enabled, date) do
    date
    |> find_eligible_projects()
    |> Enum.map(fn project ->
      generate_metrics(project, cleartext_enabled, date)
    end)
  end
end

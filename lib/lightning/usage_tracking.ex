defmodule Lightning.UsageTracking do
  @moduledoc """
  The UsageTracking context.
  """
  import Ecto.Query

  alias Lightning.Helpers
  alias Lightning.Repo
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.UsageTracking.GithubClient
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ReportData
  alias Lightning.UsageTracking.ReportWorker

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
    start_reporting_after = Date.add(earliest_report_date, -1)

    start_reporting_after(start_reporting_after)

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

  def insert_report(config, cleartext_uuids_enabled, date) do
    data = ReportData.generate(config, cleartext_uuids_enabled, date)

    %Report{}
    |> Report.changeset(%{
      data: data,
      report_date: date,
      submitted: false,
      submitted_at: nil
    })
    |> Repo.insert()
  end

  def update_report_submission!(:ok = _state, report) do
    report
    |> Report.changeset(%{
      submitted: true,
      submitted_at: DateTime.utc_now()
    })
    |> Repo.update!()
  end

  def update_report_submission!(:error = _state, report) do
    report
    |> Report.changeset(%{
      submitted: false,
      submitted_at: nil
    })
    |> Repo.update!()
  end

  def lightning_version do
    %{image: image, commit: commit, spec_version: vsn} = Helpers.version_data()

    "#{vsn}:#{image_for_submission(image, vsn)}:#{commit_for_submission(commit)}"
  end

  defp commit_for_submission(commit) do
    commit
    |> GithubClient.open_fn_commit?()
    |> then(fn
      true -> commit
      _not_true -> "sanitised"
    end)
  end

  defp image_for_submission(version, version) do
    "match"
  end

  defp image_for_submission("edge" = _image, _spec_version), do: "edge"
  defp image_for_submission(_image, _spec_version), do: "other"
end

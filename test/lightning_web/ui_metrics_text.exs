defmodule LightningWeb.UiMetricsTest do
  use Lightning.DataCase, async: false

  alias LightningWeb.UiMetrics

  import ExUnit.CaptureLog

  describe ".job_editor_metrics" do
    setup do
      current_log_level = Logger.level()
      Logger.configure(level: :info)

      on_exit(fn ->
        Logger.configure(level: current_log_level)
      end)

      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        true
      end)

      :ok
    end

    test "logs the job editor metrics passed in" do
      job = insert(:job)

      metrics = [
        %{
          "event" => "mount to 1st render",
          "start" => 1737635739914,
          "end" => 1737635808890
        },
        %{
          "event" => "render before fetching metadata",
          "start" => 1737637606066,
          "end" => 1737637623051
        },
      ]

      expected_entry_1 =
        job_editor_log_regex(
          job_id: job.id,
          event: "mount to 1st render",
          start: 1737635739914,
          end: 1737635808890
        )

      expected_entry_2 =
        job_editor_log_regex(
          job_id: job.id,
          event: "render before fetching metadata",
          start: 1737639109889,
          end: 1737639132505
        )

      fun = fn ->
        UiMetrics.log_job_editor_metrics(job, metrics)
      end

      assert capture_log([level: :info], fun) =~ expected_entry_1
      assert capture_log(fun) =~ expected_entry_2
    end

    def job_editor_log_regex(opts \\ []) do
      job_id = Keyword.fetch!(opts, :job_id)

      event = Keyword.fetch!(opts, :event)

      start_time =
        opts
        |> Keyword.fetch!(:start)
        |> DateTime.from_unix!(:millisecond)

      end_time =
          opts
          |> Keyword.fetch!(:end)
          |> DateTime.from_unix!(:millisecond)

      duration = DateTime.diff(end_time, start_time, :millisecond)

      log_line = 
        "UiMetrics: \\[JobEditor\\] " <>
        "event=`#{event}` " <>
        "job_id=#{job_id} " <>
        "start_time=#{DateTime.to_iso8601(start_time)} " <>
        "end_time=#{DateTime.to_iso8601(end_time)} " <>
        "duration=#{duration} ms"

      ~r/#{log_line}/
    end
      
  end
end

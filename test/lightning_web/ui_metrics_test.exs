defmodule LightningWeb.UiMetricsTest do
  use Lightning.DataCase, async: false

  alias LightningWeb.UiMetrics

  import ExUnit.CaptureLog

  setup do
    current_log_level = Logger.level()
    Logger.configure(level: :info)

    on_exit(fn ->
      Logger.configure(level: current_log_level)
    end)
  end

  describe "log_job_editor_metrics/2" do
    setup do
      metrics = [
        %{
          "event" => "mount to 1st render",
          "start" => 1_737_635_739_914,
          "end" => 1_737_635_808_890
        },
        %{
          "event" => "render before fetching metadata",
          "start" => 1_737_637_606_066,
          "end" => 1_737_637_623_051
        }
      ]

      job = insert(:job)

      snapshot_job = build(:snapshot_job, id: job.id)

      %{job: job, metrics: metrics, snapshot_job: snapshot_job}
    end

    test "logs the job editor metrics when a job is provided", %{
      job: job,
      metrics: metrics
    } do
      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        true
      end)

      expected_entry_1 =
        job_editor_log_regex(
          job: job,
          event: "mount to 1st render",
          start: 1_737_635_739_914,
          end: 1_737_635_808_890
        )

      expected_entry_2 =
        job_editor_log_regex(
          job: job,
          event: "render before fetching metadata",
          start: 1_737_637_606_066,
          end: 1_737_637_623_051
        )

      fun = fn -> UiMetrics.log_job_editor_metrics(job, metrics) end

      assert capture_log(fun) =~ expected_entry_1
      assert capture_log(fun) =~ expected_entry_2
    end

    test "logs the job editor metrics when a snapshot job is provided", %{
      job: job,
      metrics: metrics,
      snapshot_job: snapshot_job
    } do
      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        true
      end)

      expected_entry_1 =
        job_editor_log_regex(
          job: job,
          event: "mount to 1st render",
          start: 1_737_635_739_914,
          end: 1_737_635_808_890
        )

      expected_entry_2 =
        job_editor_log_regex(
          job: job,
          event: "render before fetching metadata",
          start: 1_737_637_606_066,
          end: 1_737_637_623_051
        )

      fun = fn -> UiMetrics.log_job_editor_metrics(snapshot_job, metrics) end

      assert capture_log(fun) =~ expected_entry_1
      assert capture_log(fun) =~ expected_entry_2
    end

    test "logs the metrics when the workflow for the snapshot job is missing", %{
      metrics: metrics
    } do
      snapshot_job = build(:snapshot_job)

      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        true
      end)

      expected_entry_1 =
        job_editor_no_workflow_log_regex(
          job: snapshot_job,
          event: "mount to 1st render",
          start: 1_737_635_739_914,
          end: 1_737_635_808_890
        )

      expected_entry_2 =
        job_editor_no_workflow_log_regex(
          job: snapshot_job,
          event: "render before fetching metadata",
          start: 1_737_637_606_066,
          end: 1_737_637_623_051
        )

      fun = fn -> UiMetrics.log_job_editor_metrics(snapshot_job, metrics) end

      assert capture_log(fun) =~ expected_entry_1
      assert capture_log(fun) =~ expected_entry_2
    end

    test "does not write metrics to the log if logging is disabled", %{
      job: job,
      metrics: metrics
    } do
      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        false
      end)

      fun = fn -> UiMetrics.log_job_editor_metrics(job, metrics) end

      refute capture_log(fun) =~ ~r/UiMetrics/
    end

    def job_editor_log_regex(opts \\ []) do
      %{id: job_id, workflow_id: workflow_id} = Keyword.fetch!(opts, :job)

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
          "workflow_id=#{workflow_id} " <>
          "job_id=#{job_id} " <>
          "start_time=#{DateTime.to_iso8601(start_time)} " <>
          "end_time=#{DateTime.to_iso8601(end_time)} " <>
          "duration=#{duration} ms"

      ~r/#{log_line}/
    end

    def job_editor_no_workflow_log_regex(opts \\ []) do
      %{id: job_id} = Keyword.fetch!(opts, :job)

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
          "workflow_id=unknown " <>
          "job_id=#{job_id} " <>
          "start_time=#{DateTime.to_iso8601(start_time)} " <>
          "end_time=#{DateTime.to_iso8601(end_time)} " <>
          "duration=#{duration} ms"

      ~r/#{log_line}/
    end
  end

  describe "log_workflow_editor_metrics/2" do
    setup do
      metrics = [
        %{
          "event" => "workflow-params load",
          "start" => 1_737_635_739_914,
          "end" => 1_737_635_808_890
        },
        %{
          "event" => "something else important",
          "start" => 1_737_637_606_066,
          "end" => 1_737_637_623_051
        }
      ]

      workflow = insert(:workflow)

      %{metrics: metrics, workflow: workflow}
    end

    test "logs the workflow metrics provided", %{
      metrics: metrics,
      workflow: workflow
    } do
      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        true
      end)

      expected_entry_1 =
        workflow_editor_log_regex(
          workflow: workflow,
          event: "workflow-params load",
          start: 1_737_635_739_914,
          end: 1_737_635_808_890
        )

      expected_entry_2 =
        workflow_editor_log_regex(
          workflow: workflow,
          event: "something else important",
          start: 1_737_637_606_066,
          end: 1_737_637_623_051
        )

      fun = fn -> UiMetrics.log_workflow_editor_metrics(workflow, metrics) end

      assert capture_log(fun) =~ expected_entry_1
      assert capture_log(fun) =~ expected_entry_2
    end

    test "does not write metrics to the log if logging is disabled", %{
      metrics: metrics,
      workflow: workflow
    } do
      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        false
      end)

      fun = fn -> UiMetrics.log_workflow_editor_metrics(workflow, metrics) end

      refute capture_log(fun) =~ ~r/UiMetrics/
    end

    def workflow_editor_log_regex(opts \\ []) do
      %{id: workflow_id} = Keyword.fetch!(opts, :workflow)

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
        "UiMetrics: \\[WorkflowEditor\\] " <>
          "event=`#{event}` " <>
          "workflow_id=#{workflow_id} " <>
          "start_time=#{DateTime.to_iso8601(start_time)} " <>
          "end_time=#{DateTime.to_iso8601(end_time)} " <>
          "duration=#{duration} ms"

      ~r/#{log_line}/
    end
  end
end

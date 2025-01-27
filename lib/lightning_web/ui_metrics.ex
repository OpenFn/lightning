defmodule LightningWeb.UiMetrics do
  @moduledoc """
  A temporary measure to allow WorkflowEditor and JobEditor UI components to 
  report selected metrics and have these logged.
  """
  require Logger

  def log_job_editor_metrics(job, metrics) do
    if Lightning.Config.ui_metrics_tracking_enabled?() do
      Enum.each(metrics, fn metric ->
        metric
        |> enrich_job_editor_metric(job)
        |> create_job_editor_log_line()
        |> Logger.info()
      end)
    end
  end

  defp enrich_job_editor_metric(metric, job) do
    %{id: job_id, workflow_id: workflow_id} = job

    metric
    |> common_enrichment()
    |> Map.merge(%{
      "workflow_id" => workflow_id,
      "job_id" => job_id
    })
  end

  defp create_job_editor_log_line(metric) do
    %{
      "event" => event,
      "workflow_id" => workflow_id,
      "job_id" => job_id,
      "start_time" => start_time,
      "end_time" => end_time,
      "duration" => duration
    } = metric

    "UiMetrics: [JobEditor] " <>
      "event=`#{event}` " <>
      "workflow_id=#{workflow_id} " <>
      "job_id=#{job_id} " <>
      "start_time=#{start_time} " <>
      "end_time=#{end_time} " <>
      "duration=#{duration} ms"
  end

  def log_workflow_editor_metrics(workflow, metrics) do
    if Lightning.Config.ui_metrics_tracking_enabled?() do
      Enum.each(metrics, fn metric ->
        metric
        |> enrich_workflow_editor_metric(workflow)
        |> create_workflow_editor_log_line()
        |> Logger.info()
      end)
    end
  end

  defp enrich_workflow_editor_metric(metric, %{id: workflow_id}) do
    metric |> common_enrichment() |> Map.put("workflow_id", workflow_id)
  end

  defp create_workflow_editor_log_line(metric) do
    %{
      "event" => event,
      "workflow_id" => workflow_id,
      "start_time" => start_time,
      "end_time" => end_time,
      "duration" => duration
    } = metric

    "UiMetrics: [WorkflowEditor] " <>
      "event=`#{event}` " <>
      "workflow_id=#{workflow_id} " <>
      "start_time=#{start_time} " <>
      "end_time=#{end_time} " <>
      "duration=#{duration} ms"
  end

  defp common_enrichment(%{"start" => start_ts, "end" => end_ts} = metric) do
    metric
    |> Map.merge(%{
      "start_time" => convert_ts(start_ts),
      "end_time" => convert_ts(end_ts),
      "duration" => end_ts - start_ts
    })
  end

  defp convert_ts(ts) do
    ts |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
  end
end

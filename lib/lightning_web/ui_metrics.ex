defmodule LightningWeb.UiMetrics do
  require Logger

  def log_job_editor_metrics(%{id: job_id}, metrics) do
    Logger.info "Sigh"
    Enum.each(metrics, fn metric ->
      metric |> enrich_job_editor_metric(job_id) |> log_job_editor_metric()
    end)
  end

  defp enrich_job_editor_metric(_metric, _job_id) do
    # metric
    # |> Map.put("job_id", job_id)
  end

  defp log_job_editor_metric(_metric) do
    Logger.info "aargh"
  end
end

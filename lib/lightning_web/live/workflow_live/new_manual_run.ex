defmodule LightningWeb.WorkflowLive.NewManualRun do
  @moduledoc """
  This module helps with the rewrite of the Workflow editor.
  It implements the backend API for the React frontend.
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Workflows.Job

  @latest_dataclips_limit 5

  def get_selectable_dataclips(socket, job_id) do
    dataclips =
      Invocation.list_dataclips_for_job(
        %Job{id: job_id},
        @latest_dataclips_limit
      )
    push_event(socket, "current-selectable-dataclips", %{dataclips: dataclips})
  end

  def search_selectable_dataclips(socket, job_id, search_text) do
    filters = get_dataclips_filters(search_text)

    dataclips =
      Invocation.list_dataclips_for_job(
        %Job{id: job_id},
        filters,
        @latest_dataclips_limit
      )
    push_event(socket, "searched-selectable-dataclips", %{dataclips: dataclips})
  end

  defp get_dataclips_filters(search_text) do
    search_text
    |> String.split()
    |> Enum.reduce(Map.new(), fn text, filters ->
      if text in Dataclip.source_types() do
        Map.put(filters, :type, text)
      else
        with :error <- Date.from_iso8601(text) do
          DateTime.from_iso8601(text)
        end
        |> case do
          {:ok, %Date{} = date} -> Map.put(filters, :date, date)
          {:ok, datetime} -> Map.put(filters, :datetime, datetime)
          :error -> filters
        end
      end
    end)
  end
end

defmodule LightningWeb.WorkflowLive.NewManualRun do
  @moduledoc """
  This module helps with the rewrite of the Workflow editor.
  It implements the backend API for the React frontend.
  """
  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias LightningWeb.WorkflowLive.Edit
  alias Lightning.Workflows.Job

  @dataclip_types MapSet.new(Dataclip.source_types(), &to_string/1)

  def get_selectable_dataclips(job_id, limit) do
    dataclips =
      Invocation.list_dataclips_for_job(%Job{id: job_id}, limit)

    %Edit.PushEvent{
      key: "current-selectable-dataclips",
      payload: %{dataclips: dataclips}
    }
  end

  def search_selectable_dataclips(job_id, search_text, limit, offset) do
    filters = get_dataclips_filters(search_text)

    dataclips =
      Invocation.list_dataclips_for_job(
        %Job{id: job_id},
        filters,
        limit,
        offset
      )

    %Edit.PushEvent{
      key: "searched-selectable-dataclips",
      payload: %{dataclips: dataclips}
    }
  end

  defp get_dataclips_filters(search_text) do
    search_text
    |> String.split()
    |> Enum.reduce(Map.new(), fn text, filters ->
      if MapSet.member?(@dataclip_types, text) do
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

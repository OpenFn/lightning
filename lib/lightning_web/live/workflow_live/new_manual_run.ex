defmodule LightningWeb.WorkflowLive.NewManualRun do
  @moduledoc """
  This module helps with the rewrite of the Workflow editor.
  It implements the backend API for the React frontend.
  """
  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Workflows.Job

  @dataclip_types MapSet.new(Dataclip.source_types(), &to_string/1)

  def get_selectable_dataclips(job_id, limit) do
    dataclips =
      Invocation.list_dataclips_for_job(%Job{id: job_id}, limit)

    %{dataclips: dataclips}
  end

  def search_selectable_dataclips(job_id, search_text, limit, offset) do
    case get_dataclips_filters(search_text) do
      {:ok, filters} ->
        dataclips =
          Invocation.list_dataclips_for_job(
            %Job{id: job_id},
            filters,
            limit,
            offset
          )

        %{dataclips: dataclips}

      {:error, reason} ->
        %{error: reason}
    end
  end

  defp get_dataclips_filters(search_text) do
    search_text
    |> String.split()
    |> Enum.reduce(Map.new(), fn text, filters ->
      with {:error, _reason} <- Date.from_iso8601(text),
           {:error, _reason} <- DateTime.from_iso8601(text),
           true <-
             MapSet.member?(@dataclip_types, text) || {:error, :invalid_type} do
        {:ok, Map.put(filters, :type, text)}
      end
      |> case do
        {:ok, %Date{} = date} -> {:ok, Map.put(filters, :date, date)}
        {:ok, datetime, _tz} -> {:ok, Map.put(filters, :datetime, datetime)}
        error -> error
      end
    end)
  end
end

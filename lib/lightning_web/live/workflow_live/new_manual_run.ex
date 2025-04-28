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

  def get_dataclips_filters(search_text) do
    search_text = String.replace(search_text, ": ", ":")

    search_text
    |> String.split()
    |> Enum.reduce(Map.new(), fn text, filters ->
      case parse_param(text) do
        {:ok, %Date{} = date} -> {:ok, Map.put(filters, :date, date)}
        {:ok, uuid} when is_binary(uuid) -> {:ok, Map.put(filters, :id, uuid)}
        {:ok, type} when is_atom(type) -> {:ok, Map.put(filters, :type, type)}
        {:ok, {:after, datetime}} -> {:ok, Map.put(filters, :after, datetime)}
        {:ok, datetime} -> {:ok, Map.put(filters, :datetime, datetime)}
        result -> result
      end
    end)
  end

  defp parse_param("after:" <> param) do
    case Date.from_iso8601(param) do
      {:ok, date} ->
        {:ok,
         {:after, Date.add(date, -1) |> NaiveDateTime.new!(~T[23:59:59.999999])}}

      {:error, _reason} ->
        with {:ok, datetime} <- NaiveDateTime.from_iso8601(param) do
          {:ok, {:after, datetime}}
        end
    end
  end

  defp parse_param("date:" <> param), do: Date.from_iso8601(param)
  defp parse_param("datetime:" <> param), do: NaiveDateTime.from_iso8601(param)

  defp parse_param("id:" <> param) do
    with :error <- Ecto.UUID.cast(param), do: {:error, :invalid_uuid}
  end

  defp parse_param("type:" <> param) do
    with true <-
           MapSet.member?(@dataclip_types, param) || {:error, :invalid_type} do
      {:ok, String.to_existing_atom(param)}
    end
  end

  defp parse_param(text) do
    with {:error, _reason} <- Date.from_iso8601(text),
         {:error, _reason} <- NaiveDateTime.from_iso8601(text),
         :error <- Ecto.UUID.cast(text),
         true <- MapSet.member?(@dataclip_types, text) || {:error, :invalid_type} do
      {:ok, String.to_existing_atom(text)}
    end
  end
end

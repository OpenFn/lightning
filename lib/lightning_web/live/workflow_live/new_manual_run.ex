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
    |> Enum.reduce_while(Map.new(), fn text, filters ->
      case parse_param(text) do
        {:ok, %NaiveDateTime{} = datetime} ->
          {:cont, Map.put(filters, :datetime, datetime)}

        {:ok, {:before, datetime}} ->
          {:cont, Map.put(filters, :before, datetime)}

        {:ok, {:after, datetime}} ->
          {:cont, Map.put(filters, :after, datetime)}

        {:ok, {:id_prefix, id_prefix}} ->
          {:cont, Map.put(filters, :id_prefix, id_prefix)}

        {:ok, uuid} when is_binary(uuid) ->
          {:cont, Map.put(filters, :id, uuid)}

        {:ok, type} when is_atom(type) ->
          {:cont, Map.put(filters, :type, type)}

        error ->
          {:halt, error}
      end
    end)
    |> then(fn result ->
      with %{} = filters <- result, do: {:ok, filters}
    end)
  end

  defp parse_param("after:" <> param) do
    # TODO - Why doesn't the native datetime picker (datetime-local) send seconds?
    case NaiveDateTime.from_iso8601(param <> ":00") do
      {:ok, datetime} ->
        {:ok, {:after, datetime}}

      {:error, _reason} ->
        {:error, :invalid_datetime}
    end
  end

  defp parse_param("before:" <> param) do
    # TODO - Why doesn't the native datetime picker (datetime-local) send seconds?
    case NaiveDateTime.from_iso8601(param <> ":00") do
      {:ok, datetime} ->
        {:ok, {:before, datetime}}

      {:error, _reason} ->
        {:error, :invalid_datetime}
    end
  end

  defp parse_param("datetime:" <> param), do: NaiveDateTime.from_iso8601(param)

  defp parse_param("id:" <> param) do
    with :error <- Ecto.UUID.cast(param), do: parse_id_prefix(param)
  end

  defp parse_param("type:" <> param) do
    if MapSet.member?(@dataclip_types, param) do
      {:ok, String.to_existing_atom(param)}
    else
      {:error, :invalid_type}
    end
  end

  defp parse_param(text) do
    with {:error, _reason} <- NaiveDateTime.from_iso8601(text),
         :error <- Ecto.UUID.cast(text),
         {:error, _reason} <- parse_id_prefix(text),
         true <-
           MapSet.member?(@dataclip_types, text) || {:error, :invalid_search} do
      {:ok, String.to_existing_atom(text)}
    end
  end

  defp parse_id_prefix(text) do
    with {_num, ""} <- Integer.parse(text, 16),
         0 <- rem(String.length(text), 2) do
      {:ok, {:id_prefix, text}}
    else
      _invalid -> {:error, :invalid_uuid}
    end
  end
end

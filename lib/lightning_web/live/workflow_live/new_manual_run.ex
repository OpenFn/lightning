defmodule LightningWeb.WorkflowLive.NewManualRun do
  @moduledoc """
  This module helps with the rewrite of the Workflow editor.
  It implements the backend API for the React frontend.
  """
  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Jobs
  alias Lightning.Projects.Project
  alias Lightning.Workflows.Job

  @spec search_selectable_dataclips(
          job_id :: Ecto.UUID.t(),
          project :: Project.t(),
          search_filters :: String.t() | map(),
          limit :: integer(),
          offset :: integer()
        ) ::
          {:ok,
           %{
             dataclips: [Dataclip.t()],
             next_cron_run_dataclip_id: Ecto.UUID.t() | nil
           }}
          | {:error, Ecto.Changeset.t()}
  def search_selectable_dataclips(job_id, project, search_filters, limit, offset) do
    # A job outside the caller's project (or missing/malformed) yields an empty
    # result, never another project's dataclips and never an error the client
    # can distinguish from "no dataclips".
    if Jobs.job_in_project?(job_id, project) do
      with {:ok, filters} <- normalize_filters(search_filters) do
        {dataclips, next_cron_run_dataclip_id} =
          Invocation.list_dataclips_for_job_with_cron_state(
            %Job{id: job_id},
            filters,
            limit: limit,
            offset: offset
          )

        {:ok,
         %{
           dataclips: dataclips,
           next_cron_run_dataclip_id: next_cron_run_dataclip_id
         }}
      end
    else
      {:ok, %{dataclips: [], next_cron_run_dataclip_id: nil}}
    end
  end

  defp normalize_filters(filters) when is_map(filters), do: {:ok, filters}

  defp normalize_filters(search_text) when is_binary(search_text),
    do: get_dataclips_filters(search_text)

  @spec get_dataclips_filters(String.t() | map()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def get_dataclips_filters(query_string) when is_binary(query_string) do
    query_string
    |> URI.query_decoder()
    |> Enum.into(%{})
    |> get_dataclips_filters()
  end

  def get_dataclips_filters(params) when is_map(params) do
    Ecto.Changeset.cast(
      {%{},
       %{
         before: :utc_datetime,
         after: :utc_datetime,
         type:
           Ecto.ParameterizedType.init(Ecto.Enum,
             values: Dataclip.source_types()
           ),
         query: :string,
         id: Ecto.UUID,
         name_or_id_part: :string,
         name_part: :string,
         named_only: :boolean
       }},
      params,
      [:before, :after, :type, :named_only, :query]
    )
    |> then(fn changeset ->
      query = Ecto.Changeset.get_field(changeset, :query)

      cond do
        is_nil(query) || query == "" ->
          changeset

        Ecto.UUID.cast(query) != :error ->
          changeset
          |> Ecto.Changeset.put_change(:id, query)

        match?({_num, ""}, Integer.parse(query, 16)) ->
          changeset
          |> Ecto.Changeset.put_change(:name_or_id_part, query)

        true ->
          Ecto.Changeset.put_change(changeset, :name_part, query)
      end
    end)
    |> Ecto.Changeset.delete_change(:query)
    |> Ecto.Changeset.apply_action(:validate)
  end
end

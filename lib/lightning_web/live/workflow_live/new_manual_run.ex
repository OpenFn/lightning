defmodule LightningWeb.WorkflowLive.NewManualRun do
  @moduledoc """
  This module helps with the rewrite of the Workflow editor.
  It implements the backend API for the React frontend.
  """
  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Workflows.Job

  @spec search_selectable_dataclips(
          job_id :: Ecto.UUID.t(),
          search_text :: String.t(),
          limit :: integer(),
          offset :: integer()
        ) ::
          {:ok,
           %{
             dataclips: [Dataclip.t()],
             next_cron_run_dataclip_id: Ecto.UUID.t() | nil
           }}
          | {:error, Ecto.Changeset.t()}
  def search_selectable_dataclips(job_id, search_text, limit, offset) do
    with {:ok, filters} <-
           get_dataclips_filters(search_text),
         {dataclips, next_cron_run_dataclip_id} <-
           Invocation.list_dataclips_for_job_with_cron_state(
             %Job{id: job_id},
             filters,
             limit: limit,
             offset: offset
           ) do
      {:ok,
       %{
         dataclips: dataclips,
         next_cron_run_dataclip_id: next_cron_run_dataclip_id
       }}
    end
  end

  @spec get_dataclips_filters(String.t()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def get_dataclips_filters(query_string) do
    params = URI.query_decoder(query_string) |> Enum.into(%{})

    Ecto.Changeset.cast(
      {%{},
       %{
         before: :naive_datetime,
         after: :naive_datetime,
         type:
           Ecto.ParameterizedType.init(Ecto.Enum,
             values: Dataclip.source_types()
           ),
         query: :string,
         id: Ecto.UUID,
         id_prefix: :string
       }},
      params,
      [:before, :after, :type, :query]
    )
    |> then(fn changeset ->
      query = Ecto.Changeset.get_field(changeset, :query)

      cond do
        is_nil(query) || query == "" ->
          changeset

        Ecto.UUID.cast(query) != :error ->
          changeset
          |> Ecto.Changeset.put_change(:id, query)
          |> Ecto.Changeset.delete_change(:query)

        match?({_num, ""}, Integer.parse(query, 16)) ->
          changeset
          |> Ecto.Changeset.put_change(:id_prefix, query)
          |> Ecto.Changeset.delete_change(:query)

        true ->
          Ecto.Changeset.add_error(changeset, :query, "is invalid")
      end
    end)
    |> Ecto.Changeset.apply_action(:validate)
  end
end

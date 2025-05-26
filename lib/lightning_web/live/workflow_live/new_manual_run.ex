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
          {:ok, [Dataclip.t()]} | {:error, Ecto.Changeset.t()}
  def search_selectable_dataclips(job_id, search_text, limit, offset) do
    with {:ok, filters} <-
           get_dataclips_filters(search_text),
         dataclips <-
           Invocation.list_dataclips_for_job(
             %Job{id: job_id},
             filters,
             limit,
             offset
           ) do
      {:ok, dataclips}
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
    # TODO - figure out why this was added.
    # |> Lightning.Validators.validate_one_required(
    #   [:query, :before, :after, :type],
    #   "at least one filter is required"
    # )
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

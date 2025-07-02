defmodule LightningWeb.WorkflowLive.NewManualRun do
  @moduledoc """
  This module helps with the rewrite of the Workflow editor.
  It implements the backend API for the React frontend.
  """
  import Ecto.Query, warn: false

  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger

  @spec search_selectable_dataclips(
          job_id :: Ecto.UUID.t(),
          search_text :: String.t(),
          limit :: integer(),
          offset :: integer()
        ) ::
          {:ok,
           %{dataclips: [Dataclip.t()], next_cron_run_id: Ecto.UUID.t() | nil}}
          | {:error, Ecto.Changeset.t()}
  def search_selectable_dataclips(job_id, search_text, limit, offset) do
    with {:ok, filters} <-
           get_dataclips_filters(search_text),
         {dataclips, next_cron_run_id} <-
           list_dataclips_for_job_with_cron_state(
             %Job{id: job_id},
             filters,
             limit: limit,
             offset: offset
           ) do
      {:ok, %{dataclips: dataclips, next_cron_run_id: next_cron_run_id}}
    end
  end

  # Private function to list dataclips for a job, including next cron run state if cron-triggered
  defp list_dataclips_for_job_with_cron_state(%Job{id: job_id}, user_filters, opts) do
    if cron_triggered_job?(job_id) do
      list_dataclips_with_cron_state(job_id, user_filters, opts)
    else
      dataclips = Invocation.list_dataclips_for_job(
        %Job{id: job_id},
        user_filters,
        opts
      )
      {dataclips, nil}
    end
  end

  # Query dataclips for cron-triggered jobs, including the next run state
  defp list_dataclips_with_cron_state(job_id, user_filters, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.get(opts, :offset)

    # Create the filters that will be applied to both parts of the union
    db_filters =
      Enum.reduce(user_filters, dynamic(true), fn
        {:id, uuid}, dynamic ->
          dynamic([d], ^dynamic and d.id == ^uuid)

        {:id_prefix, id_prefix}, dynamic ->
          {id_prefix_start, id_prefix_end} =
            id_prefix_interval(id_prefix)

          dynamic(
            [d],
            ^dynamic and d.id > ^id_prefix_start and d.id < ^id_prefix_end
          )

        {:type, type}, dynamic ->
          dynamic([d], ^dynamic and d.type == ^type)

        {:after, ts}, dynamic ->
          dynamic([d], ^dynamic and d.inserted_at >= ^ts)

        {:before, ts}, dynamic ->
          dynamic([d], ^dynamic and d.inserted_at <= ^ts)
      end)

    # Query for regular input dataclips
    input_dataclips_query =
      from(d in Dataclip,
        join: s in Step,
        on: s.input_dataclip_id == d.id,
        where: s.job_id == ^job_id and is_nil(d.wiped_at),
        where: ^db_filters,
        select: %{
          id: d.id,
          type: d.type,
          inserted_at: d.inserted_at,
          project_id: d.project_id,
          wiped_at: d.wiped_at,
          is_next_cron_run: false
        },
        distinct: [desc: d.inserted_at],
        order_by: [desc: d.inserted_at]
      )

    # Query for next cron run dataclip (output of last successful step)
    next_cron_run_query =
      from(d in Dataclip,
        join: s in Step,
        on: s.output_dataclip_id == d.id,
        where: s.job_id == ^job_id and s.exit_reason == "success" and is_nil(d.wiped_at),
        where: ^db_filters,
        select: %{
          id: d.id,
          type: d.type,
          inserted_at: d.inserted_at,
          project_id: d.project_id,
          wiped_at: d.wiped_at,
          is_next_cron_run: true
        },
        order_by: [desc: s.finished_at],
        limit: 1
      )

    # Union both queries
    union_query =
      from(d in subquery(input_dataclips_query),
        union: ^next_cron_run_query
      )

    # Apply final ordering, limit, and offset
    dataclips_data =
      from(u in subquery(union_query),
        order_by: [desc: u.is_next_cron_run, desc: u.inserted_at],
        limit: ^limit
      )
      |> then(fn query -> if offset, do: offset(query, ^offset), else: query end)
      |> Repo.all()
      |> maybe_filter_uuid_prefix(user_filters)

    # Extract next_cron_run_id and convert to proper dataclip structs
    next_cron_run_id =
      dataclips_data
      |> Enum.find(&(&1.is_next_cron_run))
      |> case do
        nil -> nil
        data -> data.id
      end

    # Convert the result data back to proper Dataclip structs
    dataclips =
      dataclips_data
      |> Enum.map(fn data ->
        %Dataclip{
          id: data.id,
          type: data.type,
          inserted_at: data.inserted_at,
          project_id: data.project_id,
          wiped_at: data.wiped_at,
          body: nil,
          request: nil
        }
      end)

    {dataclips, next_cron_run_id}
  end

  # Helper function copied from Lightning.Invocation for id_prefix filtering
  defp id_prefix_interval(id_prefix) do
    prefix_bin =
      id_prefix
      |> String.to_charlist()
      |> Enum.chunk_every(2)
      |> Enum.reduce(<<>>, fn
        [_single_char], prefix_bin ->
          prefix_bin

        byte_list, prefix_bin ->
          byte_int = byte_list |> :binary.list_to_bin() |> String.to_integer(16)
          prefix_bin <> <<byte_int>>
      end)

    prefix_size = byte_size(prefix_bin)

    # UUIDs are 128 bits (16 bytes) in binary form.
    # We calculate how many bytes are missing from the prefix.
    # missing_byte_size is the number of bytes to pad to reach a full UUID binary.
    # We pad with 0s for the lower bound and 255s for the upper bound.
    missing_byte_size = 16 - prefix_size

    {
      Ecto.UUID.load!(prefix_bin <> :binary.copy(<<0>>, missing_byte_size)),
      Ecto.UUID.load!(prefix_bin <> :binary.copy(<<255>>, missing_byte_size))
    }
  end

  # Helper function copied from Lightning.Invocation for uuid_prefix filtering
  defp maybe_filter_uuid_prefix(dataclips, filters) do
    case Map.get(filters, :id_prefix, "") do
      id_prefix when rem(byte_size(id_prefix), 2) == 1 ->
        Enum.filter(dataclips, &String.starts_with?(&1.id, id_prefix))

      _ ->
        dataclips
    end
  end

  # Check if a job is triggered by a cron trigger
  defp cron_triggered_job?(job_id) do
    from(e in Edge,
      join: t in Trigger,
      on: e.source_trigger_id == t.id,
      where: e.target_job_id == ^job_id and t.type == :cron,
      select: count(e.id)
    )
    |> Repo.one()
    |> case do
      count when count > 0 -> true
      _ -> false
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

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
  defp list_dataclips_for_job_with_cron_state(
         %Job{id: job_id},
         user_filters,
         opts
       ) do
    if cron_triggered_job?(job_id) do
      list_dataclips_with_cron_state(job_id, user_filters, opts)
    else
      dataclips =
        Invocation.list_dataclips_for_job(
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

    # Build filters for database queries
    db_filters = build_db_filters(user_filters)

    # Get the next cron run dataclip (with filters applied)
    next_cron_dataclip = get_next_cron_run_dataclip(job_id, db_filters)

    next_cron_run_id =
      if next_cron_dataclip, do: next_cron_dataclip.id, else: nil

    # Build filters for input dataclips (excluding the next cron run to avoid duplication)
    input_db_filters =
      if next_cron_run_id do
        dynamic([d], ^db_filters and d.id != ^next_cron_run_id)
      else
        db_filters
      end

    # Get filtered input dataclips
    input_dataclips =
      build_input_dataclips_query(job_id, input_db_filters)
      |> apply_pagination(limit, offset)
      |> Repo.all()

    # Apply UUID prefix filtering if needed
    input_dataclips = maybe_filter_uuid_prefix(input_dataclips, user_filters)

    next_cron_dataclip =
      if next_cron_dataclip do
        case maybe_filter_uuid_prefix([next_cron_dataclip], user_filters) do
          [filtered_clip] -> filtered_clip
          [] -> nil
        end
      else
        nil
      end

    # Combine results - next cron run first (if it exists and matches filters), then input dataclips
    all_dataclips =
      if next_cron_dataclip do
        [next_cron_dataclip | input_dataclips]
      else
        input_dataclips
      end

    # Convert to proper dataclip structs
    dataclips = convert_to_dataclip_structs(all_dataclips)

    # Only return next_cron_run_id if the dataclip actually made it through filtering
    final_next_cron_run_id =
      if next_cron_dataclip, do: next_cron_dataclip.id, else: nil

    {dataclips, final_next_cron_run_id}
  end

  # Get the next cron run dataclip (with filters applied)
  defp get_next_cron_run_dataclip(job_id, db_filters) do
    from(d in Dataclip,
      join: s in Step,
      on: s.output_dataclip_id == d.id,
      where:
        s.job_id == ^job_id and s.exit_reason == "success" and
          is_nil(d.wiped_at),
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
    |> Repo.one()
  end

  # Build dynamic filters for the database queries
  defp build_db_filters(user_filters) do
    Enum.reduce(user_filters, dynamic(true), &build_single_filter/2)
  end

  # Build a single filter condition
  defp build_single_filter({:id, uuid}, dynamic) do
    dynamic([d], ^dynamic and d.id == ^uuid)
  end

  defp build_single_filter({:id_prefix, id_prefix}, dynamic) do
    {id_prefix_start, id_prefix_end} = id_prefix_interval(id_prefix)
    dynamic([d], ^dynamic and d.id > ^id_prefix_start and d.id < ^id_prefix_end)
  end

  defp build_single_filter({:type, type}, dynamic) do
    dynamic([d], ^dynamic and d.type == ^type)
  end

  defp build_single_filter({:after, ts}, dynamic) do
    dynamic([d], ^dynamic and d.inserted_at >= ^ts)
  end

  defp build_single_filter({:before, ts}, dynamic) do
    dynamic([d], ^dynamic and d.inserted_at <= ^ts)
  end

  # Build query for regular input dataclips
  defp build_input_dataclips_query(job_id, db_filters) do
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
        wiped_at: d.wiped_at
      },
      distinct: [desc: d.inserted_at],
      order_by: [desc: d.inserted_at]
    )
  end

  # Apply pagination to the query
  defp apply_pagination(query, limit, offset) do
    query
    |> limit(^limit)
    |> then(fn q -> if offset, do: offset(q, ^offset), else: q end)
  end

  # Convert the result data back to proper Dataclip structs
  defp convert_to_dataclip_structs(dataclips_data) do
    Enum.map(dataclips_data, fn data ->
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

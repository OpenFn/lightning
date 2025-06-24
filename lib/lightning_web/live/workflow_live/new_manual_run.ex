defmodule LightningWeb.WorkflowLive.NewManualRun do
  @moduledoc """
  This module helps with the rewrite of the Workflow editor.
  It implements the backend API for the React frontend.
  """
  import Ecto.Query, warn: false

  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Repo
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Edge
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
         dataclips <-
           Invocation.list_dataclips_for_job(
             %Job{id: job_id},
             filters,
             limit: limit,
             offset: offset
           ) do
      # Check if this job is cron-triggered and include next run state if so
      {enhanced_dataclips, next_cron_run_id} =
        maybe_add_next_cron_run(job_id, dataclips)

      {:ok, %{dataclips: enhanced_dataclips, next_cron_run_id: next_cron_run_id}}
    end
  end

  # Private function to check if job is cron-triggered and add next run dataclip
  defp maybe_add_next_cron_run(job_id, dataclips) do
    case is_cron_triggered_job?(job_id) do
      true ->
        case last_state_for_job(job_id) do
          nil ->
            {dataclips, nil}

          next_run_dataclip ->
            {[next_run_dataclip | dataclips], next_run_dataclip.id}
        end

      false ->
        {dataclips, nil}
    end
  end

  # Check if a job is triggered by a cron trigger
  defp is_cron_triggered_job?(job_id) do
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

  # Copy of the last_state_for_job function from the scheduler
  defp last_state_for_job(id) do
    step =
      %Job{id: id}
      |> Invocation.Query.last_successful_step_for_job()
      |> Repo.one()

    case step do
      nil -> nil
      step -> Invocation.get_output_dataclip_query(step) |> Repo.one()
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

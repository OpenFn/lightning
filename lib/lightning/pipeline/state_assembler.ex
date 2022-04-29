defmodule Lightning.Pipeline.StateAssembler do
  @moduledoc """
  Facilities for building the state for a Run

  ## How state is assembled

  For the most common jobs, where a Webhooks will store an `:http_request` type
  dataclip. The event that was created is associated with the dataclip.

  At runtime, the initial state for a Run will in the shape of:

  ```
  { "data": <the dataclip>, "configuration": <the job's credential> }
  ```

  ### Flow Jobs

  When a Job is triggered by a previous Jobs success or failure these are the
  rules for constructing that Jobs state.

  For jobs that trigger on it's upstream jobs failure, the event will have
  the source events original dataclip as its dataclip.

  The state will also have the log of the source events run attached on the
  `error` key.

  For Jobs triggered by a previous success, the event will have the source
  event runs resulting dataclip as its dataclip.

  `:run_result` dataclips are expected to already have a `data` key, and are
  merged into the root.
  """

  import Ecto.Query, warn: false

  require Jason.Helpers
  alias Lightning.Invocation.{Event}

  @doc """
  Assemble state for use in a Run.
  """
  def assemble(run) do
    %{id: run_id} = run

    query =
      from(e in Event,
        join: r in assoc(e, :run),
        join: d in assoc(e, :dataclip),
        as: :dataclip,
        join: j in assoc(e, :job),
        left_join: c in assoc(j, :credential),
        as: :credential,
        left_join: se in assoc(e, :source),
        left_join: ser in assoc(se, :run),
        as: :source_event_run,
        where: r.id == ^run_id
      )

    context = context_query(run)

    case {context.dataclip_type, context.trigger_type} do
      # Source event failed, so we reconstruct the `data` key, and attach
      # the error log.
      {:http_request, :on_job_failure} ->
        query
        |> select(
          [dataclip: d, credential: c, source_event_run: ser],
          type(
            fragment(
              """
              jsonb_build_object('data', ?, 'configuration', ?, 'error', ?)
              """,
              d.body,
              c.body,
              ser.log
            ),
            :string
          )
        )

      # Is the first event, attach the `http_request` dataclip onto `data`.
      {:http_request, _} ->
        query
        |> select(
          [dataclip: d, credential: c],
          type(
            fragment(
              """
              jsonb_build_object('data', ?, 'configuration', ?)
              """,
              d.body,
              c.body
            ),
            :string
          )
        )

      # Source event succeeded, merge the `run_result` dataclip onto the root
      # and then this Jobs configuration.
      {:run_result, :on_job_success} ->
        query
        |> select(
          [dataclip: d, credential: c],
          type(
            fragment(
              """
              (? || jsonb_build_object('configuration', ?))
              """,
              d.body,
              c.body
            ),
            :string
          )
        )

      # Source event failed and had a `run_result` as it's dataclip,
      # merge it into the root, with this Jobs configuration and the source
      # events error log.
      {:run_result, :on_job_failure} ->
        query
        |> select(
          [dataclip: d, credential: c, source_event_run: ser],
          type(
            fragment(
              """
              (? || jsonb_build_object('configuration', ?, 'error', ?))
              """,
              d.body,
              c.body,
              ser.log
            ),
            :string
          )
        )
    end
    |> Lightning.Repo.one!()
  end

  def context_query(%{id: run_id}) do
    from(e in Event,
      join: d in assoc(e, :dataclip),
      join: r in assoc(e, :run),
      join: j in assoc(e, :job),
      join: t in assoc(j, :trigger),
      left_join: c in assoc(j, :credential),
      left_join: se in assoc(e, :source),
      left_join: ser in assoc(se, :run),
      where: r.id == ^run_id,
      select: %{
        dataclip_type: d.type,
        trigger_type: t.type
      }
    )
    |> Lightning.Repo.one!()
  end
end

defmodule Lightning.Pipeline.StateAssembler do
  @moduledoc """
  Facilities for building the state for a Run

  ## How state is assembled

  For the most common jobs, an inbound webhook will store an `:http_request` type
  dataclip. The event that is created is associated with the dataclip.

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
  @spec assemble(run :: Lightning.Invocation.Run.t()) :: String.t()
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

    context_query(run)
    |> build_state(query)
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
      select: {
        d.type,
        t.type
      }
    )
    |> Lightning.Repo.one!()
  end

  @spec build_state(
          context ::
            {Lightning.Invocation.Dataclip.source_type(),
             Lightning.Jobs.Trigger.trigger_type()},
          query :: Ecto.Queryable.t()
        ) :: binary()
  # Source event failed, so we reconstruct the `data` key, and attach
  # the error log.
  def build_state({:http_request, :on_job_failure}, query) do
    {dataclip, credential, log} =
      query
      |> select(
        [dataclip: d, credential: c, source_event_run: ser],
        {d.body, c.body, ser.log}
      )
      |> Lightning.Repo.one!()

    Jason.Helpers.json_map(data: dataclip, configuration: credential, error: log)
    |> Jason.encode_to_iodata!()
  end

  # Is the first event, attach the `http_request` dataclip onto `data`.
  def build_state({:http_request, _}, query) do
    {dataclip, credential} =
      query
      |> select(
        [dataclip: d, credential: c],
        {d.body, c.body}
      )
      |> Lightning.Repo.one!()

    Jason.Helpers.json_map(data: dataclip, configuration: credential)
    |> Jason.encode_to_iodata!()
  end

  # A cron job started without any default initial dataclip gets a new
  # "global" dataclip with an empty body.
  def build_state({:global, :cron}, query) do
    dataclip_with_credential(query)
  end

  # A cron job started with the result of a previous run; merge the
  # `run_result` dataclip onto the root and then use this job's configuration.
  def build_state({:run_result, :cron}, query) do
    dataclip_with_credential(query)
  end

  # Source event succeeded, merge the `run_result` dataclip onto the root
  # and then use this job's configuration.
  def build_state({:run_result, :on_job_success}, query) do
    dataclip_with_credential(query)
  end

  # Source event failed and had a `run_result` as it's dataclip,
  # merge it into the root, with this Jobs configuration and the source
  # events error log.
  def build_state({:run_result, :on_job_failure}, query) do
    dataclip_with_credential_and_log(query)
  end

  @doc """
  Merge the credential key into the dataclip.

  Returns `iodata`.
  """
  def dataclip_with_credential(query) do
    {dataclip, credential} =
      query
      |> select([dataclip: d, credential: c], {d.body, c.body})
      |> Lightning.Repo.one!()

    Jason.encode_to_iodata!(dataclip |> Map.put("configuration", credential))
  end

  @doc """
  Merge the credential, and the previous runs log into the dataclip.

  Returns `iodata`.
  """
  def dataclip_with_credential_and_log(query) do
    {dataclip, credential, error} =
      query
      |> select(
        [dataclip: d, credential: c, source_event_run: ser],
        {d.body, c.body, ser.log}
      )
      |> Lightning.Repo.one!()

    Jason.encode_to_iodata!(
      dataclip
      |> Map.put("configuration", credential)
      |> Map.put("error", error)
    )
  end
end

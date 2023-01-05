defmodule Lightning.Pipeline.StateAssembler do
  @moduledoc """
  Facilities for building the state for a Run

  ## How state is assembled

  For the most common jobs, an inbound webhook will store an `:http_request` type
  dataclip. The reason that is created is associated with the dataclip.

  At runtime, the initial state for a Run will be in the shape of:

  ```
  { "data": <the dataclip>, "configuration": <the job's credential> }
  ```

  ## Saved inputs

  Saved custom inputs will only have state.configuration changed, everything else
  will remain as displayed.

  ### Flow Jobs

  When a Job is triggered by a previous Jobs success or failure these are the
  rules for constructing that Jobs state:

  For jobs that trigger on it's upstream jobs failure, the event will have
  the previous runs input dataclip as its input dataclip.

  The state will also have the log of the previous run attached on the
  `error` key.

  For Jobs triggered by a previous success, the run will have the previous
  runs output dataclip as its input dataclip.

  `:run_result` dataclips are expected to already have a `data` key, and are
  merged into the root.
  """

  import Ecto.Query, warn: false

  require Jason.Helpers
  alias Lightning.Invocation.Run

  @doc """
  Assemble state for use in a Run.
  """
  @spec assemble(run :: Lightning.Invocation.Run.t()) :: String.t()
  def assemble(%Run{} = run) do
    query =
      from(r in Run,
        join: d in assoc(r, :input_dataclip),
        as: :dataclip,
        left_join: p in assoc(r, :previous),
        on: p.exit_code > 0,
        as: :previous,
        join: j in assoc(r, :job),
        left_join: c in assoc(j, :credential),
        as: :credential,
        where: r.id == ^run.id
      )

    {dataclip_type, dataclip_body, credential, error} =
      query
      |> select(
        [dataclip: d, credential: c, previous: p],
        {d.type, d.body, c.body, p.log}
      )
      |> Lightning.Repo.one!()

    case {dataclip_type, error} do
      {:run_result, error} when not is_nil(error) ->
        Jason.encode_to_iodata!(
          dataclip_body
          |> Map.put("configuration", credential)
          |> Map.put("error", error)
        )

      {_, error} when not is_nil(error) ->
        Jason.Helpers.json_map(
          data: dataclip_body,
          configuration: credential,
          error: error
        )
        |> Jason.encode_to_iodata!()

      {:run_result, nil} ->
        Jason.encode_to_iodata!(
          dataclip_body
          |> Map.put("configuration", credential)
        )

      {:saved_input, nil} ->
        Jason.encode_to_iodata!(
          dataclip_body
          |> Map.put("configuration", credential)
        )

      {_, nil} ->
        Jason.Helpers.json_map(data: dataclip_body, configuration: credential)
        |> Jason.encode_to_iodata!()
    end
  end
end

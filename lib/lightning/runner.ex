defmodule Lightning.Runner do
  @moduledoc """
  Job running entrypoint
  """
  require Logger
  alias Lightning.Invocation
  import Lightning.Invocation, only: [get_dataclip_body: 1]
  import Lightning.Jobs, only: [get_job!: 1]
  import Lightning.Credentials, only: [get_credential_body: 1]

  import Engine.Adaptor.Service, only: [install!: 2, resolve_package_name: 1, find_adaptor: 2]

  defmodule Handler do
    @moduledoc """
    Custom handler callbacks for Lightnings use of Engine to execute runs.
    """
    use Engine.Run.Handler
    import Lightning.Invocation, only: [update_run: 2]

    @impl true
    def on_start(run) do
      update_run(run, %{started_at: DateTime.utc_now()})
    end

    @impl true
    def on_finish(result, run) do
      update_run(run, %{
        finished_at: DateTime.utc_now(),
        exit_code: result.exit_code,
        log: result.log
      })

      Lightning.Runner.create_dataclip_from_result(result, run)
    end
  end

  require Jason.Helpers

  @doc """
  Execute a Run.

  Given a valid run:
  - Persist the Dataclip and the Job's body to disk
  - Create a blank output file on disk
  - Build up a `%Engine.Runspec{}` with the paths, and adaptor module name

  And start it via `Handler.start/2`.

  The callbacks implemented on `Handler` (`c:Handler.on_start/1` and `c:Handler.on_finish/2`)
  update the run when a Run is started and when it's finished, attaching
  the `exit_code` and `log` when they are available.
  """
  @spec start(run :: Invocation.Run.t(), opts :: []) :: Engine.Result.t()
  def start(%Invocation.Run{} = run, opts \\ []) do
    run = Lightning.Repo.preload(run, :event)

    %{body: expression, adaptor: adaptor, credential_id: credential_id} =
      get_job!(run.event.job_id)

    dataclip = get_dataclip_body(run)

    credential =
      if credential_id do
        get_credential_body(credential_id)
      else
        nil
      end

    state = build_state(dataclip, credential)

    %{local_name: local_name} = find_or_install_adaptor(adaptor)

    # turn run into RunSpec
    {:ok, state_path} = write_temp(state, "state")
    {:ok, final_state_path} = write_temp("", "output")
    {:ok, expression_path} = write_temp(expression, "expression")

    runspec = %Engine.RunSpec{
      adaptor: local_name,
      state_path: state_path,
      adaptors_path: "./priv/openfn/lib",
      final_state_path: final_state_path,
      expression_path: expression_path,
      env: %{
        "PATH" => "./priv/openfn/bin:#{System.get_env("PATH")}"
      },
      timeout: 60_000
    }

    Handler.start(runspec, Keyword.merge(opts, context: run))
  end

  # In order to run a flow job, `start/2` is called, and on a result

  @spec write_temp(contents :: binary(), prefix :: String.t()) :: {:ok, Path.t()} | {:error, any}
  defp write_temp(contents, prefix) do
    Temp.open(
      %{prefix: prefix, suffix: ".json"},
      &IO.write(&1, contents)
    )
  end

  @spec build_state(dataclip :: String.t(), credential :: String.t() | nil) :: iodata()
  defp build_state(dataclip, credential) do
    # NOTE: really not sure how much we're gaining here, we're trying to avoid
    # as much data marshalling as possible - and this currently avoids turning
    # the job body into a map before turning it into a string again; which
    # is probably somewhat of a win.
    Jason.Helpers.json_map(
      data: Jason.Fragment.new(fn _ -> dataclip end),
      configuration: Jason.Fragment.new(fn _ -> credential || "null" end)
    )
    |> Jason.encode_to_iodata!()
  end

  @doc """
  Creates a dataclip linked to the run that just finished.
  If either the file doesn't exist or there is a JSON decoding error, it logs
  and returns an error tuple.
  """
  @spec create_dataclip_from_result(result :: Engine.Result.t(), run :: Invocation.Run.t()) ::
          {:ok, Invocation.Dataclip.t()} | {:error, any}
  def create_dataclip_from_result(%Engine.Result{} = result, run) do
    with {:ok, data} <- File.read(result.final_state_path),
         {:ok, body} <- Jason.decode(data) do
      Invocation.create_dataclip(%{
        run_id: run.id,
        type: :run_result,
        body: body
      })
    else
      res = {:error, %Jason.DecodeError{position: pos}} ->
        Logger.info(
          "Got JSON decoding error when trying to parse: #{result.final_state_path}:#{pos}"
        )

        res

      res = {:error, err} ->
        Logger.info(
          "Got unexpected result while saving the resulting state from a Run:\n#{inspect(err)}"
        )

        res
    end
  end

  @doc """
  Make sure an adaptor matching the name is available.

  If it is available, return it's `Engine.Adaptor` struct - if not then
  install it.
  """
  @spec find_or_install_adaptor(adaptor :: String.t()) :: Engine.Adaptor.t()
  def find_or_install_adaptor(adaptor) when is_binary(adaptor) do
    package_spec = resolve_package_name(adaptor)
    adaptor = find_adaptor(:adaptor_service, package_spec)

    if is_nil(adaptor) do
      {:ok, adaptor} = install!(:adaptor_service, package_spec)
      adaptor
    else
      adaptor
    end
  end
end

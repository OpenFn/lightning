defmodule Lightning.Runner do
  @moduledoc """
  Job running entrypoint
  """
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
    credential = get_credential_body(credential_id)

    # NOTE: really not sure how much we're gaining here, we're trying to avoid
    # as much data marshalling as possible - and this currently avoids turning
    # the job body into a map before turning it into a string again; which
    # is probably somewhat of a win.
    state =
      Jason.Helpers.json_map(
        data: Jason.Fragment.new(fn _ -> dataclip end),
        configuration: Jason.Fragment.new(fn _ -> credential || "null" end)
      )
      |> Jason.encode_to_iodata!()

    %{local_name: local_name} = find_or_install_adaptor(adaptor)

    # turn run into RunSpec
    {:ok, state_path} =
      Temp.open(
        %{prefix: "state", suffix: ".json"},
        &IO.write(&1, state)
      )

    {:ok, final_state_path} =
      Temp.open(
        %{prefix: "output", suffix: ".json"},
        &IO.write(&1, "")
      )

    {:ok, expression_path} =
      Temp.open(
        %{prefix: "expression", suffix: ".json"},
        &IO.write(&1, expression)
      )

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

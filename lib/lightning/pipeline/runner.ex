defmodule Lightning.Pipeline.Runner do
  @moduledoc """
  Job running entrypoint
  """
  require Logger
  alias Lightning.Invocation
  import Lightning.Jobs, only: [get_job!: 1]

  import Engine.Adaptor.Service,
    only: [install!: 2, resolve_package_name: 1, find_adaptor: 2]

  defmodule Handler do
    @moduledoc """
    Custom handler callbacks for Lightnings use of Engine to execute runs.
    """
    use Engine.Run.Handler
    alias Lightning.Pipeline.Runner
    import Lightning.Invocation, only: [update_run: 2]

    @impl true
    def on_start(run: run, scrubber: _) do
      update_run(run, %{started_at: DateTime.utc_now()})
    end

    @impl true
    def on_finish(result, run: run, scrubber: scrubber) do
      debug do
        result.log
        |> Enum.each(fn line ->
          Logger.debug("#{String.slice(run.id, -5..-1)} : #{line}")
        end)
      end

      scrubbed_log = Lightning.Scrubber.scrub(scrubber, result.log)

      update_run(run, %{
        finished_at: DateTime.utc_now(),
        exit_code: result.exit_code,
        log: scrubbed_log
      })

      Runner.create_dataclip_from_result(result, run)
    end

    defp debug(do: block) do
      if Logger.compare_levels(Logger.level(), :debug) == :eq do
        # coveralls-ignore-start
        block.call()
        # coveralls-ignore-stop
      end
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
    run = Lightning.Repo.preload(run, event: [job: :credential])

    %{body: expression, adaptor: adaptor} = get_job!(run.event.job_id)

    {:ok, scrubber} =
      Lightning.Scrubber.start_link(
        samples:
          Lightning.Credentials.sensitive_values_for(run.event.job.credential)
      )

    state = Lightning.Pipeline.StateAssembler.assemble(run)

    %{local_name: local_name} = find_or_install_adaptor(adaptor)

    # turn run into RunSpec
    {:ok, state_path} = write_temp(state, "state")
    {:ok, final_state_path} = write_temp("", "output")
    {:ok, expression_path} = write_temp(expression, "expression")

    adaptors_path =
      Application.get_env(:lightning, :adaptor_service)
      |> Keyword.get(:adaptors_path)

    runspec = %Engine.RunSpec{
      adaptor: local_name,
      state_path: state_path,
      adaptors_path: "#{adaptors_path}/lib",
      final_state_path: final_state_path,
      expression_path: expression_path,
      env: %{
        "PATH" => "#{adaptors_path}/bin:#{System.get_env("PATH")}"
      },
      timeout: 60_000
    }

    Handler.start(
      runspec,
      Keyword.merge(opts, context: [run: run, scrubber: scrubber])
    )
  end

  # In order to run a flow job, `start/2` is called, and on a result

  @spec write_temp(contents :: binary(), prefix :: String.t()) ::
          {:ok, Path.t()} | {:error, any}
  defp write_temp(contents, prefix) do
    Temp.open(
      %{prefix: prefix, suffix: ".json", mode: [:write, :utf8]},
      &IO.write(&1, contents)
    )
  end

  @doc """
  Creates a dataclip linked to the run that just finished.
  If either the file doesn't exist or there is a JSON decoding error, it logs
  and returns an error tuple.
  """
  @spec create_dataclip_from_result(
          result :: Engine.Result.t(),
          run :: Invocation.Run.t()
        ) ::
          {:ok, Invocation.Dataclip.t()} | {:error, any}
  def create_dataclip_from_result(%Engine.Result{} = result, run) do
    with {:ok, data} <- File.read(result.final_state_path),
         {:ok, body} <- Jason.decode(data) do
      Invocation.create_dataclip(%{
        project_id: run.event.project_id,
        source_event_id: run.event_id,
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

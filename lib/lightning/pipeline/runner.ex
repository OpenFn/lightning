defmodule Lightning.Pipeline.Runner do
  @moduledoc """
  Job running entrypoint
  """
  require Logger
  alias Lightning.Repo
  alias Lightning.Invocation
  alias Lightning.Workflows.Job
  alias Lightning.Credentials.Credential

  import Lightning.AdaptorService,
    only: [install!: 2, resolve_package_name: 1, find_adaptor: 2]

  defmodule Handler do
    @moduledoc """
    Custom handler callbacks for Lightnings use of Engine to execute runs.
    """
    use Lightning.Runtime.Handler
    alias Lightning.Repo
    alias Lightning.Pipeline.Runner
    import Lightning.Invocation, only: [update_run: 2]

    @doc """
    The on_start handler updates the run, setting the started_at time and
    stamping the run with the ID of the credential that was used, if any, to
    facilitate easier auditing.
    """
    @impl true
    def on_start(run: run, scrubber: _) do
      update_run(run, %{
        started_at: DateTime.utc_now(),
        credential_id:
          case run do
            %{job: %Job{credential: %Credential{id: id}}} -> id
            _else -> nil
          end
      })
    end

    @impl true
    def on_finish(result, run: run, scrubber: scrubber) do
      Logger.debug(fn ->
        # coveralls-ignore-start
        result.log
        |> Enum.map(fn line ->
          "\n#{String.slice(run.id, -5..-1)} : #{line}"
        end)

        # coveralls-ignore-stop
      end)

      {:ok, run} =
        Repo.transaction(fn ->
          :ok =
            Lightning.Scrubber.scrub(scrubber, result.log)
            |> save_logs_for_run(run)

          {:ok, run} =
            update_run(run, %{
              finished_at: DateTime.utc_now(),
              exit_code: result.exit_code
            })

          run
        end)

      dataclip_result =
        Runner.create_dataclip_from_result(result, run)

      Lightning.FailureAlerter.alert_on_failure(run)

      dataclip_result
    end

    # TODO - this, along with everything else in the runner, will probably be deleted in a hot second.
    defp save_logs_for_run(logs, run) do
      Enum.each(logs, fn log ->
        %Lightning.Invocation.LogLine{}
        |> Ecto.Changeset.change(%{
          run: run,
          message: log,
          timestamp: Timex.now()
        })
        |> LogLine.validate()
        |> Repo.insert!()
      end)
    end
  end

  require Jason.Helpers

  @doc """
  Execute a Run.

  Given a valid run:
  - Persist the Dataclip and the Job's body to disk
  - Create a blank output file on disk
  - Build up a `%Lightning.Runtime.Runspec{}` with the paths, and adaptor module name

  And start it via `Handler.start/2`.

  The callbacks implemented on `Handler` (`c:Handler.on_start/1` and `c:Handler.on_finish/2`)
  update the run when a Run is started and when it's finished, attaching
  the `exit_code` and `log` when they are available.
  """
  @spec start(run :: Invocation.Run.t(), opts :: []) ::
          Lightning.Runtime.Result.t()
  def start(%Invocation.Run{} = run, opts \\ []) do
    run =
      Lightning.Repo.preload(run, [
        :log_lines,
        :output_dataclip,
        job: :credential
      ])

    %{body: expression, adaptor: adaptor} = run.job

    {:ok, scrubber} =
      Lightning.Scrubber.start_link(
        samples: Lightning.Credentials.sensitive_values_for(run.job.credential)
      )

    Lightning.Credentials.maybe_refresh_token(run.job.credential)

    state = Lightning.Pipeline.StateAssembler.assemble(run)

    %{path: path} = find_or_install_adaptor(adaptor)

    # turn run into RunSpec
    {:ok, state_path} = write_temp(state, "state", ".json")
    {:ok, final_state_path} = write_temp("", "output", ".json")
    {:ok, expression_path} = write_temp(expression, "expression", ".js")

    adaptors_path =
      Application.get_env(:lightning, :adaptor_service)
      |> Keyword.get(:adaptors_path)

    runspec =
      Lightning.Runtime.RunSpec.new(
        adaptor: "#{adaptor}=#{path}",
        state_path: state_path,
        adaptors_path: "#{adaptors_path}/lib",
        final_state_path: final_state_path,
        expression_path: expression_path,
        env: %{
          "PATH" => "#{adaptors_path}/bin:#{System.get_env("PATH")}"
        },
        timeout: Application.get_env(:lightning, :max_run_duration)
      )

    Handler.start(
      runspec,
      Keyword.merge(opts, context: [run: run, scrubber: scrubber])
    )
  end

  # In order to run a flow job, `start/2` is called, and on a result

  @spec write_temp(
          contents :: binary(),
          prefix :: String.t(),
          suffix :: String.t()
        ) ::
          {:ok, Path.t()} | {:error, any}
  defp write_temp(contents, prefix, suffix) do
    Temp.open(
      %{prefix: prefix, suffix: suffix, mode: [:write, :utf8]},
      &IO.write(&1, contents)
    )
  end

  @doc """
  Scrubs values from all keys in configuration, will be replaced by extensions
  to scrubber.ex, which is currently only used for logs.
  """
  @spec scrub_result(body :: map()) :: map()
  def scrub_result(%{} = body) do
    Map.delete(body, "configuration")
  end

  @doc """
  Creates a dataclip linked to the run that just finished.

  **IMPORTANT**: The function was refactored to address the issue described in [GitHub Issue #1084](https://github.com/OpenFn/Lightning/issues/1084).

  The following scenarios are handled:
  1. Reads the file content of the result's final state.
  2. Attempts to decode the file content as JSON.
  3. Processes the decoded content, linking it to the provided run.

  If the file doesn't exist or there's a JSON decoding error:
  - The error is logged.
  - A nil value is set for the output dataclip linked to the run.
  - An error tuple is returned.

  Success scenario:
  - The dataclip is updated with the decoded content and linked to the run.

  Returns:
  - The updated run with the linked dataclip in the case of success.
  - An error tuple in the case of failure.

  """
  @spec create_dataclip_from_result(
          result :: Lightning.Runtime.Result.t(),
          run :: Invocation.Run.t()
        ) ::
          {:ok, Invocation.Dataclip.t()} | {:error, any}
  # false positive, it's the output.json temp file
  # sobelow_skip ["Traversal.FileModule"]
  def create_dataclip_from_result(%Lightning.Runtime.Result{} = result, run) do
    with {:ok, data} <- File.read(result.final_state_path),
         {:ok, body} <- Jason.decode(data) do
      job = Lightning.Repo.preload(run.job, :workflow)

      Invocation.update_run(run, %{
        output_dataclip: %{
          project_id: job.workflow.project_id,
          type: :run_result,
          body: scrub_result(body)
        }
      })
    else
      error = {:error, %Jason.DecodeError{position: pos}} ->
        Logger.info(
          "Got JSON decoding error when trying to parse: #{result.final_state_path}:#{pos}"
        )

        run
        |> Repo.preload(:output_dataclip)
        |> Invocation.update_run(%{
          output_dataclip: nil
        })

        error

      error = {:error, err} ->
        Logger.info(
          "Got unexpected result while saving the resulting state from a Run:\n#{inspect(err)}"
        )

        error
    end
  end

  @doc """
  Make sure an adaptor matching the name is available.

  If it is available, return it's `Engine.Adaptor` struct - if not then
  install it.
  """
  @spec find_or_install_adaptor(adaptor :: String.t()) ::
          Lightning.AdaptorService.Adaptor.t()
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

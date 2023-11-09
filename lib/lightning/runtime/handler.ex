defmodule Lightning.Runtime.Handler do
  @moduledoc """
  A strategy for executing things via ChildProcess.

  This module handles the dirty bits, setting up processes and coordinating
  results (and logs) as they arrive.
  """
  alias Lightning.Runtime.{RunSpec, Result}

  @type t :: module

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            task_supervisor: pid(),
            agent_supervisor: pid(),
            log_agent: pid(),
            log_agent_ref: reference(),
            run_task: Task.t(),
            context: any()
          }

    defstruct [
      :task_supervisor,
      :agent_supervisor,
      :log_agent,
      :log_agent_ref,
      :run_task,
      :context
    ]
  end

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      alias Lightning.Runtime.Handler
      @behaviour Handler

      @type handler_opts :: [
              context: any(),
              timeout: integer(),
              env: %{}
            ]

      @impl true
      @spec start(run_spec :: RunSpec.t(), opts :: handler_opts()) :: Result.t()
      def start(run_spec, opts \\ []) do
        {:ok, task_supervisor} = Task.Supervisor.start_link()

        {:ok, agent_supervisor} =
          DynamicSupervisor.start_link(strategy: :one_for_one)

        {:ok, log_agent} =
          DynamicSupervisor.start_child(
            agent_supervisor,
            {Lightning.Runtime.LogAgent, []}
          )

        log_agent_ref = Process.monitor(log_agent)

        context = opts[:context] || nil

        rambo_opts = [
          timeout: opts[:timeout] || run_spec.timeout,
          log: &log_callback(log_agent, context, &1),
          env: env(run_spec, opts)
        ]

        run_task =
          Task.Supervisor.async_nolink(task_supervisor, fn ->
            __MODULE__.on_start(context)

            {_msg, result} =
              Lightning.Runtime.ChildProcess.run(run_spec, rambo_opts)

            result
          end)

        wait(%State{
          task_supervisor: task_supervisor,
          agent_supervisor: agent_supervisor,
          log_agent: log_agent,
          log_agent_ref: log_agent_ref,
          run_task: run_task,
          context: context
        })
      end

      @impl true
      def log_callback(log_agent, context, args) do
        res = Lightning.Runtime.LogAgent.process_chunk(log_agent, args)
        res |> __MODULE__.on_log_emit(context)

        true
      end

      defp wait(
             %State{
               run_task: %Task{ref: run_task_ref},
               log_agent_ref: log_agent_ref
             } = state
           ) do
        receive do
          # RunTask finished
          {^run_task_ref, result} ->
            __MODULE__.on_finish(result, state.context)

            # We don't care about the DOWN message now, so let's demonitor and flush it
            Process.demonitor(run_task_ref, [:flush])
            Process.demonitor(log_agent_ref, [:flush])
            stop(state)
            result

          {:DOWN, ^run_task_ref, :process, _pid, reason} ->
            stop(state)
            # This means that the task, and therefore Rambo finished without
            # either a value or an exception, in all reasonable circumstances
            # this should not be reached.
            raise "ChildProcess task exited without a value:\n#{inspect(reason)}"

          {:DOWN, ^log_agent_ref, :process, _pid, reason} ->
            stop(state)
            # Something when wrong in the logger, when/if this gets reached
            # we need to decide what we want to be done.
            raise "Logging agent process ended prematurely:\n#{inspect(reason)}"
        end
      end

      def stop(%State{
            task_supervisor: task_supervisor,
            agent_supervisor: agent_supervisor
          }) do
        Supervisor.stop(task_supervisor)
        DynamicSupervisor.stop(agent_supervisor)
      end

      @impl true
      defdelegate env(run_spec, opts), to: Handler

      @impl true
      defdelegate on_start(context), to: Handler

      @impl true
      defdelegate on_log_emit(chunk, context), to: Handler

      @impl true
      defdelegate on_finish(result, context), to: Handler

      defoverridable Handler
    end
  end

  @doc """
  The entrypoint for executing a run.
  """
  @callback start(any, opts :: []) :: any()

  @doc """
  Called with context, if any - when the Run has been started.
  """
  @callback on_start(context :: any()) :: any
  @callback on_log_emit(chunk :: binary(), context :: any()) :: any
  @callback on_finish(result :: Lightning.Runtime.Result.t(), context :: any()) ::
              any
  @callback log_callback(agent :: pid(), context :: any(), args :: any()) :: true

  def on_start(_context), do: :noop
  def on_log_emit(_chunk, _context), do: :noop
  def on_finish(_result, _context), do: :noop

  @callback env(run_spec :: %RunSpec{}, opts :: []) :: %{binary() => binary()}

  def env(run_spec, opts) do
    %{}
    |> Map.merge(node_path(run_spec.adaptors_path))
    |> Map.merge(%{"OPENFN_ADAPTORS_REPO" => run_spec.adaptors_path})
    |> Map.merge(Keyword.get(opts, :env, %{}))
    |> Map.merge(run_spec.env || %{})
  end

  defp node_path(nil), do: %{}

  defp node_path(path) when is_binary(path) do
    %{"NODE_PATH" => path}
  end
end

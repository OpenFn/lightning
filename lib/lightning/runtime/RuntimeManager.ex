defmodule Lightning.Runtime.RuntimeManager do
  @moduledoc """
  Locates and runs the Runtime server. Added in order to ease development and default installations of Lightning
  """

  use GenServer, restart: :transient, shutdown: 5_000
  require Logger

  alias __MODULE__

  defstruct [
    :lightning_url,
    :runtime_pid,
    runtime_path: Application.app_dir(:lightning, "priv/runtime/test"),
    max_restarts: 5,
    restarts: 0
  ]

  def start_link(args) do
    {name, args} = Keyword.pop(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    config = Application.get_env(:lighting, RuntimeManager, [])
    config = Keyword.merge(config, args)

    config = Keyword.put_new(config, :lightning_url, LightningWeb.Endpoint.url())

    {:ok, struct(RuntimeManager, config), {:continue, :start_runtime}}
  end

  @impl true
  def handle_continue(:start_runtime, state) do
    {:noreply, start_runtime(state)}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{runtime_pid: pid} = state) do
    Logger.error("Runtime exited with reason: #{inspect(reason)}")
    {:noreply, start_runtime(state)}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Shutting down Runtime Manager with reason: #{inspect(reason)}")
    state
  end

  defp start_runtime(config) do
    wrapper = Application.app_dir(:lightning, "priv/runtime/wrapper")

    {:ok, pid} =
      Task.start_link(fn ->
        System.cmd(wrapper, [config.runtime_path, config.lightning_url],
          into: IO.stream()
        )
      end)

    %{config | runtime_pid: pid}
  end
end

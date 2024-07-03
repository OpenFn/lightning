defmodule Lightning.Runtime.RuntimeManagerTest do
  use ExUnit.Case, async: false

  alias Lightning.Runtime.RuntimeManager

  defmodule RuntimeClient do
    @behaviour Lightning.Runtime.RuntimeManager.RuntimeClient

    @impl true
    def start_runtime(state) do
      port = Port.open({:spawn, "cat"}, [:binary])
      %{state | runtime_port: port}
    end

    @impl true
    def stop_runtime(state) do
      Port.close(state.runtime_port)
      send(self(), {state.runtime_port, {:exit_status, 143}})
    end
  end

  defmodule CleanupClient do
    def cleanup_time do
      10
    end

    def start_runtime(state) do
      port = Port.open({:spawn, "cat"}, [:binary])
      %{state | runtime_port: port}
    end

    def stop_runtime(state) do
      Port.close(state.runtime_port)

      Process.send_after(
        self(),
        {state.runtime_port, {:exit_status, 143}},
        cleanup_time()
      )
    end
  end

  test "the runtime manager does not start when start is set to false", %{
    test: test
  } do
    assert {:ok, server} =
             start_server(test, runtime_client: RuntimeClient, start: true)

    assert Process.alive?(server)

    assert {:ok, :undefined} ==
             start_server(:test_start_false,
               runtime_client: RuntimeClient,
               start: false
             )
  end

  test "on timeout, the runtime manager exits with premature termination",
       %{test: test} do
    {:ok, server} = start_server(test)

    Process.monitor(server)
    send(server, :timeout)

    assert_receive {:DOWN, _ref, :process, ^server, :premature_termination}
  end

  test "the runtime manager stops if the runtime exits", %{test: test} do
    {:ok, server} = start_server(test)
    Process.monitor(server)

    state = :sys.get_state(server)
    send(server, {:EXIT, state.runtime_port, :normal})

    assert_receive {:DOWN, _ref, :process, ^server, :premature_termination}
  end

  test "the runtime manager waits for the runtime to complete processing before shutting down",
       %{test: test} do
    {:ok, server} =
      start_server(test, runtime_client: CleanupClient, start: true)

    Process.monitor(server)

    spawn_link(fn -> :ok = GenServer.stop(server) end)

    assert Process.alive?(server)
    refute_received {:DOWN, _ref, :process, ^server, :normal}

    assert_receive {:DOWN, _ref, :process, ^server, :normal},
                   CleanupClient.cleanup_time() + 3
  end

  test "the runtime manager updates the buffer for NOEOL messages",
       %{test: test} do
    {:ok, server} = start_server(test)

    state = :sys.get_state(server)

    send(server, {state.runtime_port, {:data, {:noeol, ~c"H"}}})
    updated_state = :sys.get_state(server)
    assert IO.iodata_to_binary(updated_state.buffer) == "H"
    send(server, {state.runtime_port, {:data, {:noeol, ~c"e"}}})

    updated_state = :sys.get_state(server)

    refute updated_state.buffer == state.buffer
    assert IO.iodata_to_binary(updated_state.buffer) == "eH"
  end

  test "the runtime manager updates the buffer for EOL messages",
       %{test: test} do
    {:ok, server} = start_server(test)

    state = :sys.get_state(server)

    send(server, {state.runtime_port, {:data, {:noeol, ~c"H"}}})

    updated_state = :sys.get_state(server)
    assert IO.iodata_to_binary(updated_state.buffer) == "H"

    send(server, {state.runtime_port, {:data, {:eol, ~c"e"}}})

    updated_state = :sys.get_state(server)

    assert updated_state.buffer == []
  end

  defp start_server(
         test,
         opts \\ [runtime_client: RuntimeClient, start: true]
       ) do
    name = Module.concat([__MODULE__, test, RuntimeManager])

    child_spec = %{
      id: name,
      restart: :temporary,
      shutdown: 10,
      start: {RuntimeManager, :start_link, [Keyword.merge(opts, name: name)]}
    }

    start_supervised(child_spec)
  end
end

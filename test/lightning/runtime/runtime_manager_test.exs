defmodule Lightning.Runtime.RuntimeManagerTest do
  use ExUnit.Case

  alias Lightning.Runtime.RuntimeManager

  @line_runtime_path Path.expand("../../support/runtime_per_line", __DIR__)
  # @char_runtime_path Path.expand("../../support/runtime_per_char", __DIR__)

  @default_config [
    start: true,
    version: "0.1.0",
    args: ["Hello world 😎", "0.2", "0"],
    cd: Path.expand("..", __DIR__),
    env: %{"TEST" => "hello", "STOP" => nil},
    path: @line_runtime_path
  ]

  setup do
    Application.put_env(:lightning, RuntimeManager, @default_config)

    on_exit(fn ->
      Application.put_env(:lightning, RuntimeManager, @default_config)
    end)
  end

  test "the runtime manager does not start when start is set to false" do
    assert {:ok, _server} = RuntimeManager.start_link(name: __MODULE__)

    Application.put_env(:lightning, RuntimeManager, start: false)

    assert :ignore ==
             RuntimeManager.start_link(name: :test_start_false)
  end

  test "the runtime manager logs a warning when version is not configured",
       %{test: test} do
    config = Keyword.merge(@default_config, version: nil)
    Application.put_env(:lightning, RuntimeManager, config)

    assert ExUnit.CaptureLog.capture_log(fn ->
             RuntimeManager.start_link(name: test)
           end) =~
             "runtime version is not configured. Please set it in your config files"
  end

  test "the runtime manager waits for a certain timeout when the runtime exits",
       %{test: test} do
    timeout = 0
    {:ok, server} = RuntimeManager.start_link(name: test)

    state = :sys.get_state(server)
    exit_status = 2

    assert ExUnit.CaptureLog.capture_log(fn ->
             assert {:noreply, ^state, ^timeout} =
                      RuntimeManager.handle_info(
                        {state.runtime_port, {:exit_status, exit_status}},
                        state
                      )
           end) =~ "Runtime exited with status: #{exit_status}"
  end

  test "on timeout, the runtime manager exits with premature termination",
       %{test: test} do
    {:ok, server} = RuntimeManager.start_link(name: test)

    state = :sys.get_state(server)

    assert {:stop, :premature_termination, ^state} =
             RuntimeManager.handle_info(:timeout, state)
  end

  @tag :capture_log
  test "the runtime manager stops if the runtime exits" do
    server =
      start_supervised!(
        {RuntimeManager, [[name: :test_exit]]},
        restart: :temporary
      )

    Process.monitor(server)

    state = :sys.get_state(server)
    send(server, {:EXIT, state.runtime_port, :normal})

    assert_receive {:DOWN, _ref, :process, ^server, :premature_termination}
  end

  @tag :capture_log
  test "the runtime manager waits for the runtime to complete processing before shutting down",
       %{test: test} do
    cleanup_time = 0.2
    {:ok, server} = start_server(test, "Hello World 😎", 0.2, cleanup_time)
    Process.flag(:trap_exit, true)
    Process.link(server)

    spawn_link(fn -> :ok = GenServer.stop(server) end)

    assert Process.alive?(server)
    refute_received {:EXIT, ^server, :normal}

    assert_receive {:EXIT, ^server, :normal}, round((cleanup_time + 0.2) * 1000)
  end

  test "the runtime manager receives end of line (EOL) messages",
       %{test: test} do
    string_to_print = "Hello World 😎"
    {:ok, server} = start_server(test, string_to_print, 1, 1)
    state = :sys.get_state(server)
    port = state.runtime_port
    Port.connect(port, self())

    assert_receive {^port, {:data, {:eol, ^string_to_print}}}, 1000

    # unlink the port
    Port.connect(port, server)
    Process.unlink(port)
  end

  test "the runtime manager updates the buffer for NOEL messages",
       %{test: test} do
    {:ok, server} = RuntimeManager.start_link(name: test)

    state = :sys.get_state(server)

    state = %{state | buffer: ~c"H"}

    assert {:noreply, updated_state} =
             RuntimeManager.handle_info(
               {state.runtime_port, {:data, {:noeol, ~c"e"}}},
               state
             )

    refute updated_state.buffer == state.buffer
    assert IO.iodata_to_binary(updated_state.buffer) == "eH"
  end

  defp start_server(
         test,
         line_to_print,
         interval,
         cleanup_time,
         override_opts \\ []
       ) do
    config =
      @default_config
      |> Keyword.merge(
        args: ["#{line_to_print}", "#{interval}", "#{cleanup_time}"]
      )
      |> Keyword.merge(override_opts)

    Application.put_env(
      :lightning,
      RuntimeManager,
      config
    )

    name = Module.concat([__MODULE__, test, RuntimeManager])

    child_spec = %{
      id: RuntimeManager,
      restart: :temporary,
      shutdown: 10_000,
      start: {RuntimeManager, :start_link, [[name: name]]}
    }

    start_supervised(child_spec)
  end
end

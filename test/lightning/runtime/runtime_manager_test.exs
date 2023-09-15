defmodule Lightning.Runtime.RuntimeManagerTest do
  use ExUnit.Case

  alias Lightning.Runtime.RuntimeManager

  @line_runtime_path Path.expand("../../support/runtime_per_line", __DIR__)
  # @char_runtime_path Path.expand("../../support/runtime_per_char", __DIR__)

  @default_config [
    start: true,
    version: "0.1.0",
    args: ["Hello world 😎", "0.2", "0"],
    env: %{},
    path: @line_runtime_path
  ]

  setup do
    Application.put_env(
      :lightning,
      RuntimeManager,
      @default_config
    )

    on_exit(fn ->
      Application.put_env(
        :lightning,
        RuntimeManager,
        @default_config
      )
    end)
  end

  test "bin_version/0 returns correct version" do
    path = Application.app_dir(:lightning, "priv/runtime/fake_runtime")
    config = Keyword.merge(@default_config, path: path)

    Application.put_env(:lightning, RuntimeManager, config)

    latest_version = RuntimeManager.latest_version()
    assert {:ok, ^latest_version} = RuntimeManager.bin_version()
  end

  test "bin_path/0 returns the configured path" do
    assert RuntimeManager.bin_path() == @default_config[:path]
  end

  test "the runtime manager does not start when start is set to false" do
    assert {:ok, _server} = RuntimeManager.start_link(name: __MODULE__)

    Application.put_env(:lightning, RuntimeManager, start: false)

    assert :ignore ==
             RuntimeManager.start_link(name: :test_start_false)
  end

  test "the runtime manager stops if the runtime exits" do
    Process.flag(:trap_exit, true)
    {:ok, server} = RuntimeManager.start_link(name: :test_exit)

    state = :sys.get_state(server)
    send(server, {:EXIT, state.runtime_port, :normal})

    Process.sleep(20)
    refute Process.alive?(server)
  end

  test "the runtime manager waits for the runtime to complete processing before shutting down",
       %{test: test} do
    cleanup_time = 0.5
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
      restart: :transient,
      shutdown: 10_000,
      start: {RuntimeManager, :start_link, [[name: name]]}
    }

    start_supervised(child_spec)
  end
end

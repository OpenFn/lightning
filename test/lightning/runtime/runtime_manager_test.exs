defmodule Lightning.Runtime.RuntimeManagerTest do
  use ExUnit.Case

  alias Lightning.Runtime.RuntimeManager

  @default_config [
    start: true,
    version: "0.1.0",
    args: ["Hello world 😎", "1", "3"],
    env: %{},
    path: Path.expand("../../support/runtime_dummy", __DIR__)
  ]

  setup do
    Application.put_env(
      :lightning,
      Lightning.Runtime.RuntimeManager,
      @default_config
    )

    on_exit(fn ->
      Application.put_env(
        :lightning,
        Lightning.Runtime.RuntimeManager,
        @default_config
      )
    end)
  end

  test "the runtime manager does not start when start is set to false" do
    assert {:ok, _server} = RuntimeManager.start_link(name: __MODULE__)

    Application.put_env(:lightning, RuntimeManager, start: false)

    assert :ignore ==
             RuntimeManager.start_link(name: :test_start_false)
  end

  test "the runtime manager waits for the runtime to complete processing before shutting down",
       %{test: test} do
    cleanup_time = 3
    {:ok, server} = start_server(test, "Hello World 😎", 1, cleanup_time)
    Process.flag(:trap_exit, true)
    Process.link(server)

    spawn_link(fn -> :ok = GenServer.stop(server) end)

    assert Process.alive?(server)
    refute_received {:EXIT, ^server, :normal}, 1000

    assert_receive {:EXIT, ^server, :normal}, (cleanup_time + 2) * 1000
  end

  defp start_server(test, line_to_print, interval, cleanup_time \\ 3) do
    config =
      Keyword.merge(@default_config,
        args: ["#{line_to_print}", "#{interval}", "#{cleanup_time}"]
      )

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

defmodule Lightning.Adaptors.ChannelBroadcasterTest do
  @moduledoc """
  Exercises `Lightning.Adaptors.ChannelBroadcaster` through its real
  message interface: broadcasting `{:changed, name, source}` tuples onto
  `:source_topic` and asserting what it forwards to `:client_topic`.
  """

  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup do
    sup = :"cb_test_#{System.unique_integer([:positive])}"

    # :rest_for_one starts the ChannelBroadcaster automatically, registered
    # under `channel_broadcaster_name(sup)`.
    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    source_topic = AdaptorsSupervisor.source_topic(sup)
    client_topic = AdaptorsSupervisor.client_topic(sup)
    cb_name = AdaptorsSupervisor.channel_broadcaster_name(sup)

    :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, client_topic)

    {:ok, cb_name: cb_name, source_topic: source_topic}
  end

  defp changed(source_topic, name) do
    Phoenix.PubSub.broadcast!(
      Lightning.PubSub,
      source_topic,
      {:changed, name, :npm}
    )
  end

  describe "handle_info/2 - :flush" do
    test "broadcasts just the changed adaptor's name", %{
      source_topic: source_topic
    } do
      changed(source_topic, "@openfn/language-http")

      assert_receive %{
                       event: "adaptors_updated",
                       payload: %{names: ["@openfn/language-http"]}
                     },
                     500
    end

    test "two adaptors changing within one debounce window are both named in a single broadcast",
         %{source_topic: source_topic} do
      changed(source_topic, "@openfn/language-salesforce")
      changed(source_topic, "@openfn/language-http")
      # Duplicate: must not appear twice in the output.
      changed(source_topic, "@openfn/language-http")

      assert_receive %{
                       event: "adaptors_updated",
                       payload: %{
                         names: [
                           "@openfn/language-http",
                           "@openfn/language-salesforce"
                         ]
                       }
                     },
                     500

      refute_receive %{event: "adaptors_updated"}, 100

      # A second, separate burst must not still carry the first burst's
      # names — the accumulator has to reset after :flush.
      changed(source_topic, "@openfn/language-dhis2")

      assert_receive %{
                       event: "adaptors_updated",
                       payload: %{names: ["@openfn/language-dhis2"]}
                     },
                     500
    end
  end

  describe "crash recovery" do
    test "supervisor restarts the GenServer; next {:changed} re-arms cleanly", %{
      cb_name: cb_name,
      source_topic: source_topic
    } do
      original_pid = Process.whereis(cb_name)
      assert is_pid(original_pid)

      ref = Process.monitor(original_pid)

      changed(source_topic, "@openfn/language-http")

      Process.exit(original_pid, :kill)

      assert_receive {:DOWN, ^ref, :process, ^original_pid, :killed}, 500

      new_pid = await_registered(cb_name)
      assert is_pid(new_pid)
      assert new_pid != original_pid

      # The restarted GenServer starts with timer: nil and an empty
      # names accumulator, so this reopens a fresh window.
      changed(source_topic, "@openfn/language-http")

      assert_receive %{
                       event: "adaptors_updated",
                       payload: %{names: ["@openfn/language-http"]}
                     },
                     500
    end
  end

  describe "leading-edge throttle invariant" do
    test "a 10ms drip over 500ms yields multiple broadcasts, not 0 and not one-per-message",
         %{source_topic: source_topic} do
      task =
        Task.async(fn ->
          for _ <- 1..50 do
            changed(source_topic, "@openfn/language-http")
            Process.sleep(10)
          end
        end)

      Task.await(task, 3_000)
      # Allow time for the final flush window to fire.
      Process.sleep(300)

      count = drain_broadcasts()

      assert count > 0 and count < 50,
             "Expected leading-edge throttling (1..49), got #{count}"
    end
  end

  defp await_registered(name, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 500

    case Process.whereis(name) do
      nil ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          await_registered(name, deadline)
        else
          raise "#{inspect(name)} did not restart within 500ms"
        end

      pid ->
        pid
    end
  end

  defp drain_broadcasts(acc \\ 0) do
    receive do
      %{event: "adaptors_updated"} -> drain_broadcasts(acc + 1)
    after
      0 -> acc
    end
  end
end

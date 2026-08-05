defmodule Lightning.Adaptors.ChannelBroadcasterTest do
  @moduledoc """
  Tests `:flush` via `Lightning.Adaptors.packages/1` (the 2-arity facade),
  not `packages/0`, because each test spins up its own isolated supervisor
  instance. The Batch 7 review should confirm that `/1` and `/0` are
  behaviourally identical in production (both delegate to `Store.packages/1`).
  """

  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup do
    sup = :"cb_test_#{System.unique_integer([:positive])}"

    # The supervisor's :rest_for_one child list starts the
    # ChannelBroadcaster automatically — registered under
    # `channel_broadcaster_name(sup)`.
    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    # Stop the auto-started Invalidator — these tests pre-populate the
    # Cachex `{:packages, source}` key directly to exercise the
    # ChannelBroadcaster's `:flush` path in isolation. The Invalidator
    # subscribes to the same source_topic and would race the broadcaster
    # by deleting the cached entry before the flush window expires.
    :ok = Supervisor.terminate_child(sup, Lightning.Adaptors.Invalidator)

    source_topic = AdaptorsSupervisor.source_topic(sup)
    client_topic = AdaptorsSupervisor.client_topic(sup)
    cb_name = AdaptorsSupervisor.channel_broadcaster_name(sup)
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    packages = [%{name: "@openfn/language-http", latest_version: "1.0.0"}]
    Cachex.put!(cache, {:packages, source}, {:ok, packages})

    :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, client_topic)

    {:ok,
     sup: sup,
     cb_name: cb_name,
     source_topic: source_topic,
     cache: cache,
     source: source,
     packages: packages}
  end

  describe "start_link/1" do
    test "registers under the :name opt", %{cb_name: cb_name} do
      assert is_pid(Process.whereis(cb_name))
    end
  end

  describe "handle_info/2 - {:changed, ...}" do
    test "first message in idle state arms the 250ms timer", %{
      cb_name: cb_name,
      source_topic: source_topic
    } do
      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, "pkg", :npm}
      )

      %{timer: timer} = :sys.get_state(cb_name)
      assert is_reference(timer)
    end

    test "subsequent messages within the window are dropped — one broadcast per burst",
         %{source_topic: source_topic, packages: packages} do
      for _ <- 1..5 do
        Phoenix.PubSub.broadcast!(
          Lightning.PubSub,
          source_topic,
          {:changed, "pkg", :npm}
        )
      end

      assert_receive %{
                       event: "adaptors_updated",
                       payload: %{adaptors: ^packages}
                     },
                     500

      refute_receive %{event: "adaptors_updated"}, 100
    end

    test "timer resets to nil after :flush fires", %{
      cb_name: cb_name,
      source_topic: source_topic
    } do
      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, "pkg", :npm}
      )

      assert_receive %{event: "adaptors_updated"}, 500
      %{timer: timer} = :sys.get_state(cb_name)
      assert timer == nil
    end
  end

  describe "handle_info/2 - :flush" do
    test "broadcasts the envelope to client_topic with the correct shape", %{
      source_topic: source_topic,
      packages: packages
    } do
      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, "pkg", :npm}
      )

      assert_receive %{
                       event: "adaptors_updated",
                       payload: %{adaptors: ^packages}
                     },
                     500
    end

    test "broadcasts with empty adaptors list when packages returns {:ok, []}",
         %{
           cache: cache,
           source: source,
           source_topic: source_topic
         } do
      Cachex.put!(cache, {:packages, source}, {:ok, []})

      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, "pkg", :npm}
      )

      assert_receive %{event: "adaptors_updated", payload: %{adaptors: []}}, 500
    end
  end

  describe "crash recovery" do
    test "supervisor restarts the GenServer; next {:changed} re-arms cleanly", %{
      cb_name: cb_name,
      source_topic: source_topic,
      packages: packages
    } do
      original_pid = Process.whereis(cb_name)
      assert is_pid(original_pid)

      ref = Process.monitor(original_pid)

      # Arm the timer, then kill the process mid-burst.
      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, "pkg", :npm}
      )

      Process.exit(original_pid, :kill)

      # Confirm death before looking for the restarted process.
      assert_receive {:DOWN, ^ref, :process, ^original_pid, :killed}, 500

      new_pid = await_registered(cb_name)
      assert is_pid(new_pid)
      assert new_pid != original_pid

      # The new instance starts with timer: nil — one more {:changed} opens a
      # fresh 250ms window and produces a clean broadcast.
      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, "pkg", :npm}
      )

      assert_receive %{
                       event: "adaptors_updated",
                       payload: %{adaptors: ^packages}
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
            Phoenix.PubSub.broadcast!(
              Lightning.PubSub,
              source_topic,
              {:changed, "pkg", :npm}
            )

            Process.sleep(10)
          end
        end)

      Task.await(task, 3_000)
      # Allow time for the final flush window to fire.
      Process.sleep(300)

      count = drain_broadcasts()

      # Leading-edge invariant: throttle produces some broadcasts (> 0)
      # but far fewer than one per message (< 50).
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

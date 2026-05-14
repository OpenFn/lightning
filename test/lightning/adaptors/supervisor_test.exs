defmodule Lightning.Adaptors.SupervisorTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  describe "start_link/1" do
    test "raises KeyError when :name is missing" do
      assert_raise KeyError, ~r/key :name not found/, fn ->
        AdaptorsSupervisor.start_link([])
      end
    end

    test "raises KeyError when opts has no :name key" do
      assert_raise KeyError, fn ->
        AdaptorsSupervisor.start_link(strategy: :ignored)
      end
    end
  end

  describe "derived-name helpers" do
    test "cache_name/1 concatenates `Cache` onto the supervisor name" do
      assert AdaptorsSupervisor.cache_name(Lightning.Adaptors) ==
               Lightning.Adaptors.Cache

      assert AdaptorsSupervisor.cache_name(:MyAdaptors) ==
               Module.concat(:MyAdaptors, Cache)
    end

    test "tasks_name/1 concatenates `Tasks` onto the supervisor name" do
      assert AdaptorsSupervisor.tasks_name(Lightning.Adaptors) ==
               Lightning.Adaptors.Tasks
    end

    test "invalidator_name/1 concatenates `Invalidator` onto the supervisor name" do
      assert AdaptorsSupervisor.invalidator_name(Lightning.Adaptors) ==
               Lightning.Adaptors.Invalidator
    end

    test "channel_broadcaster_name/1 concatenates `ChannelBroadcaster`" do
      assert AdaptorsSupervisor.channel_broadcaster_name(Lightning.Adaptors) ==
               Lightning.Adaptors.ChannelBroadcaster
    end

    test "node_monitor_name/1 concatenates `NodeMonitor`" do
      assert AdaptorsSupervisor.node_monitor_name(Lightning.Adaptors) ==
               Lightning.Adaptors.NodeMonitor
    end

    test "scheduler_name/1 concatenates `Scheduler`" do
      assert AdaptorsSupervisor.scheduler_name(Lightning.Adaptors) ==
               Lightning.Adaptors.Scheduler
    end

    test "source_topic/1 returns an `adaptors:<inspect name>` string" do
      assert AdaptorsSupervisor.source_topic(Lightning.Adaptors) ==
               "adaptors:Lightning.Adaptors"
    end

    test "client_topic/1 returns an `adaptors:client_update:<inspect name>` string" do
      assert AdaptorsSupervisor.client_topic(Lightning.Adaptors) ==
               "adaptors:client_update:Lightning.Adaptors"
    end

    test "source_topic/1 and client_topic/1 produce distinct strings" do
      name = Lightning.Adaptors

      refute AdaptorsSupervisor.source_topic(name) ==
               AdaptorsSupervisor.client_topic(name)
    end

    test "lock_key/1 derives an int via :erlang.phash2({:adaptors, name})" do
      name = Lightning.Adaptors

      assert AdaptorsSupervisor.lock_key(name) ==
               :erlang.phash2({:adaptors, name})
    end

    test "lock_key/1 of a name differs from phash2 of just the name" do
      name = :"Adaptors_#{System.unique_integer([:positive])}"

      assert AdaptorsSupervisor.lock_key(name) != :erlang.phash2(name)
    end
  end

  describe "two concurrent supervisors do not collide" do
    test "derived Cachex / Task.Supervisor / GenServer names differ between instances" do
      a = :"AdaptorsA_#{System.unique_integer([:positive])}"
      b = :"AdaptorsB_#{System.unique_integer([:positive])}"

      assert AdaptorsSupervisor.cache_name(a) !=
               AdaptorsSupervisor.cache_name(b)

      assert AdaptorsSupervisor.tasks_name(a) !=
               AdaptorsSupervisor.tasks_name(b)

      assert AdaptorsSupervisor.invalidator_name(a) !=
               AdaptorsSupervisor.invalidator_name(b)

      assert AdaptorsSupervisor.channel_broadcaster_name(a) !=
               AdaptorsSupervisor.channel_broadcaster_name(b)

      assert AdaptorsSupervisor.node_monitor_name(a) !=
               AdaptorsSupervisor.node_monitor_name(b)

      assert AdaptorsSupervisor.scheduler_name(a) !=
               AdaptorsSupervisor.scheduler_name(b)
    end

    test "PubSub topics differ between instances" do
      a = :"AdaptorsA_#{System.unique_integer([:positive])}"
      b = :"AdaptorsB_#{System.unique_integer([:positive])}"

      assert AdaptorsSupervisor.source_topic(a) !=
               AdaptorsSupervisor.source_topic(b)

      assert AdaptorsSupervisor.client_topic(a) !=
               AdaptorsSupervisor.client_topic(b)
    end

    test "HighlanderPG lock keys differ between instances" do
      a = :"AdaptorsA_#{System.unique_integer([:positive])}"
      b = :"AdaptorsB_#{System.unique_integer([:positive])}"

      assert AdaptorsSupervisor.lock_key(a) !=
               AdaptorsSupervisor.lock_key(b)
    end

    test "production-equivalent lock key is stable across calls" do
      first = AdaptorsSupervisor.lock_key(Lightning.Adaptors)
      second = AdaptorsSupervisor.lock_key(Lightning.Adaptors)

      assert first == second
      assert is_integer(first)
    end
  end

  describe "init/1 (child spec list)" do
    # The Supervisor's children (`Invalidator`, `ChannelBroadcaster`,
    # `NodeMonitor`, `Scheduler`) and the `HighlanderPG` dep are
    # authored by sibling PRDs in later batches. Until they exist, we
    # cannot call `init/1` directly — `Supervisor.init/2` normalises
    # `{Module, opts}` child specs by calling `Module.child_spec/1`
    # against each, which would crash on the missing modules.
    #
    # The shape of the child list is exercised end-to-end by the §12.7
    # integration tests once all sibling modules land.

    test "init/1 requires the :name opt" do
      assert_raise KeyError, ~r/key :name not found/, fn ->
        AdaptorsSupervisor.init([])
      end
    end
  end
end

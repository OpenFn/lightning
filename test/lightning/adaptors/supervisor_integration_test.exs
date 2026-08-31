defmodule Lightning.Adaptors.SupervisorIntegrationTest do
  @moduledoc """
  Integration-level tests for `Lightning.Adaptors.Supervisor`: prove the full
  child list boots under a single `start_supervised!` call, and that a crash in
  any of the siblings restarts only that sibling, leaving the HighlanderPG
  Scheduler holding its advisory lock.
  """

  use Lightning.DataCase, async: false

  import Eventually

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  # Children with their *registered* names. We look up live PIDs by name
  # (Process.whereis/1) rather than by child id from which_children/1,
  # because module-based child specs share child ids like `Cachex` or
  # `Lightning.Adaptors.Invalidator` — those don't carry the per-instance
  # name we derive in the Supervisor. The Scheduler is registered via
  # `:global` (HighlanderPG-wrapped) so it needs a `:global.whereis_name/1`
  # lookup instead.
  defp local_named_children(sup) do
    %{
      cache: AdaptorsSupervisor.cache_name(sup),
      tasks: AdaptorsSupervisor.tasks_name(sup),
      invalidator: AdaptorsSupervisor.invalidator_name(sup),
      node_monitor: AdaptorsSupervisor.node_monitor_name(sup),
      broadcaster: AdaptorsSupervisor.channel_broadcaster_name(sup)
    }
  end

  defp scheduler_pid(sup) do
    {:global, global_name} = AdaptorsSupervisor.global_scheduler_name(sup)

    case :global.whereis_name(global_name) do
      :undefined -> nil
      pid -> pid
    end
  end

  defp pids_by_role(sup) do
    locals =
      sup
      |> local_named_children()
      |> Enum.map(fn {role, registered_name} ->
        {role, Process.whereis(registered_name)}
      end)
      |> Map.new()

    Map.put(locals, :scheduler, scheduler_pid(sup))
  end

  # HighlanderPG polls every 300ms by default; allow ~3s for the
  # wrapped child to acquire the advisory lock and register globally.
  @scheduler_wait_ms 3_000

  setup do
    sup = :"test_full_boot_#{System.unique_integer([:positive])}"
    on_exit(fn -> AdaptorsSupervisor.forget(sup) end)
    {:ok, sup: sup}
  end

  describe "child-list boot" do
    test "boots the full child list under one start_supervised! call",
         %{sup: sup} do
      pid =
        start_supervised!(
          {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.Local}
        )

      children = Supervisor.which_children(pid)

      # Cachex + Task.Supervisor + Invalidator + NodeMonitor +
      # ChannelBroadcaster + HighlanderPG(Scheduler) = 6.
      assert length(children) == 6

      ids = Enum.map(children, fn {id, _pid, _type, _mods} -> id end)
      assert AdaptorsSupervisor.highlander_name(sup) in ids

      Enum.each(children, fn {_id, child_pid, _type, _mods} ->
        assert is_pid(child_pid),
               "unexpected child pid shape: #{inspect(child_pid)}"

        assert Process.alive?(child_pid),
               "child pid #{inspect(child_pid)} is not alive"
      end)

      # Locally-registered children are up under their derived names.
      Enum.each(local_named_children(sup), fn {role, registered_name} ->
        pid = Process.whereis(registered_name)
        assert is_pid(pid), "expected #{role} to be registered and alive"
        assert Process.alive?(pid)
      end)

      # The HighlanderPG-wrapped Scheduler registers globally once it
      # acquires the advisory lock — give it up to ~3s to do so.
      assert_eventually(is_pid(scheduler_pid(sup)), @scheduler_wait_ms)
      assert Process.alive?(scheduler_pid(sup))
    end

    test "exposes the per-instance strategy and source via :persistent_term",
         %{sup: sup} do
      start_supervised!(
        {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.Local}
      )

      assert AdaptorsSupervisor.strategy(sup) == Lightning.Adaptors.Local
      assert AdaptorsSupervisor.source(sup) == :local
    end
  end

  describe ":one_for_one strategy" do
    # Two victims only: the supervisor's default max_restarts is 3 in 5s,
    # and hitting that ceiling would take the whole instance down for
    # reasons that have nothing to do with what we're asserting. `:tasks`
    # is the interesting one — the Scheduler uses it on every tick, and
    # still doesn't need restarting alongside it.
    test "a sibling crash restarts only that sibling, leaving the Scheduler's leadership intact",
         %{sup: sup} do
      start_supervised!(
        {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.Local}
      )

      # Block until the HighlanderPG-wrapped Scheduler has registered
      # globally so we have a baseline pid to compare against.
      assert_eventually(is_pid(scheduler_pid(sup)), @scheduler_wait_ms)

      leader = scheduler_pid(sup)
      highlander = Process.whereis(AdaptorsSupervisor.highlander_name(sup))

      for role <- [:tasks, :broadcaster] do
        victim = Map.fetch!(pids_by_role(sup), role)
        assert is_pid(victim)

        ref = Process.monitor(victim)
        Process.exit(victim, :kill)
        assert_receive {:DOWN, ^ref, :process, ^victim, _}, 1_000

        assert_eventually(
          is_pid(current_pid(sup, role)) and current_pid(sup, role) != victim,
          1_000
        )

        # HighlanderPG holds the advisory lock for as long as its wrapped
        # child lives, so an unchanged Scheduler pid is an unchanged
        # leader: no re-election, no lock handover.
        assert scheduler_pid(sup) == leader,
               "killing #{role} re-elected the Scheduler " <>
                 "(before=#{inspect(leader)}, after=#{inspect(scheduler_pid(sup))})"

        assert Process.alive?(leader)

        assert Process.whereis(AdaptorsSupervisor.highlander_name(sup)) ==
                 highlander
      end
    end
  end

  defp current_pid(sup, role), do: Map.get(pids_by_role(sup), role)
end

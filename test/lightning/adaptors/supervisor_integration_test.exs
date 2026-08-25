defmodule Lightning.Adaptors.SupervisorIntegrationTest do
  @moduledoc """
  Integration-level tests for `Lightning.Adaptors.Supervisor`: prove all
  Phase A children boot under a single `start_supervised!` call and that
  the `:rest_for_one` cascade pins §6.5a (Invalidator subscribes at init;
  if Cachex restarts without Invalidator restarting, the cache goes
  stale).
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

  describe ":rest_for_one strategy" do
    test "Cachex crash cascades to Invalidator / ChannelBroadcaster / Scheduler",
         %{sup: sup} do
      start_supervised!(
        {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.Local}
      )

      # Block until the HighlanderPG-wrapped Scheduler has registered
      # globally so we have a baseline pid to compare against.
      assert_eventually(is_pid(scheduler_pid(sup)), @scheduler_wait_ms)

      before = pids_by_role(sup)

      cachex_pid = Map.fetch!(before, :cache)
      assert is_pid(cachex_pid)

      ref = Process.monitor(cachex_pid)
      Process.exit(cachex_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^cachex_pid, _}, 1_000

      after_pids = wait_for_restart(sup, before)

      # Cachex itself comes back under a fresh pid.
      assert Map.fetch!(after_pids, :cache) != cachex_pid

      # §6.5a: under :rest_for_one, all children that depend on Cachex
      # (Invalidator, Broadcaster, Scheduler) must restart too so they
      # re-bind to the fresh cache.
      for role <- [:invalidator, :broadcaster, :scheduler] do
        old = Map.fetch!(before, role)
        new = Map.fetch!(after_pids, role)
        assert is_pid(old)
        assert is_pid(new)

        assert new != old,
               "expected #{role} to restart after Cachex crash " <>
                 "(before=#{inspect(old)}, after=#{inspect(new)})"
      end
    end
  end

  # Polls `pids_by_role/1` until the children we expect to be restarted
  # show new PIDs, or we hit the deadline. Returns the post-restart map.
  # The Scheduler restart goes through HighlanderPG (lock + poll cycle),
  # so allow a slightly longer deadline than for the locally-registered
  # children alone.
  defp wait_for_restart(sup, before, deadline_ms \\ 3_000) do
    start = System.monotonic_time(:millisecond)
    roles_expected = [:invalidator, :broadcaster, :scheduler]
    do_wait_for_restart(sup, before, roles_expected, start, deadline_ms)
  end

  defp do_wait_for_restart(sup, before, roles, start, deadline_ms) do
    current = pids_by_role(sup)

    changed? =
      Enum.all?(roles, fn role ->
        case {Map.get(before, role), Map.get(current, role)} do
          {old, new} when is_pid(old) and is_pid(new) -> old != new
          _ -> false
        end
      end)

    cond do
      changed? ->
        current

      System.monotonic_time(:millisecond) - start > deadline_ms ->
        flunk(
          "supervisor children did not restart within #{deadline_ms}ms; " <>
            "before=#{inspect(before)} after=#{inspect(current)}"
        )

      true ->
        Process.sleep(20)
        do_wait_for_restart(sup, before, roles, start, deadline_ms)
    end
  end
end

defmodule Lightning.Adaptors.SupervisorIntegrationTest do
  @moduledoc """
  Integration-level tests for `Lightning.Adaptors.Supervisor`: prove all
  Phase A children boot under a single `start_supervised!` call and that
  the `:rest_for_one` cascade pins §6.5a (Invalidator subscribes at init;
  if Cachex restarts without Invalidator restarting, the cache goes
  stale).
  """

  use Lightning.DataCase, async: false

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  # Children with their *registered* names. We look up live PIDs by name
  # (Process.whereis/1) rather than by child id from which_children/1,
  # because module-based child specs share child ids like `Cachex` or
  # `Lightning.Adaptors.Invalidator` — those don't carry the per-instance
  # name we derive in the Supervisor.
  defp named_children(sup) do
    %{
      cache: AdaptorsSupervisor.cache_name(sup),
      tasks: AdaptorsSupervisor.tasks_name(sup),
      invalidator: AdaptorsSupervisor.invalidator_name(sup),
      node_monitor: AdaptorsSupervisor.node_monitor_name(sup),
      broadcaster: AdaptorsSupervisor.channel_broadcaster_name(sup),
      scheduler: AdaptorsSupervisor.scheduler_name(sup)
    }
  end

  defp pids_by_role(sup) do
    sup
    |> named_children()
    |> Enum.map(fn {role, registered_name} ->
      {role, Process.whereis(registered_name)}
    end)
    |> Map.new()
  end

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

      # Cachex + CacheClear Task + Task.Supervisor + Invalidator +
      # NodeMonitor + ChannelBroadcaster + Scheduler = 7.
      assert length(children) == 7

      Enum.each(children, fn {_id, child_pid, _type, _mods} ->
        # CacheClear is restart: :transient and may have already exited
        # cleanly by the time which_children/1 runs — that surfaces as
        # :undefined here, which is healthy.
        assert is_pid(child_pid) or child_pid == :undefined,
               "unexpected child pid shape: #{inspect(child_pid)}"

        if is_pid(child_pid) do
          assert Process.alive?(child_pid),
                 "child pid #{inspect(child_pid)} is not alive"
        end
      end)

      # Every long-lived registered child is up under its derived name.
      pids = pids_by_role(sup)

      Enum.each(pids, fn {role, role_pid} ->
        assert is_pid(role_pid), "expected #{role} to be registered and alive"
        assert Process.alive?(role_pid)
      end)
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
  defp wait_for_restart(sup, before, deadline_ms \\ 1_000) do
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

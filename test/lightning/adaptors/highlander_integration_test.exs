defmodule Lightning.Adaptors.HighlanderIntegrationTest do
  @moduledoc """
  §12.7 — verifies that the HighlanderPG-wrapped `Lightning.Adaptors.Scheduler`
  actually behaves as a cluster singleton when two supervisor instances
  compete for the same Postgres advisory lock.

  Both supervisors share an explicit `:lock_key` so they race for the
  same `pg_try_advisory_lock` bucket, but each keeps its own derived
  `:global` Scheduler name. Exactly one of them — the leader — registers
  a Scheduler under its `{:global, …}` name; the other's HighlanderPG
  polls and waits. When the leading supervisor stops (releasing its
  Postgres session and thus its advisory lock), the surviving instance
  must acquire the lock within ~2× the default 300ms polling interval
  and register its own Scheduler under its own `{:global, …}` name.
  """

  # async: false — real advisory locks coordinate against the test DB;
  # set_mox_global so the StrategyMock is visible to the wrapped child
  # processes started by HighlanderPG.
  use Lightning.DataCase, async: false

  import Eventually
  import Mox

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup :set_mox_global
  setup :verify_on_exit!

  # Both supervisors come up with refresh_interval=0 (default in config/test.exs)
  # so the inert Scheduler's init does no DB work; the test only cares about
  # HighlanderPG's leader election, not refresh behaviour.

  test "two supervisors sharing one lock_key: only one runs the Scheduler at a time; failover on leader shutdown" do
    suffix = System.unique_integer([:positive])
    sup_a = :"hl_a_#{suffix}"
    sup_b = :"hl_b_#{suffix}"
    shared_lock_key = :erlang.phash2({:adaptors_highlander_test, suffix})

    on_exit(fn ->
      AdaptorsSupervisor.forget(sup_a)
      AdaptorsSupervisor.forget(sup_b)
    end)

    {:ok, _pid_a} =
      start_supervised(
        Supervisor.child_spec(
          {AdaptorsSupervisor,
           name: sup_a,
           strategy: Lightning.Adaptors.StrategyMock,
           lock_key: shared_lock_key},
          id: :sup_a
        )
      )

    {:ok, _pid_b} =
      start_supervised(
        Supervisor.child_spec(
          {AdaptorsSupervisor,
           name: sup_b,
           strategy: Lightning.Adaptors.StrategyMock,
           lock_key: shared_lock_key},
          id: :sup_b
        )
      )

    {:global, gname_a} = AdaptorsSupervisor.global_scheduler_name(sup_a)
    {:global, gname_b} = AdaptorsSupervisor.global_scheduler_name(sup_b)

    # The advisory-lock race may go to either supervisor. Allow ~3s for
    # the winner's HighlanderPG to acquire the lock and start its child.
    assert_eventually(
      is_pid(:global.whereis_name(gname_a)) or
        is_pid(:global.whereis_name(gname_b)),
      3_000
    )

    leader_global =
      cond do
        is_pid(:global.whereis_name(gname_a)) -> gname_a
        is_pid(:global.whereis_name(gname_b)) -> gname_b
      end

    surviving_global =
      if leader_global == gname_a, do: gname_b, else: gname_a

    leader_sup = if leader_global == gname_a, do: sup_a, else: sup_b

    # Singleton invariant: only the leader's :global registration is
    # populated cluster-wide.
    assert :global.whereis_name(surviving_global) == :undefined,
           "expected only the leader to have a globally-registered Scheduler"

    # Stop the leader supervisor. start_supervised gave us a stable id
    # (:sup_a / :sup_b), so we can unambiguously target it for teardown.
    leader_id = if leader_sup == sup_a, do: :sup_a, else: :sup_b
    :ok = stop_supervised(leader_id)

    # The surviving HighlanderPG polls at 300ms by default; give it
    # comfortably more than 2× that interval to win the lock and start
    # its wrapped Scheduler under its own :global name.
    assert_eventually(is_pid(:global.whereis_name(surviving_global)), 3_000)

    # Sanity: the formerly-leading :global name is gone.
    assert :global.whereis_name(leader_global) == :undefined
  end
end

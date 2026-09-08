defmodule Lightning.Adaptors.SchedulerTest do
  # async: false — DataCase's shared sandbox mode means every process can
  # reach the DB without an allow/3 call, and set_mox_global is only safe
  # when tests run serially.
  use Lightning.DataCase, async: false

  import Lightning.AdaptorTestHelpers

  import Eventually
  import ExUnit.CaptureLog
  import Mox

  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  # set_mox_global makes expectations visible to tasks spawned by the Scheduler,
  # whose $callers chain does not include the test process (only the GenServer).
  setup :set_mox_global
  setup :verify_on_exit!

  # Each test owns an isolated supervisor. The supervisor starts its own
  # Scheduler as part of its child list, but with the test-env
  # `refresh_interval: 0` it's an inert no-op. Individual tests
  # call `start_scheduler/2` to replace it with a controlled-interval
  # Scheduler under `start_supervised!/1` (so Mox expectations can be
  # registered before init fires).
  setup do
    sup = :"sched_test_#{System.unique_integer([:positive])}"

    start_supervised!({
      AdaptorsSupervisor,
      # Keeps the auto-started scheduler a true inert no-op ahead of
      # start_scheduler/2 below — otherwise its boot-time max_checked_at
      # read logs an empty-catalogue warning on every test in this file.
      name: sup,
      strategy: Lightning.Adaptors.StrategyMock,
      checked_at: fn _source -> nil end
    })

    # Default no-op icons stub for tests that don't care about the icons
    # pipeline. Individual tests override via `expect` when they need to
    # assert on it.
    stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
      {:ok, %{}}
    end)

    {:ok, sup: sup}
  end

  # Replace the supervisor's inert auto-started (HighlanderPG-wrapped)
  # Scheduler with a controlled one under test ownership. Application
  # env is restored immediately after start_supervised!/1 returns
  # because the Scheduler captures interval_ms in init/1.
  #
  # The test-owned Scheduler bypasses HighlanderPG entirely: we
  # register the GenServer directly under the same `{:global, …}` name
  # the production wrapper would, so test code can call it via
  # `AdaptorsSupervisor.global_scheduler_name/1` exactly as production
  # callers do.
  defp start_scheduler(sup, opts \\ []) do
    interval = Keyword.get(opts, :interval, 99_999_999)
    original_env = Application.get_env(:lightning, Lightning.Adaptors, [])

    Application.put_env(
      :lightning,
      Lightning.Adaptors,
      Keyword.put(original_env, :refresh_interval, interval)
    )

    global_name = AdaptorsSupervisor.global_scheduler_name(sup)
    source_topic = AdaptorsSupervisor.source_topic(sup)

    # Stop the supervisor's auto-started HighlanderPG (and its wrapped
    # Scheduler) so we can start a replacement under the controlled
    # interval without name collision.
    :ok =
      Supervisor.terminate_child(sup, AdaptorsSupervisor.highlander_name(sup))

    scheduler_opts =
      [
        name: global_name,
        sup: sup,
        lock_key: AdaptorsSupervisor.lock_key(sup),
        cache: AdaptorsSupervisor.cache_name(sup),
        tasks: AdaptorsSupervisor.tasks_name(sup),
        source_topic: source_topic
      ] ++ Keyword.take(opts, [:checked_at])

    pid = start_supervised!({Scheduler, scheduler_opts})

    Application.put_env(:lightning, Lightning.Adaptors, original_env)

    pid
  end

  defp drain_tick_ran do
    receive do
      :tick_ran -> drain_tick_ran()
    after
      0 -> :ok
    end
  end

  describe "start_link/1" do
    test "raises when :name is missing", %{sup: sup} do
      assert_raise KeyError, ~r/key :name not found/, fn ->
        Scheduler.start_link(
          sup: sup,
          lock_key: 1,
          cache: :cache,
          tasks: :tasks,
          source_topic: "t"
        )
      end
    end

    test "raises when :sup is missing", %{sup: sup} do
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert_raise KeyError, ~r/key :sup not found/, fn ->
        Scheduler.start_link(
          name: sched_name,
          lock_key: 1,
          cache: :cache,
          tasks: :tasks,
          source_topic: "t"
        )
      end
    end

    test "raises when :lock_key is missing", %{sup: sup} do
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert_raise KeyError, ~r/key :lock_key not found/, fn ->
        Scheduler.start_link(
          name: sched_name,
          sup: sup,
          cache: :cache,
          tasks: :tasks,
          source_topic: "t"
        )
      end
    end

    test "registers under :global with global_scheduler_name/1", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn -> {:ok, []} end)
      start_scheduler(sup)
      {:global, global_name} = AdaptorsSupervisor.global_scheduler_name(sup)
      assert is_pid(:global.whereis_name(global_name))
    end
  end

  describe "tick timing" do
    test "tick fires on init when table is empty", %{sup: sup} do
      test_pid = self()

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :list_adaptors_called)
        {:ok, []}
      end)

      # Empty table → max_checked_at returns nil → delay 0 → tick fires on init.
      start_scheduler(sup)

      assert_receive :list_adaptors_called, 2000
    end

    test "tick re-arms itself", %{sup: sup} do
      test_pid = self()

      # Stub allows repeated calls; each fires a message so we can count them.
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :tick_ran)
        {:ok, []}
      end)

      # 30ms interval → two ticks fire well within 2s.
      start_scheduler(sup, interval: 30)

      assert_receive :tick_ran, 2000
      assert_receive :tick_ran, 2000
    end
  end

  describe "boot resilience" do
    test "a DB error reading max_checked_at does not crash the scheduler, and it ticks immediately",
         %{sup: sup} do
      test_pid = self()

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :list_adaptors_called)
        {:ok, []}
      end)

      start_scheduler(sup,
        checked_at: fn _source ->
          raise DBConnection.ConnectionError, "down"
        end
      )

      assert_receive :list_adaptors_called, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      {:global, gname} = sched_name
      assert is_pid(:global.whereis_name(gname))
    end

    test "a Postgrex.Error reading max_checked_at is not rescued and crashes the scheduler",
         %{sup: sup} do
      pid =
        start_scheduler(sup,
          checked_at: fn _source ->
            raise Postgrex.Error, message: "undefined_column"
          end
        )

      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 2000
      assert {%Postgrex.Error{}, _stacktrace} = reason
    end

    test "an empty catalogue logs a boot warning and still ticks when interval > 0",
         %{sup: sup} do
      test_pid = self()

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :tick_ran)
        {:ok, []}
      end)

      log =
        capture_log(fn ->
          start_scheduler(sup, checked_at: fn _source -> nil end, interval: 30)
          assert_receive :tick_ran, 2000
        end)

      assert log =~ "catalogue is empty at boot"
    end

    test "an empty catalogue logs a boot warning and schedules no tick when interval is 0",
         %{sup: sup} do
      test_pid = self()

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :tick_ran)
        {:ok, []}
      end)

      log =
        capture_log(fn ->
          start_scheduler(sup, checked_at: fn _source -> nil end, interval: 0)
          refute_receive :tick_ran, 200
        end)

      assert log =~ "catalogue is empty at boot"
    end
  end

  describe "do_refresh/1 diff logic" do
    test "unchanged adaptor: touch_checked_at only, no upsert, no broadcast", %{
      sup: sup
    } do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      {:ok, existing} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            schema_data: ~s({"type":"object"}),
            schema_sha256: "sha-1"
          )
        )

      checked_at_before = existing.checked_at

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :list_adaptors_called)
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      # With a recently-inserted adaptor, max_checked_at is "now", so the smart-
      # init delay is ~99,999 seconds. Trigger an explicit tick via refresh_now.
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      Scheduler.refresh_now(sched_name)

      assert_receive :list_adaptors_called, 2000

      # Allow the spawned task to complete before asserting no broadcast.
      refute_receive {:changed, _, _}

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert DateTime.compare(row.checked_at, checked_at_before) == :gt
      assert row.latest_version == "1.0.0"
    end

    test "matching version with no stored schema: refetch and persist it", %{
      sup: sup
    } do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(schema_data: nil, schema_sha256: nil)
        )

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          send(test_pid, :fetch_adaptor_called)

          {:ok,
           adaptor_record(
             schema_data: ~s({"type":"object"}),
             schema_sha256: "sha-1"
           )}
        end
      )

      start_scheduler(sup)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      Scheduler.refresh_now(sched_name)

      assert_receive :fetch_adaptor_called, 2000
      assert {:ok, %{fetched: 1}} = Scheduler.await_refresh(sched_name, 5_000)

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row.latest_version == "1.0.0"
      assert row.schema_data == ~s({"type":"object"})
      assert row.schema_sha256 == "sha-1"
    end

    test "matching version, still no schema upstream: touch only", %{sup: sup} do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      {:ok, existing} =
        Catalogue.upsert_adaptor(
          adaptor_record(schema_data: nil, schema_sha256: nil)
        )

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn
        "@openfn/language-http" ->
          send(test_pid, :fetch_adaptor_called)
          {:ok, adaptor_record(schema_data: nil, schema_sha256: nil)}
      end)

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      Scheduler.refresh_now(sched_name)

      assert_receive :fetch_adaptor_called, 2000

      assert {:ok, %{fetched: 0, changed: 0}} =
               Scheduler.await_refresh(sched_name, 5_000)

      refute_receive {:changed, _, _}

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert DateTime.compare(row.checked_at, existing.checked_at) == :gt
      assert row.updated_at == existing.updated_at
    end

    test "matching version, no stored schema, row older than the grace window: touch only",
         %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      {:ok, existing} =
        Catalogue.upsert_adaptor(
          adaptor_record(schema_data: nil, schema_sha256: nil)
        )

      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      {1, _} =
        Lightning.Repo.update_all(
          from(a in Lightning.Adaptors.Catalogue.Adaptor,
            where: a.id == ^existing.id
          ),
          set: [updated_at: two_hours_ago]
        )

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{fetched: 0, changed: 0, errors: 0}} =
               Scheduler.await_refresh(sched_name, 5_000)

      refute_receive {:changed, _, _}

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row.schema_data == nil
      assert DateTime.compare(row.checked_at, existing.checked_at) == :gt
    end

    test "changed adaptor: upsert and broadcast per changed name", %{sup: sup} do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :list_adaptors_called)
        {:ok, [%{name: "@openfn/language-http", latest_version: "2.0.0"}]}
      end)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          {:ok, adaptor_record(latest_version: "2.0.0")}
        end
      )

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      # Trigger an explicit tick since smart-init delay is large (recent checked_at).
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      Scheduler.refresh_now(sched_name)

      assert_receive :list_adaptors_called, 2000
      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row.latest_version == "2.0.0"
    end

    test "bumped version reporting no schema keeps the stored schema", %{
      sup: sup
    } do
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            schema_data: ~s({"type":"object"}),
            schema_sha256: "sha-1"
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "2.0.0"}]}
      end)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          {:ok,
           adaptor_record(
             latest_version: "2.0.0",
             schema_data: nil,
             schema_sha256: nil
           )}
        end
      )

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      Scheduler.refresh_now(sched_name)

      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row.latest_version == "2.0.0"
      assert row.schema_data == ~s({"type":"object"})
      assert row.schema_sha256 == "sha-1"
    end

    test "new adaptor (not in DB): upsert and broadcast", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-new", latest_version: "1.0.0"}]}
      end)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-new" ->
          {:ok, adaptor_record(name: "@openfn/language-new")}
        end
      )

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive {:changed, "@openfn/language-new", ^source}, 2000
      assert Catalogue.get_adaptor("@openfn/language-new", source) != nil
    end

    test "a failed fetch persists nothing, and the next tick retries", %{
      sup: sup
    } do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)
      name = "@openfn/language-new"

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 2, fn ->
        {:ok, [%{name: name, latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn ^name ->
        send(test_pid, :first_fetch)
        {:error, {:schema_fetch_failed, :timeout}}
      end)

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive :first_fetch, 2000
      refute_receive {:changed, _, _}
      assert Catalogue.get_adaptor(name, source) == nil

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn ^name ->
        {:ok, adaptor_record(name: name)}
      end)

      Scheduler.refresh_now(AdaptorsSupervisor.global_scheduler_name(sup))

      assert_receive {:changed, ^name, ^source}, 2000
      assert Catalogue.get_adaptor(name, source) != nil
    end

    test "list_adaptors error: no DB writes, no broadcasts", %{sup: sup} do
      test_pid = self()
      source_topic = AdaptorsSupervisor.source_topic(sup)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :list_adaptors_called)
        {:error, :timeout}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive :list_adaptors_called, 2000
      refute_receive {:changed, _, _}
    end

    test "fetch_adaptor error: logs warning, continues to next adaptor", %{
      sup: sup
    } do
      source_topic = AdaptorsSupervisor.source_topic(sup)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok,
         [
           %{name: "@openfn/bad-adaptor", latest_version: "1.0.0"},
           %{name: "@openfn/good-adaptor", latest_version: "1.0.0"}
         ]}
      end)

      # Single multi-clause expectation — Mox routes by pattern within
      # one slot, so Scheduler's async_stream_nolink can fan out to the
      # two adaptors in either order. Two separate `expect/4` calls
      # would dispatch FIFO and crash with FunctionClauseError when the
      # task arrival order doesn't match the expectation insertion order.
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 2, fn
        "@openfn/bad-adaptor" ->
          {:error, :not_found}

        "@openfn/good-adaptor" ->
          {:ok, adaptor_record(name: "@openfn/good-adaptor")}
      end)

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive {:changed, "@openfn/good-adaptor", _}, 2000
      refute_receive {:changed, "@openfn/bad-adaptor", _}, 200
    end
  end

  describe "fetch timeout" do
    test "per-adaptor fetch is bounded by the strategy's http_timeout, " <>
           "not Task's 5s default",
         %{sup: sup} do
      original = Application.get_env(:lightning, Lightning.Adaptors.StrategyMock)

      Application.put_env(
        :lightning,
        Lightning.Adaptors.StrategyMock,
        Keyword.put(original, :http_timeout, 100)
      )

      on_exit(fn ->
        Application.put_env(
          :lightning,
          Lightning.Adaptors.StrategyMock,
          original
        )
      end)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "2.0.0"}]}
      end)

      # Never returns; only the async_stream timeout can end it. With the
      # 5s default the await below would time out, so it passing shows
      # the configured budget is what's being applied.
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        receive do
        end
      end)

      start_scheduler(sup)
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{listed: 1, errors: 1}} =
               Scheduler.await_refresh(sched_name, 2_000)
    end
  end

  describe "refresh_now/1" do
    test "triggers an immediate tick on the leader", %{sup: sup} do
      test_pid = self()

      # First call: from init tick. Second call: from refresh_now.
      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 2, fn ->
        send(test_pid, :tick_ran)
        {:ok, []}
      end)

      start_scheduler(sup)

      # Wait for init tick.
      assert_receive :tick_ran, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      # Let the init tick's cycle clear so refresh_now starts a new one
      # instead of coalescing.
      {:global, gname} = sched_name
      pid = :global.whereis_name(gname)
      assert_eventually(:sys.get_state(pid).refresh == nil, 2000)

      assert :ok = Scheduler.refresh_now(sched_name)

      assert_receive :tick_ran, 2000
    end

    test "repeated calls do not leak extra recurring tick chains", %{sup: sup} do
      test_pid = self()

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :tick_ran)
        {:ok, []}
      end)

      start_scheduler(sup, interval: 200)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      {:global, gname} = sched_name
      pid = :global.whereis_name(gname)

      # Init tick, then two manual refresh_now calls — each waited out so it
      # starts its own cycle instead of coalescing into the previous one.
      assert_receive :tick_ran, 2000
      assert_eventually(:sys.get_state(pid).refresh == nil, 2000)

      assert :ok = Scheduler.refresh_now(sched_name)
      assert_receive :tick_ran, 2000
      assert_eventually(:sys.get_state(pid).refresh == nil, 2000)

      assert :ok = Scheduler.refresh_now(sched_name)
      assert_receive :tick_ran, 2000
      assert_eventually(:sys.get_state(pid).refresh == nil, 2000)

      # Drain any tick_ran messages belonging to the manual calls themselves
      # before counting the chain(s) that fire on their own over one interval.
      drain_tick_ran()

      # Only the init-driven chain should still be ticking, arriving ~200ms
      # out. A leaked chain per refresh_now call would fire almost
      # immediately instead, since they were all armed within milliseconds
      # of each other above.
      assert_receive :tick_ran, 300
      refute_receive :tick_ran, 100
    end
  end

  # Rows are seeded before the Scheduler starts so no init tick fires and
  # the Mox counts stay exact.
  describe "await_refresh/2 result" do
    test "carries the cycle's counts on success, with per-adaptor failures as errors",
         %{sup: sup} do
      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            schema_data: ~s({"type":"object"}),
            schema_sha256: "sha-1"
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 1, fn ->
        {:ok,
         [
           %{name: "@openfn/language-http", latest_version: "1.0.0"},
           %{name: "@openfn/language-new", latest_version: "2.0.0"},
           %{name: "@openfn/language-bad", latest_version: "1.0.0"}
         ]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 2, fn
        "@openfn/language-new" ->
          {:ok,
           adaptor_record(
             name: "@openfn/language-new",
             latest_version: "2.0.0"
           )}

        "@openfn/language-bad" ->
          {:error, :upstream_5xx}
      end)

      start_scheduler(sup)
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{listed: 3, changed: 1, fetched: 1, errors: 1}} =
               Scheduler.await_refresh(sched_name, 5_000)
    end

    test "returns the upstream listing failure to waiters", %{sup: sup} do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 1, fn ->
        {:error, :upstream_down}
      end)

      start_scheduler(sup)
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:error, :upstream_down} =
               Scheduler.await_refresh(sched_name, 5_000)
    end
  end

  describe "icons pipeline" do
    test "writes icon bytes to disk and stamps ext+sha256 on the row", %{
      sup: sup
    } do
      source = AdaptorsSupervisor.source(sup)

      bytes = "ICON_BYTES"
      sha = :crypto.hash(:sha256, bytes)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:ok, adaptor_record()}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok,
         %{
           "@openfn/language-http" => %{
             square: %{data: bytes, ext: "png", sha256: sha}
           }
         }}
      end)

      source_topic = AdaptorsSupervisor.source_topic(sup)
      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row.icon_square_ext == "png"
      assert row.icon_square_sha256 == sha
      assert row.icon_rectangle_ext == nil
      assert row.icon_rectangle_sha256 == nil

      icon_path =
        Lightning.Adaptors.IconCache.path(
          source,
          "@openfn/language-http",
          :square,
          "png",
          sha
        )

      assert File.exists?(icon_path)
      assert File.read!(icon_path) == bytes
    end

    test "fetch_icons error: records still persist without icons", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:ok, adaptor_record()}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:error, :timeout}
      end)

      source_topic = AdaptorsSupervisor.source_topic(sup)
      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row != nil
      assert row.icon_square_ext == nil
      assert row.icon_square_sha256 == nil
    end

    test "updates an icon-only change on the periodic tick even when the " <>
           "package's version did not bump",
         %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)

      old_sha = :crypto.hash(:sha256, "OLD")
      rect_sha = :crypto.hash(:sha256, "RECT")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            schema_data: ~s({"type":"object"}),
            schema_sha256: "sha-1",
            icon_square_ext: "png",
            icon_square_sha256: old_sha,
            # Both icon shapes already exist on the row; only the square
            # shape's bytes changed upstream.
            icon_rectangle_ext: "png",
            icon_rectangle_sha256: rect_sha
          )
        )

      new_bytes = "NEW_ICON_BYTES"
      new_sha = :crypto.hash(:sha256, new_bytes)

      # Same version and a stored schema, so the diff path marks this
      # adaptor :touched instead of re-fetching it — only the icon changed.
      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok,
         %{
           "@openfn/language-http" => %{
             square: %{data: new_bytes, ext: "png", sha256: new_sha}
           }
         }}
      end)

      source_topic = AdaptorsSupervisor.source_topic(sup)
      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      assert {:ok, %{errors: 0}} = Scheduler.await_refresh(sched_name, 5_000)

      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row.latest_version == "1.0.0"
      assert row.icon_square_ext == "png"
      assert row.icon_square_sha256 == new_sha
    end

    test "self-heals iconless rows on the periodic tick", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)

      # Pre-seed a row that already matches the listed latest_version and
      # has a schema (so the diff path will :touch instead of :fetch).
      # Without self-heal this row would stay iconless forever.
      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-stale",
            schema_data: ~s({"type":"object"}),
            schema_sha256: "sha-1"
          )
        )

      bytes = "STALE_ICON"
      sha = :crypto.hash(:sha256, bytes)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-stale", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn opts ->
        # Row has no etags pre-seeded, so it is omitted from the
        # prior-etags map entirely (no empty inner map).
        assert Keyword.get(opts, :prior_etags) == %{}

        {:ok,
         %{
           "@openfn/language-stale" => %{
             square: %{data: bytes, ext: "png", sha256: sha}
           }
         }}
      end)

      source_topic = AdaptorsSupervisor.source_topic(sup)
      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      # The pre-seeded row pushes max_checked_at to "now", so init
      # delay = full interval — drive the tick explicitly.
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      assert {:ok, %{errors: 0}} = Scheduler.await_refresh(sched_name, 5_000)

      assert_receive {:changed, "@openfn/language-stale", ^source}, 2000

      row = Catalogue.get_adaptor("@openfn/language-stale", source)
      assert row.icon_square_ext == "png"
      assert row.icon_square_sha256 == sha
    end
  end

  describe "refresh_package/2" do
    test "fetches and upserts a single adaptor, bypassing diff", %{sup: sup} do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :init_list_adaptors_called)
        {:ok, []}
      end)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          {:ok, adaptor_record()}
        end
      )

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      # Drain the init tick (table is empty → delay 0 → fires immediately).
      assert_receive :init_list_adaptors_called, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert :ok = Scheduler.refresh_package(sched_name, "@openfn/language-http")
      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      assert Catalogue.get_adaptor("@openfn/language-http", source) != nil
    end

    test "clears a stored schema when the fetched record has none", %{sup: sup} do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            schema_data: ~s({"type":"object"}),
            schema_sha256: "sha-1"
          )
        )

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :init_list_adaptors_called)
        {:ok, []}
      end)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          {:ok, adaptor_record(schema_data: nil, schema_sha256: nil)}
        end
      )

      start_scheduler(sup)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      assert :ok = Scheduler.refresh_package(sched_name, "@openfn/language-http")

      row = Catalogue.get_adaptor("@openfn/language-http", source)
      assert row.schema_data == nil
      assert row.schema_sha256 == nil
    end

    test "returns error tuple when fetch_adaptor fails", %{sup: sup} do
      test_pid = self()

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :init_list_adaptors_called)
        {:ok, []}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn _ ->
        {:error, :not_found}
      end)

      start_scheduler(sup)

      # Drain init tick before calling refresh_package.
      assert_receive :init_list_adaptors_called, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:error, :not_found} =
               Scheduler.refresh_package(sched_name, "@openfn/language-http")
    end

    test "does not call fetch_icons (icons only refresh on the periodic tick)",
         %{sup: sup} do
      test_pid = self()
      source_topic = AdaptorsSupervisor.source_topic(sup)

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :init_list_adaptors_called)
        {:ok, []}
      end)

      # Exactly one fetch_icons call — the init tick. If refresh_package
      # also fetched icons the count would be 2 and Mox would fail.
      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, 1, fn _opts ->
        send(test_pid, :icons_called)
        {:ok, %{}}
      end)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" -> {:ok, adaptor_record()} end
      )

      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive :init_list_adaptors_called, 2000
      assert_receive :icons_called, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      assert :ok = Scheduler.refresh_package(sched_name, "@openfn/language-http")
      assert_receive {:changed, "@openfn/language-http", _}, 2000
    end
  end

  describe "refresh_icons/1" do
    test "an in-flight icon refresh does not block the Scheduler loop", %{
      sup: sup
    } do
      test_pid = self()

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, []}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, 1, fn _opts ->
        send(test_pid, {:icons_started, self()})

        receive do
          :finish_icons -> {:ok, %{}}
        end
      end)

      start_scheduler(sup, interval: 0)
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      icons_task = Task.async(fn -> Scheduler.refresh_icons(sched_name) end)
      assert_receive {:icons_started, icons_pid}, 2000

      # Completes while the icon fetch is parked, so that fetch is not on
      # the GenServer loop.
      assert {:ok, %{listed: 0}} = Scheduler.await_refresh(sched_name, 5_000)

      send(icons_pid, :finish_icons)

      assert {:ok, %{updated: 0, unchanged: 0}} =
               Task.await(icons_task, 5_000)
    end

    test "a crash in the icon refresh task replies an error instead of killing the Scheduler",
         %{sup: sup} do
      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, 1, fn _opts ->
        raise "boom"
      end)

      start_scheduler(sup, interval: 0)
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:error, {:refresh_failed, _reason}} =
               Scheduler.refresh_icons(sched_name)

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn -> {:ok, []} end)
      assert {:ok, _counts} = Scheduler.await_refresh(sched_name, 2_000)
    end

    test "updates rows whose shape sha256 differs from the fetched icon", %{
      sup: sup
    } do
      source = AdaptorsSupervisor.source(sup)

      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(name: "@openfn/language-empty"))

      old_sha = :crypto.hash(:sha256, "OLD")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-current",
            icon_square_ext: "png",
            icon_square_sha256: old_sha
          )
        )

      new_bytes = "NEW_BYTES"
      new_sha = :crypto.hash(:sha256, new_bytes)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok,
         %{
           "@openfn/language-empty" => %{
             square: %{data: new_bytes, ext: "png", sha256: new_sha}
           },
           "@openfn/language-current" => %{
             square: %{data: new_bytes, ext: "png", sha256: new_sha}
           }
         }}
      end)

      # interval: 0 disables the init tick so refresh_icons is the only
      # path that calls fetch_icons.
      start_scheduler(sup, interval: 0)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{updated: 2, unchanged: 0}} =
               Scheduler.refresh_icons(sched_name)

      empty = Catalogue.get_adaptor("@openfn/language-empty", source)
      assert empty.icon_square_ext == "png"
      assert empty.icon_square_sha256 == new_sha

      current = Catalogue.get_adaptor("@openfn/language-current", source)
      assert current.icon_square_sha256 == new_sha
    end

    test "leaves rows whose shape sha256 already matches unchanged, passing prior etag",
         %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      sha = :crypto.hash(:sha256, "SAME")
      etag = ~s("prior-etag-1")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-same",
            icon_square_ext: "png",
            icon_square_sha256: sha,
            icon_square_etag: etag
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn opts ->
        assert Keyword.get(opts, :prior_etags) == %{
                 "@openfn/language-same" => %{square: etag}
               }

        {:ok, %{"@openfn/language-same" => %{square: :not_modified}}}
      end)

      start_scheduler(sup, interval: 0)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{updated: 0, unchanged: 1}} =
               Scheduler.refresh_icons(sched_name)

      row = Catalogue.get_adaptor("@openfn/language-same", source)
      assert row.icon_square_sha256 == sha
      assert row.icon_square_etag == etag
    end

    test "applies new etag when shape sha256 changes", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      old_sha = :crypto.hash(:sha256, "OLD")
      new_bytes = "NEW"
      new_sha = :crypto.hash(:sha256, new_bytes)
      old_etag = ~s("etag-A")
      new_etag = ~s("etag-B")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-rotated",
            icon_square_ext: "png",
            icon_square_sha256: old_sha,
            icon_square_etag: old_etag
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok,
         %{
           "@openfn/language-rotated" => %{
             square: %{
               data: new_bytes,
               ext: "png",
               sha256: new_sha,
               etag: new_etag
             }
           }
         }}
      end)

      start_scheduler(sup, interval: 0)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{updated: 1, unchanged: 0}} =
               Scheduler.refresh_icons(sched_name)

      row = Catalogue.get_adaptor("@openfn/language-rotated", source)
      assert row.icon_square_sha256 == new_sha
      assert row.icon_square_etag == new_etag
    end

    test "preserves existing etag when fetched entry's etag is nil or missing",
         %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      old_sha = :crypto.hash(:sha256, "OLD")
      new_bytes_a = "NEW_A"
      new_sha_a = :crypto.hash(:sha256, new_bytes_a)
      new_bytes_b = "NEW_B"
      new_sha_b = :crypto.hash(:sha256, new_bytes_b)
      prior_etag = ~s("etag-A")

      # Two rows: one returns 200 with etag: nil (NPM-style), the other
      # returns 200 with the :etag key entirely absent (Local-style).
      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-nil-etag",
            icon_square_ext: "png",
            icon_square_sha256: old_sha,
            icon_square_etag: prior_etag
          )
        )

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-no-etag-key",
            icon_square_ext: "png",
            icon_square_sha256: old_sha,
            icon_square_etag: prior_etag
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok,
         %{
           "@openfn/language-nil-etag" => %{
             square: %{
               data: new_bytes_a,
               ext: "png",
               sha256: new_sha_a,
               etag: nil
             }
           },
           "@openfn/language-no-etag-key" => %{
             square: %{data: new_bytes_b, ext: "png", sha256: new_sha_b}
           }
         }}
      end)

      start_scheduler(sup, interval: 0)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{updated: 2, unchanged: 0}} =
               Scheduler.refresh_icons(sched_name)

      row_a = Catalogue.get_adaptor("@openfn/language-nil-etag", source)
      assert row_a.icon_square_sha256 == new_sha_a
      assert row_a.icon_square_etag == prior_etag

      row_b = Catalogue.get_adaptor("@openfn/language-no-etag-key", source)
      assert row_b.icon_square_sha256 == new_sha_b
      assert row_b.icon_square_etag == prior_etag
    end

    test "mixed 304 and 200: unchanged row preserves its etag verbatim",
         %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      stale_old_sha = :crypto.hash(:sha256, "STALE_OLD")
      stale_new_bytes = "STALE_NEW"
      stale_new_sha = :crypto.hash(:sha256, stale_new_bytes)
      stale_old_etag = ~s("etag-stale-old")
      stale_new_etag = ~s("etag-stale-new")

      current_sha = :crypto.hash(:sha256, "CURRENT_BYTES")
      current_etag = ~s("etag-current")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-stale-etag",
            icon_square_ext: "png",
            icon_square_sha256: stale_old_sha,
            icon_square_etag: stale_old_etag
          )
        )

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-current-etag",
            icon_square_ext: "png",
            icon_square_sha256: current_sha,
            icon_square_etag: current_etag
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn opts ->
        assert Keyword.get(opts, :prior_etags) == %{
                 "@openfn/language-stale-etag" => %{square: stale_old_etag},
                 "@openfn/language-current-etag" => %{square: current_etag}
               }

        {:ok,
         %{
           "@openfn/language-stale-etag" => %{
             square: %{
               data: stale_new_bytes,
               ext: "png",
               sha256: stale_new_sha,
               etag: stale_new_etag
             }
           },
           "@openfn/language-current-etag" => %{square: :not_modified}
         }}
      end)

      start_scheduler(sup, interval: 0)
      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{updated: 1, unchanged: 1}} =
               Scheduler.refresh_icons(sched_name)

      stale_row = Catalogue.get_adaptor("@openfn/language-stale-etag", source)
      assert stale_row.icon_square_sha256 == stale_new_sha
      assert stale_row.icon_square_etag == stale_new_etag

      current_row =
        Catalogue.get_adaptor("@openfn/language-current-etag", source)

      assert current_row.icon_square_sha256 == current_sha
      assert current_row.icon_square_etag == current_etag
    end

    test "surfaces a strategy fetch error as {:error, reason}", %{sup: sup} do
      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:error, :upstream_down}
      end)

      start_scheduler(sup, interval: 0)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:error, :upstream_down} = Scheduler.refresh_icons(sched_name)
    end
  end
end

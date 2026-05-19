defmodule Lightning.Adaptors.SchedulerTest do
  # async: false because:
  # 1. DataCase uses shared sandbox mode (all processes access DB without allow/3)
  # 2. set_mox_global is safe only when tests run serially
  use Lightning.DataCase, async: false

  import Mox

  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  # set_mox_global makes expectations visible to tasks spawned by the Scheduler,
  # whose $callers chain does not include the test process (only the GenServer).
  setup :set_mox_global
  setup :verify_on_exit!

  # Each test owns an isolated supervisor. The supervisor starts its own
  # Scheduler as part of the :rest_for_one child list, but with the
  # test-env `refresh_interval: 0` it's an inert no-op. Individual tests
  # call `start_scheduler/2` to replace it with a controlled-interval
  # Scheduler under `start_supervised!/1` (so Mox expectations can be
  # registered before init fires).
  setup do
    sup = :"sched_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    # Default no-op icons stub for tests that don't care about the icons
    # pipeline. Individual tests override via `expect` when they need to
    # assert on it.
    stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn -> {:ok, %{}} end)

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

    pid =
      start_supervised!({
        Scheduler,
        name: global_name,
        sup: sup,
        lock_key: AdaptorsSupervisor.lock_key(sup),
        cache: AdaptorsSupervisor.cache_name(sup),
        tasks: AdaptorsSupervisor.tasks_name(sup),
        source_topic: source_topic
      })

    Application.put_env(:lightning, Lightning.Adaptors, original_env)

    pid
  end

  defp adaptor_record(overrides \\ []) do
    overrides = Map.new(overrides)

    %{
      name: "@openfn/language-http",
      source: :npm,
      latest_version: "1.0.0",
      description: "HTTP adaptor",
      homepage: nil,
      repository: nil,
      license: "LGPL-3.0",
      deprecated: false,
      schema_data: nil,
      schema_sha256: nil,
      versions: [
        %{
          version: "1.0.0",
          integrity: "sha512-abc",
          tarball_url: "https://example.com/x-1.0.0.tgz",
          size_bytes: 1024,
          dependencies: %{},
          peer_dependencies: %{},
          published_at: nil,
          deprecated: false
        }
      ]
    }
    |> Map.merge(overrides)
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

  describe "do_refresh/1 diff logic" do
    test "unchanged adaptor: touch_checked_at only, no upsert, no broadcast", %{
      sup: sup
    } do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      {:ok, existing} = AdaptorsRepo.upsert_adaptor(adaptor_record())
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
      refute_receive {:changed, _, _}, 200

      row = AdaptorsRepo.get_adaptor("@openfn/language-http", source)
      assert DateTime.compare(row.checked_at, checked_at_before) == :gt
      assert row.latest_version == "1.0.0"
    end

    test "changed adaptor: upsert and broadcast per changed name", %{sup: sup} do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())

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

      row = AdaptorsRepo.get_adaptor("@openfn/language-http", source)
      assert row.latest_version == "2.0.0"
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
      assert AdaptorsRepo.get_adaptor("@openfn/language-new", source) != nil
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
      refute_receive {:changed, _, _}, 200
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
      assert :ok = Scheduler.refresh_now(sched_name)

      assert_receive :tick_ran, 2000
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

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn ->
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

      row = AdaptorsRepo.get_adaptor("@openfn/language-http", source)
      assert row.icon_square_ext == "png"
      assert row.icon_square_sha256 == sha
      assert row.icon_rectangle_ext == nil
      assert row.icon_rectangle_sha256 == nil

      icon_path =
        Lightning.Adaptors.IconCache.path(
          source,
          "@openfn/language-http",
          :square,
          "png"
        )

      assert File.exists?(icon_path)
      assert File.read!(icon_path) == bytes
      File.rm!(icon_path)
    end

    test "fetch_icons error: records still persist without icons", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:ok, adaptor_record()}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn ->
        {:error, :timeout}
      end)

      source_topic = AdaptorsSupervisor.source_topic(sup)
      :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, source_topic)
      start_scheduler(sup)

      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      row = AdaptorsRepo.get_adaptor("@openfn/language-http", source)
      assert row != nil
      assert row.icon_square_ext == nil
      assert row.icon_square_sha256 == nil
    end

    test "self-heals iconless rows on the periodic tick", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)

      # Pre-seed a row that already matches the listed latest_version
      # (so the diff path will :touch instead of :fetch). Without
      # self-heal this row would stay iconless forever.
      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(name: "@openfn/language-stale")
        )

      bytes = "STALE_ICON"
      sha = :crypto.hash(:sha256, bytes)

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, [%{name: "@openfn/language-stale", latest_version: "1.0.0"}]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn ->
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
      :ok = Scheduler.refresh_now(sched_name)

      assert_receive {:changed, "@openfn/language-stale", ^source}, 2000

      row = AdaptorsRepo.get_adaptor("@openfn/language-stale", source)
      assert row.icon_square_ext == "png"
      assert row.icon_square_sha256 == sha

      icon_path =
        Lightning.Adaptors.IconCache.path(
          source,
          "@openfn/language-stale",
          :square,
          "png"
        )

      File.rm(icon_path)
    end

    test "fetches per-adaptor in parallel (multiple concurrent fetch_adaptor calls)",
         %{sup: sup} do
      test_pid = self()
      barrier = :ets.new(:scheduler_test_barrier, [:public, :set])
      :ets.insert(barrier, {:in_flight, 0})
      :ets.insert(barrier, {:max_in_flight, 0})

      names =
        for i <- 1..6,
            do: %{name: "@openfn/language-pkg#{i}", latest_version: "1.0.0"}

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, names}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn name ->
        in_flight = :ets.update_counter(barrier, :in_flight, 1)

        :ets.update_element(
          barrier,
          :max_in_flight,
          {2, max_seen(barrier, in_flight)}
        )

        # Hold long enough that the fan-out has time to overlap.
        Process.sleep(80)
        :ets.update_counter(barrier, :in_flight, -1)
        send(test_pid, {:fetched, name})
        {:ok, adaptor_record(name: name)}
      end)

      start_scheduler(sup)

      for _ <- 1..6 do
        assert_receive {:fetched, _name}, 5_000
      end

      [{:max_in_flight, max_in_flight}] = :ets.lookup(barrier, :max_in_flight)
      :ets.delete(barrier)

      assert max_in_flight > 1,
             "expected concurrent fetch_adaptor calls, saw at most 1 in-flight"
    end
  end

  defp max_seen(barrier, current) do
    [{:max_in_flight, prev}] = :ets.lookup(barrier, :max_in_flight)
    max(prev, current)
  end

  describe "refresh_package/2" do
    test "fetches and upserts a single adaptor, bypassing diff", %{sup: sup} do
      test_pid = self()
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :init_tick_done)
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
      assert_receive :init_tick_done, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert :ok = Scheduler.refresh_package(sched_name, "@openfn/language-http")
      assert_receive {:changed, "@openfn/language-http", ^source}, 2000

      assert AdaptorsRepo.get_adaptor("@openfn/language-http", source) != nil
    end

    test "returns error tuple when fetch_adaptor fails", %{sup: sup} do
      test_pid = self()

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :init_tick_done)
        {:ok, []}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn _ ->
        {:error, :not_found}
      end)

      start_scheduler(sup)

      # Drain init tick before calling refresh_package.
      assert_receive :init_tick_done, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:error, :not_found} =
               Scheduler.refresh_package(sched_name, "@openfn/language-http")
    end

    test "does not call fetch_icons (icons only refresh on the periodic tick)",
         %{sup: sup} do
      test_pid = self()
      source_topic = AdaptorsSupervisor.source_topic(sup)

      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :init_tick_done)
        {:ok, []}
      end)

      # Exactly one fetch_icons call — the init tick. If refresh_package
      # also fetched icons the count would be 2 and Mox would fail.
      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, 1, fn ->
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

      assert_receive :init_tick_done, 2000
      assert_receive :icons_called, 2000

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)
      assert :ok = Scheduler.refresh_package(sched_name, "@openfn/language-http")
      assert_receive {:changed, "@openfn/language-http", _}, 2000

      # Give any (mistaken) extra fetch_icons call time to happen.
      Process.sleep(100)
    end
  end

  describe "refresh_icons/1" do
    test "updates rows whose shape sha256 differs from the fetched icon", %{
      sup: sup
    } do
      source = AdaptorsSupervisor.source(sup)

      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(name: "@openfn/language-empty")
        )

      old_sha = :crypto.hash(:sha256, "OLD")

      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-current",
            icon_square_ext: "png",
            icon_square_sha256: old_sha
          )
        )

      new_bytes = "NEW_BYTES"
      new_sha = :crypto.hash(:sha256, new_bytes)

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn ->
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

      empty = AdaptorsRepo.get_adaptor("@openfn/language-empty", source)
      assert empty.icon_square_ext == "png"
      assert empty.icon_square_sha256 == new_sha

      current = AdaptorsRepo.get_adaptor("@openfn/language-current", source)
      assert current.icon_square_sha256 == new_sha

      for name <- ["@openfn/language-empty", "@openfn/language-current"] do
        Lightning.Adaptors.IconCache.path(source, name, :square, "png")
        |> File.rm()
      end
    end

    test "leaves rows whose shape sha256 already matches unchanged", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      sha = :crypto.hash(:sha256, "SAME")

      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(
            name: "@openfn/language-same",
            icon_square_ext: "png",
            icon_square_sha256: sha
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn ->
        {:ok,
         %{
           "@openfn/language-same" => %{
             square: %{data: "SAME", ext: "png", sha256: sha}
           }
         }}
      end)

      start_scheduler(sup, interval: 0)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:ok, %{updated: 0, unchanged: 1}} =
               Scheduler.refresh_icons(sched_name)

      _ = source
    end

    test "surfaces a strategy fetch error as {:error, reason}", %{sup: sup} do
      expect(Lightning.Adaptors.StrategyMock, :fetch_icons, fn ->
        {:error, :upstream_down}
      end)

      start_scheduler(sup, interval: 0)

      sched_name = AdaptorsSupervisor.global_scheduler_name(sup)

      assert {:error, :upstream_down} = Scheduler.refresh_icons(sched_name)
    end
  end
end

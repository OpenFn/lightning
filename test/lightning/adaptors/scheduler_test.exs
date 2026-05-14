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

  # Each test owns an isolated supervisor. The Scheduler is started per-test
  # (not in setup) so Mox expectations can be registered before init fires.
  setup do
    sup = :"sched_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    {:ok, sup: sup}
  end

  # Start the Scheduler with a controlled refresh interval.
  # Application env is restored immediately after start_supervised!/1 returns
  # because the scheduler captures interval_ms in init/1.
  defp start_scheduler(sup, opts \\ []) do
    interval = Keyword.get(opts, :interval, 99_999_999)
    original_env = Application.get_env(:lightning, Lightning.Adaptors, [])

    Application.put_env(
      :lightning,
      Lightning.Adaptors,
      Keyword.put(original_env, :refresh_interval, interval)
    )

    sched_name = AdaptorsSupervisor.scheduler_name(sup)
    source_topic = AdaptorsSupervisor.source_topic(sup)

    pid =
      start_supervised!({
        Scheduler,
        name: sched_name,
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
      icon_square_ext: nil,
      icon_rectangle_ext: nil,
      icon_square_sha256: nil,
      icon_rectangle_sha256: nil,
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
      sched_name = AdaptorsSupervisor.scheduler_name(sup)

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
      sched_name = AdaptorsSupervisor.scheduler_name(sup)

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

    test "registers under :name", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn -> {:ok, []} end)
      start_scheduler(sup)
      sched_name = AdaptorsSupervisor.scheduler_name(sup)
      assert is_pid(Process.whereis(sched_name))
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
      sched_name = AdaptorsSupervisor.scheduler_name(sup)
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
      sched_name = AdaptorsSupervisor.scheduler_name(sup)
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

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/bad-adaptor" ->
          {:error, :not_found}
        end
      )

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/good-adaptor" ->
          {:ok, adaptor_record(name: "@openfn/good-adaptor")}
        end
      )

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

      sched_name = AdaptorsSupervisor.scheduler_name(sup)
      assert :ok = Scheduler.refresh_now(sched_name)

      assert_receive :tick_ran, 2000
    end
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

      sched_name = AdaptorsSupervisor.scheduler_name(sup)

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

      sched_name = AdaptorsSupervisor.scheduler_name(sup)

      assert {:error, :not_found} =
               Scheduler.refresh_package(sched_name, "@openfn/language-http")
    end
  end
end

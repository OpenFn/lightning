defmodule Lightning.Adaptors.NodeMonitorTest do
  use Lightning.DataCase, async: true

  import Mox

  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup :verify_on_exit!

  setup do
    sup = :"nm_test_#{System.unique_integer([:positive])}"

    # The supervisor's :rest_for_one child list starts the NodeMonitor
    # automatically — registered under `node_monitor_name(sup)`.
    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    cache = AdaptorsSupervisor.cache_name(sup)
    nm_name = AdaptorsSupervisor.node_monitor_name(sup)

    nm_pid = Process.whereis(nm_name)
    Ecto.Adapters.SQL.Sandbox.allow(Lightning.Repo, self(), nm_pid)

    # Scheduler is auto-started too; let it hit the Repo under the
    # current test process's sandbox connection.
    sched_pid = Process.whereis(AdaptorsSupervisor.scheduler_name(sup))

    if is_pid(sched_pid),
      do: Ecto.Adapters.SQL.Sandbox.allow(Lightning.Repo, self(), sched_pid)

    {:ok, sup: sup, cache: cache, nm_name: nm_name}
  end

  describe "start_link/1" do
    test "registers under the :name opt", %{nm_name: nm_name} do
      assert is_pid(Process.whereis(nm_name))
    end
  end

  describe "handle_info/2 - {:nodeup, ...}" do
    test "warms {:packages, source} and {:icon_meta, name, source} from Postgres",
         %{
           sup: sup,
           cache: cache,
           nm_name: nm_name
         } do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())
      source = AdaptorsSupervisor.source(sup)

      send(nm_name, {:nodeup, :node@host, %{node_type: :visible}})
      :sys.get_state(nm_name)

      assert {:ok, {:ok, [pkg]}} = Cachex.get(cache, {:packages, source})
      assert pkg.name == "@openfn/language-http"

      assert {:ok, {:ok, icon_meta}} =
               Cachex.get(cache, {:icon_meta, "@openfn/language-http", source})

      assert Map.has_key?(icon_meta, :icon_square_ext)
    end

    test "uses put_many; pre-existing schema keys survive the warm", %{
      sup: sup,
      cache: cache,
      nm_name: nm_name
    } do
      source = AdaptorsSupervisor.source(sup)

      Cachex.put!(
        cache,
        {:schema, "pre-existing", source},
        {:ok, %{"kept" => true}}
      )

      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())

      send(nm_name, {:nodeup, :node@host, %{node_type: :visible}})
      :sys.get_state(nm_name)

      assert {:ok, {:ok, %{"kept" => true}}} =
               Cachex.get(cache, {:schema, "pre-existing", source})
    end

    test "warm covers only the active source; :local keys are not materialised in npm mode",
         %{
           cache: cache,
           nm_name: nm_name
         } do
      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())

      send(nm_name, {:nodeup, :node@host, %{node_type: :visible}})
      :sys.get_state(nm_name)

      assert {:ok, nil} = Cachex.get(cache, {:packages, :local})
    end
  end

  describe "handle_info/2 - {:nodedown, ...}" do
    test "nodedown is a no-op; cache and state are unchanged", %{
      sup: sup,
      cache: cache,
      nm_name: nm_name
    } do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      source = AdaptorsSupervisor.source(sup)
      Cachex.put!(cache, {:packages, source}, {:ok, [%{name: "sentinel"}]})

      send(nm_name, {:nodedown, :node@host, %{node_type: :visible}})
      :sys.get_state(nm_name)

      assert {:ok, {:ok, [%{name: "sentinel"}]}} =
               Cachex.get(cache, {:packages, source})
    end
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
          integrity: "sha512-1.0.0",
          tarball_url: "https://example.com/x/-/x-1.0.0.tgz",
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
end

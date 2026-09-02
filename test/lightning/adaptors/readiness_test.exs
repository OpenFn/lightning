defmodule Lightning.Adaptors.ReadinessTest do
  @moduledoc """
  `fetch_adaptor/2` and `ensure_loaded/1` against an isolated supervisor:
  a populated catalogue never contacts the Scheduler, an empty one waits
  for exactly one coalesced load, and every failure mode of that wait maps
  to its error atom.
  """

  use Lightning.DataCase, async: true

  import Eventually
  import Mox

  alias Lightning.Adaptors
  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup :verify_on_exit!

  # Without the built-in Scheduler, unarranged contact fails with
  # `:unavailable` rather than a Mox error in a process the test does not own.
  setup do
    sup = :"readiness_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    :ok =
      Supervisor.terminate_child(sup, AdaptorsSupervisor.highlander_name(sup))

    {:ok, sup: sup}
  end

  defp adaptor_record(overrides \\ []) do
    overrides = Map.new(overrides)

    %{
      name: "@openfn/language-http",
      source: :npm,
      latest_version: "1.0.0",
      description: nil,
      homepage: nil,
      repository: nil,
      license: nil,
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

  # Tasks the Scheduler spawns inherit its `$callers`, so allowing the
  # Scheduler covers them.
  defp start_scheduler(sup) do
    pid =
      start_supervised!({
        Scheduler,
        name: AdaptorsSupervisor.global_scheduler_name(sup),
        sup: sup,
        lock_key: AdaptorsSupervisor.lock_key(sup),
        cache: AdaptorsSupervisor.cache_name(sup),
        tasks: AdaptorsSupervisor.tasks_name(sup),
        source_topic: AdaptorsSupervisor.source_topic(sup)
      })

    Ecto.Adapters.SQL.Sandbox.allow(Lightning.Repo, self(), pid)
    Mox.allow(Lightning.Adaptors.StrategyMock, self(), pid)
    pid
  end

  defp expect_one_load(records) do
    expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 1, fn ->
      {:ok, Enum.map(records, &Map.take(&1, [:name, :latest_version]))}
    end)

    expect(
      Lightning.Adaptors.StrategyMock,
      :fetch_adaptor,
      length(records),
      fn name -> {:ok, Enum.find(records, &(&1.name == name))} end
    )

    stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
      {:ok, %{}}
    end)
  end

  describe "fetch_adaptor/2 on a populated catalogue" do
    test "serves a known adaptor from the cache without contacting the Scheduler",
         %{sup: sup} do
      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(latest_version: "2.0.0"))

      assert {:ok, %Adaptors.Package{latest_version: "2.0.0", source: :npm}} =
               Adaptors.fetch_adaptor(sup, "@openfn/language-http")

      source = AdaptorsSupervisor.source(sup)

      assert {:ok, {:ok, [%{name: "@openfn/language-http"}]}} =
               Cachex.get(
                 AdaptorsSupervisor.cache_name(sup),
                 {:packages, source}
               )

      assert {:ok, %Adaptors.Package{latest_version: "2.0.0"}} =
               Adaptors.fetch_adaptor(sup, "@openfn/language-http")
    end

    test "finds a row the cached list does not have yet", %{sup: sup} do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())
      assert {:ok, _} = Adaptors.fetch_adaptor(sup, "@openfn/language-http")

      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(name: "@openfn/language-x"))

      assert {:ok, %Adaptors.Package{name: "@openfn/language-x"}} =
               Adaptors.fetch_adaptor(sup, "@openfn/language-x")
    end

    test "returns {:error, :not_found} for an absent name without contacting the Scheduler",
         %{sup: sup} do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert {:error, :not_found} =
               Adaptors.fetch_adaptor(sup, "@openfn/never-existed")

      assert Adaptors.get_adaptor(sup, "@openfn/never-existed") == nil
    end

    test "answers for the given supervisor's source, not the default one" do
      local_sup = :"readiness_local_#{System.unique_integer([:positive])}"

      start_supervised!(
        Supervisor.child_spec(
          {AdaptorsSupervisor,
           name: local_sup, strategy: Lightning.Adaptors.Local},
          id: local_sup
        )
      )

      :ok =
        Supervisor.terminate_child(
          local_sup,
          AdaptorsSupervisor.highlander_name(local_sup)
        )

      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert {:error, :unavailable} =
               Adaptors.fetch_adaptor(local_sup, "@openfn/language-http")

      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record(source: :local))

      assert {:ok, %Adaptors.Package{source: :local}} =
               Adaptors.fetch_adaptor(local_sup, "@openfn/language-http")
    end
  end

  describe "fetch_adaptor/2 on an empty catalogue" do
    test "waits for one coalesced load shared by concurrent callers", %{sup: sup} do
      test_pid = self()
      record = adaptor_record()

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 1, fn ->
        send(test_pid, :listed)
        Process.sleep(50)
        {:ok, [Map.take(record, [:name, :latest_version])]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn _ ->
        {:ok, record}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      start_scheduler(sup)

      task_a =
        Task.async(fn ->
          Adaptors.fetch_adaptor(sup, "@openfn/language-http")
        end)

      assert_receive :listed, 2000

      task_b =
        Task.async(fn ->
          Adaptors.fetch_adaptor(sup, "@openfn/language-http")
        end)

      assert {:ok, %Adaptors.Package{latest_version: "1.0.0"}} =
               Task.await(task_a, 5_000)

      assert {:ok, %Adaptors.Package{latest_version: "1.0.0"}} =
               Task.await(task_b, 5_000)
    end

    test "returns {:error, :not_found} when the load does not list the name",
         %{sup: sup} do
      expect_one_load([adaptor_record()])
      start_scheduler(sup)

      assert {:error, :not_found} =
               Adaptors.fetch_adaptor(sup, "@openfn/never-existed")
    end

    test "returns {:error, :not_ready} when the load leaves the catalogue empty",
         %{sup: sup} do
      expect_one_load([])
      start_scheduler(sup)

      assert {:error, :not_ready} =
               Adaptors.fetch_adaptor(sup, "@openfn/language-http")
    end

    test "returns {:error, :unavailable} when no Scheduler is reachable",
         %{sup: sup} do
      assert {:error, :unavailable} =
               Adaptors.fetch_adaptor(sup, "@openfn/language-http")
    end

    test "returns {:error, :timeout} on a slow load, and the late result still lands",
         %{sup: sup} do
      Mimic.stub(Lightning.Adaptors.Config, :first_load_timeout, fn -> 50 end)

      record = adaptor_record()

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 1, fn ->
        Process.sleep(300)
        {:ok, [Map.take(record, [:name, :latest_version])]}
      end)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn _ ->
        {:ok, record}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      pid = start_scheduler(sup)

      assert {:error, :timeout} =
               Adaptors.fetch_adaptor(sup, "@openfn/language-http")

      assert Process.alive?(pid)

      assert_eventually(
        match?(
          {:ok, %Adaptors.Package{}},
          Adaptors.fetch_adaptor(sup, "@openfn/language-http")
        ),
        2000
      )

      assert Process.alive?(pid)
    end
  end

  describe "ensure_loaded/1" do
    test "returns :ok immediately when rows exist, without contacting the Scheduler",
         %{sup: sup} do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())
      assert :ok = Adaptors.ensure_loaded(sup)
    end

    test "loads once, then answers from data even with the Scheduler gone",
         %{sup: sup} do
      expect_one_load([adaptor_record()])
      pid = start_scheduler(sup)

      assert :ok = Adaptors.ensure_loaded(sup)

      stop_supervised!(Scheduler)
      refute Process.alive?(pid)

      assert :ok = Adaptors.ensure_loaded(sup)
    end

    test "maps a failed wait to its error atom", %{sup: sup} do
      assert {:error, :unavailable} = Adaptors.ensure_loaded(sup)

      expect_one_load([])
      start_scheduler(sup)

      assert {:error, :not_ready} = Adaptors.ensure_loaded(sup)
    end
  end
end

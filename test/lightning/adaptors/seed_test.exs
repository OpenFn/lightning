defmodule Lightning.Adaptors.SeedTest do
  use Lightning.DataCase, async: true

  alias Lightning.Adaptors.Seed
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    sup = :"seed_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    :ok =
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        AdaptorsSupervisor.source_topic(sup)
      )

    {:ok,
     sup: sup,
     source: AdaptorsSupervisor.source(sup),
     cache: AdaptorsSupervisor.cache_name(sup),
     tmp_dir: tmp_dir}
  end

  defp write_snapshot(tmp_dir, records) do
    path =
      Path.join(tmp_dir, "snapshot-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode_to_iodata!(records))
    path
  end

  defp record(name, opts \\ []) do
    %{
      name: name,
      latest_version: Keyword.get(opts, :latest_version, "1.0.0"),
      versions: Keyword.get(opts, :versions, [])
    }
  end

  describe "seed_from_file/2" do
    test "broadcasts {:changed, name, source} for every seeded name", %{
      sup: sup,
      source: source,
      tmp_dir: tmp_dir
    } do
      path =
        write_snapshot(tmp_dir, [
          record("@openfn/language-http"),
          record("@openfn/language-dhis2")
        ])

      assert {:ok, 2} = Seed.seed_from_file(path, sup: sup)

      assert_receive {:changed, "@openfn/language-http", ^source}
      assert_receive {:changed, "@openfn/language-dhis2", ^source}
    end

    test "replace: true also broadcasts for names the wipe removed", %{
      sup: sup,
      source: source,
      tmp_dir: tmp_dir
    } do
      insert(:adaptor, name: "@openfn/language-stale", source: source)

      path = write_snapshot(tmp_dir, [record("@openfn/language-http")])

      assert {:ok, 1} = Seed.seed_from_file(path, sup: sup, replace: true)

      assert_receive {:changed, "@openfn/language-http", ^source}
      assert_receive {:changed, "@openfn/language-stale", ^source}
    end

    test "replace: true broadcasts for a removed name even when the catalogue listing excludes it",
         %{
           sup: sup,
           source: source,
           tmp_dir: tmp_dir
         } do
      insert(:adaptor, name: "@openfn/language-collections", source: source)

      path = write_snapshot(tmp_dir, [record("@openfn/language-http")])

      assert {:ok, 1} = Seed.seed_from_file(path, sup: sup, replace: true)

      assert_receive {:changed, "@openfn/language-http", ^source}
      assert_receive {:changed, "@openfn/language-collections", ^source}
    end

    test "a rolled-back seed broadcasts nothing", %{
      sup: sup,
      tmp_dir: tmp_dir
    } do
      insert(:adaptor, name: "@openfn/language-stale", source: :npm)

      path =
        write_snapshot(tmp_dir, [
          record("@openfn/language-http"),
          # No `latest_version`, which the Adaptor changeset requires, so
          # this raises inside the transaction.
          %{name: "@openfn/language-broken", versions: []}
        ])

      assert_raise ArgumentError, fn ->
        Seed.seed_from_file(path, sup: sup, replace: true)
      end

      refute_receive {:changed, _, _}
    end

    test "the instance's Invalidator drops the cached catalogue", %{
      sup: sup,
      source: source,
      cache: cache,
      tmp_dir: tmp_dir
    } do
      Cachex.put!(cache, {:catalogue, source}, {:ok, {{nil, 0}, []}})

      path = write_snapshot(tmp_dir, [record("@openfn/language-http")])

      assert {:ok, 1} = Seed.seed_from_file(path, sup: sup)

      :sys.get_state(AdaptorsSupervisor.invalidator_name(sup))

      assert {:ok, nil} = Cachex.get(cache, {:catalogue, source})
    end
  end
end

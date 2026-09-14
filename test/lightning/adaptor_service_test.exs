defmodule Lightning.AdaptorServiceTest do
  @moduledoc """
  Covers `AdaptorService.install/2` checking the package against
  `Lightning.Adaptors.fetch_adaptor/1` first: an empty catalogue waits for
  one load, a name the loaded catalogue lacks is refused as
  `:adaptor_not_permitted`, and a catalogue that cannot answer at all comes
  back as `{:catalogue_unavailable, reason}` rather than a refusal.
  """

  # set_mox_global: the load runs in a Task owned by the Scheduler.
  use Lightning.DataCase, async: false

  import Mox
  import Lightning.AdaptorTestHelpers, only: [isolated_adaptors: 1]

  alias Lightning.Adaptors.Catalogue
  alias Lightning.AdaptorService

  setup :set_mox_global
  setup :verify_on_exit!
  setup :isolated_adaptors

  setup do
    stub(Lightning.AdaptorService.RepoMock, :list_local, fn _path -> [] end)

    {:ok, agent} =
      AdaptorService.start_link(
        adaptors_path: "test/tmp/adaptors",
        repo: Lightning.AdaptorService.RepoMock
      )

    {:ok, agent: agent}
  end

  describe "install/2 refuses a package the catalogue doesn't recognise" do
    test "empty catalogue: loads once, then refuses without calling repo.install/2",
         %{agent: agent} do
      test_pid = self()

      expect(Lightning.Adaptors.StrategyMock, :list_adaptors, 1, fn ->
        send(test_pid, :listed)
        {:ok, []}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      assert {:error, :adaptor_not_permitted} =
               AdaptorService.install(agent, "@openfn/language-http")

      assert_received :listed
    end

    test "a catalogue that cannot answer is not a refusal", %{agent: agent} do
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:error, :econnrefused}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      assert {:error, {:catalogue_unavailable, :not_ready}} =
               AdaptorService.install(agent, "@openfn/language-http")
    end

    test "populated catalogue without this package: refuses", %{agent: agent} do
      {:ok, _} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-common",
          source: :npm,
          latest_version: "1.0.0",
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
        })

      assert {:error, :adaptor_not_permitted} =
               AdaptorService.install(agent, "@openfn/language-http")
    end
  end

  describe "install/2 allows a package the catalogue recognises" do
    test "populated catalogue with this package: proceeds to repo.install/2",
         %{agent: agent} do
      {:ok, _} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "1.0.0",
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
        })

      expect(Lightning.AdaptorService.RepoMock, :install, fn _adaptor, _dir ->
        {"", 0}
      end)

      stub(Lightning.AdaptorService.RepoMock, :list_local, fn _path -> [] end)

      assert {:ok, _installed} =
               AdaptorService.install(agent, "@openfn/language-http")
    end
  end
end

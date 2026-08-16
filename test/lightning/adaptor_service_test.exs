defmodule Lightning.AdaptorServiceTest do
  use Lightning.DataCase, async: false

  import ExUnit.CaptureLog

  alias Lightning.AdaptorRegistry
  alias Lightning.AdaptorService
  alias Lightning.AdaptorService.Adaptor

  @permitted "@openfn/language-adaptor-service-test"

  defmodule StubRepo do
    @moduledoc false
    alias Lightning.AdaptorService.Adaptor

    @present [
      %Adaptor{
        name: "@openfn/language-adaptor-service-test",
        version: "1.0.0",
        path: "/fake/path",
        local_name: "@openfn/language-adaptor-service-test",
        status: :present
      }
    ]

    def list_local(_path), do: @present
    def list_local(_path, _depth), do: @present

    def install(_aliased_name, _dir), do: {"", 0}
  end

  describe "Repo.install/2" do
    @tag :tmp_dir
    test "is not vulnerable to shell injection", %{tmp_dir: dir} do
      marker = Path.join(dir, "pwned")

      Lightning.AdaptorService.Repo.install(
        ["bogus-#{System.unique_integer([:positive])} > #{marker}"],
        dir
      )

      refute File.exists?(marker)
    end
  end

  describe "AdaptorService.install/2 allowlist" do
    setup do
      cache =
        Briefly.create!(extname: ".json")
        |> tap(fn path ->
          File.write!(
            path,
            Jason.encode!([
              %{
                name: @permitted,
                latest: "1.0.0",
                repo: "git+https://example.com/test.git",
                versions: []
              }
            ])
          )
        end)

      start_supervised!(
        {AdaptorRegistry, name: :test_asvc_registry, use_cache: cache}
      )

      start_supervised!(
        {AdaptorService,
         name: :test_adaptor_service,
         adaptors_path: "/tmp/fake",
         repo: StubRepo,
         adaptor_registry: :test_asvc_registry}
      )

      :ok
    end

    test "refuses a non-permitted adaptor" do
      log =
        capture_log(fn ->
          assert AdaptorService.install(
                   :test_adaptor_service,
                   "@openfn/language-http@1.0.0"
                 ) ==
                   {:error, :adaptor_not_permitted}
        end)

      assert log =~
               "Refusing to install non-permitted adaptor: \"@openfn/language-http\""
    end

    test "permits an adaptor present in the registry and already on disk" do
      assert {:ok, %Adaptor{name: @permitted}} =
               AdaptorService.install(:test_adaptor_service, @permitted)
    end
  end

  describe "AdaptorService.install/2 overlapping installs (#5059)" do
    defmodule SlowCountingStubRepo do
      @moduledoc """
      Like `StubRepo`, but starts with nothing on disk, counts real
      `install/2` invocations (via the named `:install_call_counter` Agent
      each test starts), and sleeps briefly so two overlapping `install/2`
      calls reliably land inside the same in-flight window.
      """
      alias Lightning.AdaptorService.Adaptor

      def list_local(_path), do: present()
      def list_local(_path, _depth), do: present()

      def install(_aliased_name, _dir) do
        Agent.update(:install_call_counter, &(&1 + 1))
        Process.sleep(200)
        Agent.update(:installed_flag, fn _ -> true end)
        {"", 0}
      end

      defp present do
        if Agent.get(:installed_flag, & &1) do
          [
            %Adaptor{
              name: "@openfn/language-adaptor-service-test",
              # Matches the pinned version the concurrency tests below
              # request, and also satisfies the "> 0.0.0" requirement the
              # @latest test resolves to — one fixture, both tests.
              version: "7.3.2",
              path: "/fake/path",
              local_name: "@openfn/language-adaptor-service-test",
              status: :present
            }
          ]
        else
          []
        end
      end
    end

    setup do
      Agent.start_link(fn -> 0 end, name: :install_call_counter)
      Agent.start_link(fn -> false end, name: :installed_flag)

      on_exit(fn ->
        for name <- [:install_call_counter, :installed_flag] do
          if pid = Process.whereis(name), do: Agent.stop(pid)
        end
      end)

      cache =
        Briefly.create!(extname: ".json")
        |> tap(fn path ->
          File.write!(
            path,
            Jason.encode!([
              %{
                name: @permitted,
                latest: "7.3.2",
                repo: "git+https://example.com/test.git",
                versions: []
              }
            ])
          )
        end)

      start_supervised!(
        {AdaptorRegistry, name: :overlap_registry, use_cache: cache}
      )

      start_supervised!(
        {AdaptorService,
         name: :overlap_service,
         adaptors_path: "/tmp/fake_overlap",
         repo: SlowCountingStubRepo,
         adaptor_registry: :overlap_registry}
      )

      :ok
    end

    test "two overlapping installs of the same pinned version collapse into one real install" do
      spec = "#{@permitted}@7.3.2"

      task =
        Task.async(fn -> AdaptorService.install(:overlap_service, spec) end)

      Process.sleep(50)
      second_result = AdaptorService.install(:overlap_service, spec)
      first_result = Task.await(task, 2000)

      assert {:ok, %Adaptor{name: @permitted, path: path}} = first_result
      refute is_nil(path)
      assert first_result == second_result
      assert Agent.get(:install_call_counter, & &1) == 1
    end

    test "two overlapping installs of @latest resolve cleanly, without raising" do
      spec = "#{@permitted}@latest"

      task =
        Task.async(fn -> AdaptorService.install(:overlap_service, spec) end)

      Process.sleep(50)
      second_result = AdaptorService.install(:overlap_service, spec)
      first_result = Task.await(task, 2000)

      assert {:ok, %Adaptor{name: @permitted, path: path}} = first_result
      refute is_nil(path)
      assert first_result == second_result
      assert Agent.get(:install_call_counter, & &1) == 1
    end
  end

  describe "version parsing never raises (#5059)" do
    setup do
      cache =
        Briefly.create!(extname: ".json")
        |> tap(fn path ->
          File.write!(
            path,
            Jason.encode!([
              %{
                name: @permitted,
                latest: "1.0.0",
                repo: "git+https://example.com/test.git",
                versions: []
              }
            ])
          )
        end)

      start_supervised!(
        {AdaptorRegistry, name: :version_registry, use_cache: cache}
      )

      start_supervised!(
        {AdaptorService,
         name: :version_service,
         adaptors_path: "/tmp/fake_version",
         repo: StubRepo,
         adaptor_registry: :version_registry}
      )

      :ok
    end

    test "find_adaptor/2 doesn't raise for local, arbitrary, or empty versions" do
      for version <- ["local", "next", ""] do
        assert AdaptorService.find_adaptor(
                 :version_service,
                 {@permitted, version}
               ) ==
                 nil,
               "expected version #{inspect(version)} to simply not match, not raise"
      end
    end

    test "installed?/2 doesn't raise for local, arbitrary, or empty versions" do
      for version <- ["local", "next", ""] do
        refute AdaptorService.installed?(:version_service, {@permitted, version})
      end
    end
  end

  describe "resolve_package_name/1" do
    test "splits a well-formed package string" do
      assert AdaptorService.resolve_package_name("@openfn/language-http@1.2.3") ==
               {"@openfn/language-http", "1.2.3"}

      assert AdaptorService.resolve_package_name("@openfn/language-http") ==
               {"@openfn/language-http", nil}
    end

    test "returns {nil, nil} for malformed / injection-shaped strings, not raising" do
      for bad <- [
            "@openfn/x\npwd\nb@1.0.0",
            "@openfn/language-http@1.0.0; touch /tmp/x",
            "@openfn/language-common@latest and stuff",
            "$(whoami)",
            ""
          ] do
        assert AdaptorService.resolve_package_name(bad) == {nil, nil},
               "expected #{inspect(bad)} to be rejected"
      end
    end
  end
end

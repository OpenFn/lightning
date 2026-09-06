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

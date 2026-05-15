defmodule Lightning.InstallSchemasTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog
  require Logger

  alias Mix.Tasks.Lightning.InstallSchemas

  @registry_url "https://registry.npmjs.org/-/user/openfn/package"
  @registry_request_options [recv_timeout: 15_000, pool: :default]

  # Per-package recv_timeouts as the implementation escalates them.
  @first_attempt_opts [recv_timeout: 30_000, pool: :default]
  @second_attempt_opts [recv_timeout: 15_000, pool: :default]
  @third_attempt_opts [recv_timeout: 5_000, pool: :default]

  @ok_200 {:ok, 200, "headers", :client}
  @ok_400 {:ok, 400, "headers", :client}

  @schemas_path Application.compile_env(:lightning, :schemas_path)

  # --- helpers ----------------------------------------------------------

  defp schema_url(package_name) do
    "https://cdn.jsdelivr.net/npm/#{package_name}/configuration-schema.json"
  end

  defp expect_registry(response) do
    expect(:hackney, :request, fn
      :get, @registry_url, [], "", @registry_request_options -> response
    end)
  end

  defp expect_body(body) do
    expect(:hackney, :body, fn :client, _timeout -> body end)
  end

  # Stub a single jsdelivr fetch attempt for `package_name` at the given
  # timeout-options profile, returning `response`.
  defp expect_schema_request(package_name, opts, response) do
    url = schema_url(package_name)

    expect(:hackney, :request, fn
      :get, ^url, [], "", ^opts -> response
    end)
  end

  # Stub all three escalating attempts for `package_name` with the same
  # error response (used when verifying retry-exhaustion behaviour).
  defp expect_all_attempts_error(package_name, reason) do
    error = {:error, reason}

    expect_schema_request(package_name, @first_attempt_opts, error)
    expect_schema_request(package_name, @second_attempt_opts, error)
    expect_schema_request(package_name, @third_attempt_opts, error)
  end

  describe "install_schemas mix task" do
    setup do
      stub(:hackney)
      :ok
    end

    test "run reports a tally of installed and skipped packages" do
      # Registry returns 3 packages:
      #   language-common  -> excluded by default
      #   language-asana   -> installed on first attempt
      #   language-primero -> skipped after exhausting all retries
      expect_registry(@ok_200)

      expect_body(
        {:ok,
         ~s({"@openfn/language-common": "write", "@openfn/language-asana": "write", "@openfn/language-primero": "write"})}
      )

      expect_schema_request(
        "@openfn/language-asana",
        @first_attempt_opts,
        @ok_200
      )

      expect_body({:ok, ~s({"name": "language-asana"})})

      expect_all_attempts_error("@openfn/language-primero", :timeout)

      File
      |> expect(:rm_rf, fn _ -> nil end)
      |> expect(:mkdir_p, fn _ -> nil end)
      |> expect(:open!, fn "test/fixtures/schemas/asana.json", [:write] ->
        nil
      end)
      |> expect(:close, fn _ -> nil end)

      expect(IO, :binwrite, fn _, ~s({"name": "language-asana"}) -> nil end)

      {output, log} =
        with_log(fn ->
          capture_io(fn ->
            InstallSchemas.run([])
          end)
        end)

      assert output =~ "1 installed, 1 skipped"

      assert log =~
               "Skipping @openfn/language-primero: :timeout after 3 attempt(s)"
    end

    test "run raises when the schemas directory cannot be created" do
      expect(File, :rm_rf, fn _ -> {:error, "error occured"} end)
      expect(File, :mkdir_p, fn _ -> {:error, "error occured"} end)

      assert_raise RuntimeError,
                   "Couldn't create the schemas directory: test/fixtures/schemas, got :error occured.",
                   fn ->
                     InstallSchemas.run([])
                   end
    end

    test "persist_schema retries transient errors then succeeds" do
      # First attempt times out; second succeeds. We also verify that the
      # retry escalates to the 15s recv_timeout profile.
      expect_schema_request(
        "@openfn/language-asana",
        @first_attempt_opts,
        {:error, :timeout}
      )

      expect_schema_request(
        "@openfn/language-asana",
        @second_attempt_opts,
        @ok_200
      )

      expect_body({:ok, ~s({"name": "language-asana"})})

      File
      |> expect(:open!, fn "test/fixtures/schemas/asana.json", [:write] ->
        nil
      end)
      |> expect(:close, fn _ -> nil end)

      expect(IO, :binwrite, fn _, ~s({"name": "language-asana"}) -> nil end)

      {result, log} =
        with_log(fn ->
          InstallSchemas.persist_schema(@schemas_path, "@openfn/language-asana")
        end)

      assert result == {:installed, "@openfn/language-asana"}

      assert log =~
               "Transient error fetching @openfn/language-asana (:timeout); retrying with recv_timeout=15000ms"
    end

    test "persist_schema skips after exhausting all retries" do
      expect_all_attempts_error("@openfn/language-asana", :timeout)

      {result, log} =
        with_log(fn ->
          InstallSchemas.persist_schema(@schemas_path, "@openfn/language-asana")
        end)

      assert result == {:skipped, "@openfn/language-asana", :timeout}

      assert log =~
               "Skipping @openfn/language-asana: :timeout after 3 attempt(s)"
    end

    test "persist_schema skips immediately on non-retriable errors" do
      # :nxdomain is not in @retriable_reasons, so we expect exactly one
      # attempt (no retry) and an "after 1 attempt(s)" log line.
      expect_schema_request(
        "@openfn/language-asana",
        @first_attempt_opts,
        {:error, :nxdomain}
      )

      {result, log} =
        with_log(fn ->
          InstallSchemas.persist_schema(@schemas_path, "@openfn/language-asana")
        end)

      assert result == {:skipped, "@openfn/language-asana", :nxdomain}

      assert log =~
               "Skipping @openfn/language-asana: :nxdomain after 1 attempt(s)"
    end

    test "persist_schema skips on non-200 status without retrying" do
      expect_schema_request(
        "@openfn/language-asana",
        @first_attempt_opts,
        @ok_400
      )

      expect_body({:ok, ""})

      {result, log} =
        with_log(fn ->
          InstallSchemas.persist_schema(@schemas_path, "@openfn/language-asana")
        end)

      assert {:skipped, "@openfn/language-asana", {:http_status, 400}} = result

      assert log =~
               "Unable to fetch @openfn/language-asana configuration schema. status=400"
    end

    test "fetch_schemas raises when the registry request errors" do
      expect_registry(@ok_200)
      expect_body({:error, %HTTPoison.Error{}})

      assert_raise RuntimeError,
                   ~r/Unable to connect to NPM; no adaptors fetched: /,
                   fn -> InstallSchemas.fetch_schemas([]) end
    end

    test "fetch_schemas raises when the registry returns a non-200 status" do
      expect_registry(@ok_400)
      expect_body({:ok, ""})

      assert_raise RuntimeError,
                   "Unable to access openfn user packages. status=400",
                   fn -> InstallSchemas.fetch_schemas([]) end
    end

    test "fetch_schemas preserves the package name when a worker crashes" do
      # Regression guard: an earlier bug surfaced the {:exit, _} branch with
      # the name "unknown" because results weren't zipped against the input
      # names. We feed fetch_schemas a worker that always raises and assert
      # the skip tuple still carries the package name.
      expect_registry(@ok_200)
      expect_body({:ok, ~s({"@openfn/language-boom": "write"})})

      crashing_fun = fn _name -> raise "boom" end

      {results, log} =
        with_log(fn ->
          InstallSchemas.fetch_schemas([], crashing_fun) |> Enum.to_list()
        end)

      assert [{:skipped, "@openfn/language-boom", _reason}] = results
      assert log =~ "Schema fetch worker for @openfn/language-boom crashed"
    end

    test "parse_excluded merges CLI args with defaults" do
      assert [
               "pack1",
               "pack2",
               "language-common",
               "language-devtools",
               "language-divoc"
             ] ==
               InstallSchemas.parse_excluded(["--exclude", "pack1", "pack2"])

      assert ["language-common", "language-devtools", "language-divoc"] ==
               InstallSchemas.parse_excluded([])
    end
  end
end

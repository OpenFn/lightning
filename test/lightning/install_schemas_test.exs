defmodule Lightning.InstallSchemasTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog
  require Logger

  alias Mix.Tasks.Lightning.InstallSchemas

  @registry_request_options [recv_timeout: 15_000, pool: :default]
  @first_attempt_opts [recv_timeout: 30_000, pool: :default]
  @second_attempt_opts [recv_timeout: 15_000, pool: :default]
  @third_attempt_opts [recv_timeout: 5_000, pool: :default]
  @ok_200 {:ok, 200, "headers", :client}
  @ok_400 {:ok, 400, "headers", :client}

  @schemas_path Application.compile_env(:lightning, :schemas_path)

  describe "install_schemas mix task" do
    setup do
      stub(:hackney)
      :ok
    end

    test "run success" do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        @registry_request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok,
         ~s({"@openfn/language-primero": "write","@openfn/language-asana": "write", "@openfn/language-common": "write"})}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @first_attempt_opts ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-asana"})}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-primero/configuration-schema.json",
        [],
        "",
        @first_attempt_opts ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-primero"})}
      end)

      File
      |> expect(:rm_rf, fn _ -> nil end)
      |> expect(:mkdir_p, fn _ -> nil end)
      |> expect(:open!, fn
        "test/fixtures/schemas/primero.json", [:write] -> nil
        "test/fixtures/schemas/asana.json", [:write] -> nil
      end)
      |> expect(:close, 2, fn _ -> nil end)

      IO
      |> expect(:binwrite, fn _, ~s({"name": "language-asana"}) -> nil end)
      |> expect(:binwrite, fn _, ~s({"name": "language-primero"}) -> nil end)

      output =
        capture_io(fn ->
          InstallSchemas.run([])
        end)

      assert output =~ "2 installed, 0 skipped"
    end

    test "run fail" do
      expect(File, :rm_rf, fn _ -> {:error, "error occured"} end)
      expect(File, :mkdir_p, fn _ -> {:error, "error occured"} end)

      assert_raise RuntimeError,
                   "Couldn't create the schemas directory: test/fixtures/schemas, got :error occured.",
                   fn ->
                     InstallSchemas.run([])
                   end
    end

    test "persist_schema retries then succeeds" do
      # First attempt times out
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @first_attempt_opts ->
          {:error, :timeout}
      end)

      # Second attempt succeeds
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @second_attempt_opts ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-asana"})}
      end)

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

    test "persist_schema logs and skips after all retries fail" do
      # All three attempts time out
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @first_attempt_opts ->
          {:error, :timeout}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @second_attempt_opts ->
          {:error, :timeout}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @third_attempt_opts ->
          {:error, :timeout}
      end)

      {result, log} =
        with_log(fn ->
          InstallSchemas.persist_schema(@schemas_path, "@openfn/language-asana")
        end)

      assert result == {:skipped, "@openfn/language-asana", :timeout}
      assert log =~ "Skipping @openfn/language-asana: :timeout after 3 attempts"
    end

    test "persist_schema HTTP 400" do
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @first_attempt_opts ->
          @ok_400
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ""}
      end)

      {result, log} =
        with_log(fn ->
          InstallSchemas.persist_schema(@schemas_path, "@openfn/language-asana")
        end)

      assert {:skipped, "@openfn/language-asana", {:http_status, 400}} = result

      assert log =~
               "Unable to fetch @openfn/language-asana configuration schema. status=400"
    end

    test "fetch_schemas fail 1" do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        @registry_request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:error, %HTTPoison.Error{}}
      end)

      assert_raise RuntimeError,
                   ~r/Unable to connect to NPM; no adaptors fetched: /,
                   fn ->
                     InstallSchemas.fetch_schemas([])
                   end
    end

    test "fetch_schemas fail 2" do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        @registry_request_options ->
          @ok_400
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ""}
      end)

      assert_raise RuntimeError,
                   "Unable to access openfn user packages. status=400",
                   fn ->
                     InstallSchemas.fetch_schemas([])
                   end
    end

    test "run reports skipped packages in the tally" do
      # Registry returns 3 packages: language-common (excluded), language-asana (succeeds), language-primero (fails all retries)
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        @registry_request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok,
         ~s({"@openfn/language-common": "write", "@openfn/language-asana": "write", "@openfn/language-primero": "write"})}
      end)

      # language-asana: first attempt succeeds
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @first_attempt_opts ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-asana"})}
      end)

      # language-primero: all three attempts fail
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-primero/configuration-schema.json",
        [],
        "",
        @first_attempt_opts ->
          {:error, :timeout}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-primero/configuration-schema.json",
        [],
        "",
        @second_attempt_opts ->
          {:error, :timeout}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-primero/configuration-schema.json",
        [],
        "",
        @third_attempt_opts ->
          {:error, :timeout}
      end)

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
               "Skipping @openfn/language-primero: :timeout after 3 attempts"
    end

    test "parse_excluded" do
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

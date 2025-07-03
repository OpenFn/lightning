defmodule Lightning.Adaptors.NPMTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox
  import Tesla.Test

  alias Lightning.Adaptors.NPM

  setup :verify_on_exit!

  setup_all do
    %{
      language_common_body:
        File.read!("test/fixtures/language-common-npm.json") |> Jason.decode!(),
      language_salesforce_body:
        File.read!("test/fixtures/language-salesforce-npm.json")
        |> Jason.decode!()
    }
  end

  describe "fetch_packages/1" do
    test "returns a list of all packages" do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          case env.url do
            "https://registry.npmjs.org/-/user/openfn/package" ->
              {:ok,
               json(
                 %Tesla.Env{status: 200},
                 File.read!("test/fixtures/openfn-packages-npm.json")
                 |> Jason.decode!()
               )}
          end
        end
      )

      {:ok, adaptors} =
        NPM.fetch_packages(
          user: "openfn",
          max_concurrency: 10,
          timeout: 30_000,
          filter: fn name ->
            name not in [
              "@openfn/language-devtools",
              "@openfn/language-template",
              "@openfn/language-fhir-jembi",
              "@openfn/language-collections"
            ] &&
              Regex.match?(~r/@openfn\/language-\w+/, name)
          end
        )

      expected_adaptors =
        [
          "@openfn/language-asana",
          "@openfn/language-common",
          "@openfn/language-commcare",
          "@openfn/language-dhis2",
          "@openfn/language-http",
          "@openfn/language-salesforce"
        ]

      assert adaptors |> Enum.sort() == expected_adaptors |> Enum.sort()
    end

    test "handles errors when fetching user packages" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] -> {:error, :nxdomain} end
      )

      assert NPM.fetch_packages(
               user: "openfn",
               max_concurrency: 10,
               timeout: 30_000,
               filter: fn _ -> true end
             ) == {:error, :nxdomain}
    end
  end

  describe "fetch_versions/1" do
    test "returns a list of all versions", %{
      language_salesforce_body: language_salesforce_body
    } do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          assert env.url ==
                   "https://registry.npmjs.org/@openfn/language-salesforce"

          {:ok, json(%Tesla.Env{status: 200}, language_salesforce_body)}
        end
      )

      deprecated_length =
        length(
          language_salesforce_body["versions"]
          |> Map.values()
          |> Enum.filter(& &1["deprecated"])
        )

      dist_tags_length =
        length(language_salesforce_body["dist-tags"] |> Map.keys())

      {:ok, versions} =
        NPM.fetch_versions(
          [timeout: 30_000, user: "openfn"],
          "@openfn/language-salesforce"
        )

      version_keys = versions |> Map.keys() |> Enum.sort()

      assert length(version_keys) == 87 - deprecated_length + dist_tags_length
    end

    test "handles errors when fetching package versions" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] -> {:error, :nxdomain} end
      )

      assert NPM.fetch_versions(
               [timeout: 30_000, user: "openfn"],
               "@openfn/language-salesforce"
             ) == {:error, :nxdomain}
    end
  end

  describe "config validation" do
    test "validates required user field" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages([])

      assert error.message =~ "required :user option not found"
    end

    test "validates user field type" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: 123)

      assert error.message =~ "expected string, got: 123"
    end

    test "validates max_concurrency type" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: "openfn", max_concurrency: "invalid")

      assert error.message =~ "expected positive integer"
    end

    test "validates max_concurrency is positive" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: "openfn", max_concurrency: 0)

      assert error.message =~ "expected positive integer, got: 0"
    end

    test "validates timeout type" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: "openfn", timeout: "invalid")

      assert error.message =~ "expected positive integer"
    end

    test "validates timeout is positive" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: "openfn", timeout: -1)

      assert error.message =~ "expected positive integer, got: -1"
    end

    test "validates filter function arity" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: "openfn", filter: fn -> true end)

      assert error.message =~ "expected function of arity 1"
    end

    test "validates filter type" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: "openfn", filter: "not_a_function")

      assert error.message =~ "expected function of arity 1"
    end

    test "accepts valid minimal config with defaults" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] -> {:error, :nxdomain} end
      )

      assert {:error, :nxdomain} = NPM.fetch_packages(user: "openfn")
    end

    test "accepts valid full config" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] -> {:error, :nxdomain} end
      )

      assert {:error, :nxdomain} =
               NPM.fetch_packages(
                 user: "openfn",
                 max_concurrency: 5,
                 timeout: 15_000,
                 filter: fn name -> String.contains?(name, "language") end
               )
    end

    test "rejects unknown options" do
      assert {:error, %NimbleOptions.ValidationError{} = error} =
               NPM.fetch_packages(user: "openfn", unknown_option: "rejected")

      assert error.message =~ "unknown options [:unknown_option]"
    end
  end

  describe "fetch_configuration_schema/1" do
    test "successfully fetches credential schema" do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          assert env.url ==
                   "https://cdn.jsdelivr.net/npm/@openfn/language-http/configuration-schema.json"

          # Return raw JSON string, not decoded JSON
          schema_json = File.read!("test/fixtures/schemas/http.json")
          {:ok, json(%Tesla.Env{status: 200}, schema_json)}
        end
      )

      assert {:ok, schema} =
               NPM.fetch_configuration_schema("@openfn/language-http")

      # Verify the schema structure - schema is a Jason.OrderedObject
      assert %Jason.OrderedObject{} = schema
      assert schema["$schema"] == "http://json-schema.org/draft-07/schema#"
      assert schema["type"] == "object"
      assert %Jason.OrderedObject{} = schema["properties"]
      assert schema["properties"]["username"]["title"] == "Username"
      assert schema["properties"]["password"]["writeOnly"] == true
    end

    test "handles 404 when schema not found" do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          assert env.url ==
                   "https://cdn.jsdelivr.net/npm/@openfn/language-common/configuration-schema.json"

          {:ok, %Tesla.Env{status: 404, body: %{}}}
        end
      )

      assert {:error, :not_found} =
               NPM.fetch_configuration_schema("@openfn/language-common")
    end

    test "handles unexpected HTTP status codes" do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          assert env.url ==
                   "https://cdn.jsdelivr.net/npm/@openfn/language-dhis2/configuration-schema.json"

          {:ok, %Tesla.Env{status: 500, body: %{}}}
        end
      )

      assert capture_log(fn ->
               assert {:error, {:unexpected_status, 500}} =
                        NPM.fetch_configuration_schema("@openfn/language-dhis2")
             end) =~
               "Unexpected status 500 when fetching schema for @openfn/language-dhis2"
    end

    test "handles network errors" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] ->
          {:error, :nxdomain}
        end
      )

      assert capture_log(fn ->
               assert {:error, :nxdomain} =
                        NPM.fetch_configuration_schema("@openfn/language-http")
             end) =~
               "Failed to fetch credential schema for @openfn/language-http: "
    end

    test "handles timeout errors" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] ->
          {:error, :timeout}
        end
      )

      assert capture_log(fn ->
               assert {:error, :timeout} =
                        NPM.fetch_configuration_schema("@openfn/language-http")
             end) =~
               "Failed to fetch credential schema for @openfn/language-http: "
    end

    test "preserves JSON object key ordering" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] ->
          # Return the schema as raw JSON string to test decoding
          schema_json = File.read!("test/fixtures/schemas/http.json")
          {:ok, json(%Tesla.Env{status: 200}, schema_json)}
        end
      )

      assert {:ok, schema} =
               NPM.fetch_configuration_schema("@openfn/language-http")

      # Verify that the schema is decoded as OrderedObject (which preserves order)
      assert %Jason.OrderedObject{} = schema
      assert schema["properties"]["username"]["title"] == "Username"
      assert schema["properties"]["password"]["writeOnly"] == true
      assert schema["properties"]["baseUrl"]["format"] == "uri"

      # Verify it's actually an OrderedObject, not a regular map
      assert %Jason.OrderedObject{} = schema["properties"]
      assert %Jason.OrderedObject{} = schema["properties"]["username"]
    end

    @tag :capture_log
    test "handles malformed JSON gracefully" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] ->
          {:ok, json(%Tesla.Env{status: 200}, "invalid json content")}
        end
      )

      assert capture_log(fn ->
               assert {:error, {:invalid_json, %Jason.DecodeError{}}} =
                        NPM.fetch_configuration_schema("@openfn/language-http")
             end) =~
               "Failed to decode JSON schema for @openfn/language-http: "
    end

    test "constructs correct URLs for different package names" do
      test_cases = [
        {"@openfn/language-http",
         "https://cdn.jsdelivr.net/npm/@openfn/language-http/configuration-schema.json"},
        {"@openfn/language-dhis2",
         "https://cdn.jsdelivr.net/npm/@openfn/language-dhis2/configuration-schema.json"},
        {"some-package",
         "https://cdn.jsdelivr.net/npm/some-package/configuration-schema.json"}
      ]

      Enum.each(test_cases, fn {package_name, expected_url} ->
        expect_tesla_call(
          times: 1,
          returns: fn env, [] ->
            assert env.url == expected_url
            {:ok, %Tesla.Env{status: 404, body: %{}}}
          end
        )

        NPM.fetch_configuration_schema(package_name)
      end)
    end
  end
end

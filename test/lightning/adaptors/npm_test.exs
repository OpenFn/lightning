defmodule Lightning.Adaptors.NPMTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mox
  import Tesla.Test

  alias Lightning.Adaptors.NPM

  setup :verify_on_exit!

  describe "fetch_packages/1" do
    setup do
      %{
        default_npm_response:
          File.read!("test/fixtures/language-common-npm.json") |> Jason.decode!()
      }
    end

    test "returns a list of all packages", %{
      default_npm_response: default_npm_response
    } do
      expect_tesla_call(
        times: 7,
        returns: fn env, [] ->
          case env.url do
            "https://registry.npmjs.org/-/user/openfn/package" ->
              {:ok,
               json(
                 %Tesla.Env{status: 200},
                 File.read!("test/fixtures/openfn-packages-npm.json")
                 |> Jason.decode!()
               )}

            "https://registry.npmjs.org/@openfn/" <> adaptor ->
              {:ok,
               json(
                 %Tesla.Env{status: 200},
                 Map.merge(default_npm_response, %{
                   "name" => "@openfn/#{adaptor}"
                 })
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
        |> MapSet.new()

      assert adaptors |> Enum.map(& &1.name) |> MapSet.new() == expected_adaptors
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

    test "handles errors when fetching adaptor details", %{
      default_npm_response: default_npm_response
    } do
      expect_tesla_call(
        times: 14,
        returns: fn env, [] ->
          case env.url do
            "https://registry.npmjs.org/-/user/openfn/package" ->
              {:ok,
               json(
                 %Tesla.Env{status: 200},
                 File.read!("test/fixtures/openfn-packages-npm.json")
                 |> Jason.decode!()
               )}

            "https://registry.npmjs.org/@openfn/language-asana" ->
              {:ok, json(%Tesla.Env{status: 404}, %{})}

            "https://registry.npmjs.org/@openfn/" <> adaptor ->
              {:ok,
               json(
                 %Tesla.Env{status: 200},
                 Map.merge(default_npm_response, %{
                   "name" => "@openfn/#{adaptor}"
                 })
               )}
          end
        end
      )

      {:ok, packages} =
        NPM.fetch_packages(
          user: "openfn",
          max_concurrency: 10,
          timeout: 30_000,
          filter: fn _ -> true end
        )

      assert Enum.any?(packages, fn adaptor ->
               adaptor.name == "@openfn/language-common"
             end)

      refute {:name, "@openfn/language-asana"} in packages
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

  describe "fetch_credential_schema/2" do
    test "successfully fetches credential schema" do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          assert env.url ==
                   "https://cdn.jsdelivr.net/npm/@openfn/language-http@1.2.3/configuration-schema.json"

          # Return raw JSON string, not decoded JSON
          schema_json = File.read!("test/fixtures/schemas/http.json")
          {:ok, json(%Tesla.Env{status: 200}, schema_json)}
        end
      )

      assert {:ok, schema} =
               NPM.fetch_credential_schema("@openfn/language-http", "1.2.3")

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
                   "https://cdn.jsdelivr.net/npm/@openfn/language-common@2.0.0/configuration-schema.json"

          {:ok, %Tesla.Env{status: 404, body: %{}}}
        end
      )

      assert {:error, :not_found} =
               NPM.fetch_credential_schema("@openfn/language-common", "2.0.0")
    end

    test "handles unexpected HTTP status codes" do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          assert env.url ==
                   "https://cdn.jsdelivr.net/npm/@openfn/language-dhis2@latest/configuration-schema.json"

          {:ok, %Tesla.Env{status: 500, body: %{}}}
        end
      )

      assert {:error, {:unexpected_status, 500}} =
               NPM.fetch_credential_schema("@openfn/language-dhis2", "latest")
    end

    test "handles network errors" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] ->
          {:error, :nxdomain}
        end
      )

      assert {:error, :nxdomain} =
               NPM.fetch_credential_schema("@openfn/language-http", "1.0.0")
    end

    test "handles timeout errors" do
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] ->
          {:error, :timeout}
        end
      )

      assert {:error, :timeout} =
               NPM.fetch_credential_schema("@openfn/language-http", "1.0.0")
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
               NPM.fetch_credential_schema("@openfn/language-http", "1.0.0")

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
                        NPM.fetch_credential_schema(
                          "@openfn/language-http",
                          "1.0.0"
                        )
             end) =~
               "Failed to decode JSON schema for @openfn/language-http@1.0.0: "
    end

    test "constructs correct URLs for different package names and versions" do
      test_cases = [
        {"@openfn/language-http", "1.2.3",
         "https://cdn.jsdelivr.net/npm/@openfn/language-http@1.2.3/configuration-schema.json"},
        {"@openfn/language-dhis2", "latest",
         "https://cdn.jsdelivr.net/npm/@openfn/language-dhis2@latest/configuration-schema.json"},
        {"some-package", "0.1.0",
         "https://cdn.jsdelivr.net/npm/some-package@0.1.0/configuration-schema.json"}
      ]

      Enum.each(test_cases, fn {package_name, version, expected_url} ->
        expect_tesla_call(
          times: 1,
          returns: fn env, [] ->
            assert env.url == expected_url
            {:ok, %Tesla.Env{status: 404, body: %{}}}
          end
        )

        NPM.fetch_credential_schema(package_name, version)
      end)
    end
  end
end

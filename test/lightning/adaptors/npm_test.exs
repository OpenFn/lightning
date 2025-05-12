defmodule Lightning.Adaptors.NPMTest do
  use ExUnit.Case, async: true

  import Mox
  import Tesla.Test

  alias Lightning.Adaptors.NPM

  setup :verify_on_exit!

  describe "get_all_packages/0" do
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

      adaptors =
        NPM.fetch_adaptors(%{
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
        })

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

      assert NPM.fetch_adaptors(%{
               user: "openfn",
               max_concurrency: 10,
               timeout: 30_000,
               filter: fn _ -> true end
             }) == {:error, :nxdomain}
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

      response =
        NPM.fetch_adaptors(%{
          user: "openfn",
          max_concurrency: 10,
          timeout: 30_000,
          filter: fn _ -> true end
        })

      assert Enum.any?(response, fn adaptor ->
               adaptor.name == "@openfn/language-common"
             end)

      refute {:name, "@openfn/language-asana"} in response
    end
  end
end

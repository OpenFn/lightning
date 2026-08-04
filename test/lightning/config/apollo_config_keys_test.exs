defmodule Lightning.Config.ApolloConfigKeysTest do
  use ExUnit.Case, async: true

  # The :apollo config once grew a key (:streaming_timeout) that code read
  # for five months but no environment could set — it silently fell back to
  # a hardcoded default while operators tuned a variable that did nothing.
  # This test makes that class of drift a red build instead: every key the
  # code reads from Lightning.Config.apollo/1 must be one that
  # Config.Bootstrap actually plumbs from the environment.
  @plumbed_keys ~w(endpoint timeout ai_assistant_api_key)

  test "every apollo config key read in lib/ is settable from the environment" do
    consumed_keys =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        content = File.read!(file)

        Regex.scan(~r/apollo\(:(\w+)\)/, content)
        |> Enum.map(fn [_, key] -> {key, file} end)
      end)
      |> Enum.uniq()

    unplumbed =
      Enum.reject(consumed_keys, fn {key, _file} -> key in @plumbed_keys end)

    assert unplumbed == [],
           "These apollo config keys are read by code but cannot be set " <>
             "from the environment (add them to Config.Bootstrap and to " <>
             "@plumbed_keys, or remove the read): #{inspect(unplumbed)}"
  end
end

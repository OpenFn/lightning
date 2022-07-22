defmodule Lightning.Credentials.SensitiveValues do
  @moduledoc """
  Functions to pull out sensitive values inside a credential.

  These values are used to scrub logs for leaked secrets.
  """

  @doc """
  Keys that are _not_ considered sensitive
  """
  @safe_keys [
               "account",
               "apiurl",
               "apiVersion",
               "baseurl",
               "database",
               "email",
               "host",
               "hosturl",
               "instanceurl",
               "loginurl",
               "user",
               "username"
             ]
             |> Enum.map(&String.downcase/1)

  @type pairs :: {String.t(), String.t() | number() | boolean()}
  @type raw_pairs :: {String.t(), pairs | map()}

  @spec flatten_map(item :: %{String.t() => any()} | [raw_pairs()]) :: [pairs()]
  def flatten_map(item) do
    Enum.reduce(item, [], fn {k, v}, acc ->
      case v do
        v when is_map(v) ->
          Enum.concat(flatten_map(v), acc)

        v when is_list(v) ->
          Enum.map(v, &{k, &1}) |> flatten_map() |> Enum.concat(acc)

        _ ->
          [{k, v}] ++ acc
      end
    end)
  end

  @doc """
  Given a map, find all values allowed (via `@safe_keys`) and return them as
  a list.
  """
  @spec secret_values(map :: %{String.t() => any()}) :: [
          String.t() | number() | boolean()
        ]
  def secret_values(map) do
    flatten_map(map)
    |> Enum.reject(fn {k, v} -> String.downcase(k) in @safe_keys || is_nil(v) end)
    |> Enum.map(fn {_k, v} -> v end)
  end
end

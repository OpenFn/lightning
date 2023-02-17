defmodule Lightning.SafetyString do
  @moduledoc """
  Utilities for securely encoding serializable structs, lists and strings into
  URL-safe strings.

  In order to pass the state around in a URL, in a manner that protects
  secrets from leaking - and allows us to avoid persistance
  we take a set of parameters and:

  - Encode into a URI query string
  - gzip it to save characters
  - encrypt the string
  - base64 encode it for URI encoding safety
  """
  @vault Lightning.Vault

  @spec decode(data :: binary) ::
          {:error, String.t()} | %{optional(binary) => binary} | list(binary)
  def decode(data) when is_binary(data) do
    data
    |> Base.url_decode64!(padding: false)
    |> @vault.decrypt!()
    |> case do
      :error ->
        {:error, "Decryption failed."}

      "|" <> result when is_binary(result) ->
        result |> String.split("|") |> Enum.map(&to_string/1)

      result when is_binary(result) ->
        result |> URI.decode_query()
    end
  end

  @spec encode(data :: struct() | map() | binary | list(binary)) :: binary
  def encode(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> encode()
  end

  def encode(data) when is_map(data) do
    data
    |> Map.filter(fn {_k, v} -> !is_nil(v) end)
    |> URI.encode_query()
    |> encode()
  end

  def encode(list) when is_list(list) do
    [nil | list]
    |> Enum.join("|")
    |> encode()
  end

  def encode(data) when is_binary(data) do
    data
    |> @vault.encrypt!()
    |> Base.url_encode64(padding: false)
  end
end

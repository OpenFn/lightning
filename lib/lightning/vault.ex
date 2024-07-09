defmodule Lightning.Vault do
  @moduledoc """
  Module for handling the encryption and decryption of database fields.
  """
  use Cloak.Vault, otp_app: :lightning
  require Logger

  @impl GenServer
  def init(config) do
    key = get_and_check_key(config)

    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key}
      )

    {:ok, config}
  end

  defp get_and_check_key(config) do
    case config[:primary_encryption_key] do
      nil ->
        Logger.error("""
        An encryption key must be provided via an env variable:

        PRIMARY_ENCRYPTION_KEY=...

        or via application config using:

        config :lightning, Lightning.Vault,
          primary_encryption_key: "..."

        You can use `mix lightning.gen_encryption_key` to generate one.
        """)

        raise "Primary encryption key not found."

      encoded ->
        encoded
        |> decode_key!()
        |> validate_key_length!()
    end
  end

  defp decode_key!(encoded) do
    encoded
    |> Base.decode64()
    |> case do
      {:ok, decoded} ->
        decoded

      :error ->
        Logger.error("""
        An encryption key must be Base64 encoded.

        Please note that Base64 URL alphabets are not currently supported.

        You can use `mix lightning.gen_encryption_key` to generate a valid key.
        """)

        raise "Encountered an error when decoding the primary encryption key."
    end
  end

  defp validate_key_length!(key) do
    if bit_size(key) != 256 do
      Logger.error("""
      The primary encryption key must be exactly 256 bits.

      You can use `mix lightning.gen_encryption_key` to generate one.
      """)

      raise "Primary encryption key is invalid."
    else
      key
    end
  end
end

defmodule Lightning.Encrypted.Map do
  @moduledoc false
  use Cloak.Ecto.Map, vault: Lightning.Vault
end

defmodule Lightning.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Lightning.Vault

  # From https://github.com/danielberkompas/cloak/issues/84
  # TODO How do I test this?
  def embed_as(_format), do: :dump

  def dump(nil), do: super(nil)

  def dump(value) do
    with {:ok, encrypted} <- super(value) do
      {:ok, Base.encode64(encrypted)}
    end
  end

  def load(nil), do: super(nil)

  def load(value), do: super(Base.decode64!(value))
end

defmodule Lightning.Vault do
  @moduledoc """
  Module for handling the encryption and decryption of database fields.
  """
  use Cloak.Vault, otp_app: :lightning
  require Logger

  @impl GenServer
  def init(config) do
    key =
      System.get_env("PRIMARY_ENCRYPTION_KEY", config[:primary_encryption_key])

    if !key do
      Logger.error("""
      An encryption key must be provided via an env variable:

      PRIMARY_ENCRYPTION_KEY=...

      or via application config using:

      config :lightning, Lightning.Vaul,
        primary_encryption_key: "..."

      You can use `mix lightning.gen_encryption_key` to generate one.
      """)

      raise "Primary encryption key not found."
    end

    config =
      Keyword.put(config, :ciphers,
        default:
          {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(key)}
      )

    {:ok, config}
  end
end

defmodule Lightning.Encrypted.Map do
  @moduledoc false
  use Cloak.Ecto.Map, vault: Lightning.Vault
end

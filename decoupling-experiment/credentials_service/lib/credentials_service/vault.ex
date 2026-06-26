defmodule CredentialsService.Vault do
  @moduledoc """
  Cloak vault for encrypting credential bodies at rest.

  Mirrors `Lightning.Vault` in the monolith. The single most important
  decoupling finding for this slice: **the encryption key travels with the
  data.** Any service that owns the `credential_bodies` table must also hold the
  AES key (or run a re-encryption migration), because `credential_bodies.body`
  is only ever stored as ciphertext.

  For this experiment the key is derived from a static string so the slice runs
  with zero configuration. A real deployment injects key material from the
  environment exactly as Lightning does (`PRIMARY_ENCRYPTION_KEY`).
  """
  use Cloak.Vault, otp_app: :credentials_service

  @impl GenServer
  def init(config) do
    key = :crypto.hash(:sha256, "credentials-service-experiment-key-do-not-use-in-prod")

    config =
      Keyword.put(config, :ciphers,
        default:
          {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key, iv_length: 12}
      )

    {:ok, config}
  end
end

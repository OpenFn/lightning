defmodule CredentialsService.Encrypted.Map do
  @moduledoc """
  Cloak-encrypted JSON map Ecto type. Mirrors `Lightning.Encrypted.Map`.
  Used for `credential_bodies.body`, the only secret store in the slice.
  """
  use Cloak.Ecto.Map, vault: CredentialsService.Vault
end

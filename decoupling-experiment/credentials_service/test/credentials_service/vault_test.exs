defmodule CredentialsService.VaultTest do
  @moduledoc "Encryption boundary: the vault round-trips and produces ciphertext."
  use ExUnit.Case, async: false

  alias CredentialsService.Vault

  test "encrypt/decrypt round-trips a value" do
    plaintext = "supersecret-marker"
    ciphertext = Vault.encrypt!(plaintext)

    assert is_binary(ciphertext)
    refute ciphertext == plaintext
    refute ciphertext =~ "supersecret-marker"
    assert Vault.decrypt!(ciphertext) == plaintext
  end
end

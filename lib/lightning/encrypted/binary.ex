defmodule Lightning.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Lightning.Vault
end

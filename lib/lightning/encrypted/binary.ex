defmodule Lightning.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Lightning.Vault

  # From https://github.com/danielberkompas/cloak/issues/84
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

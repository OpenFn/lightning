defmodule Mix.Tasks.Lightning.GenEncryptionKey do
  @shortdoc "Generate a unique Base64 encoded encryption key"

  @moduledoc """
  Helper to generate a unique encryption key for Vault
  """

  use Mix.Task

  @impl Mix.Task
  def run(_) do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64() |> IO.puts()
  end
end

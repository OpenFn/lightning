defmodule Mix.Tasks.Lightning.InstallSchemas do
  @shortdoc "Install the credential json schemas"

  @moduledoc """
  Install the credential json schemas.

  Use `--exclude language-package1 language-package2` to exclude specific
  packages.

  All core logic lives in `Lightning.CredentialSchemas`; this task only
  handles HTTP startup and CLI output.
  """

  use Mix.Task

  @impl true
  def run(args) do
    HTTPoison.start()

    excluded = Lightning.CredentialSchemas.parse_excluded(args)

    case Lightning.CredentialSchemas.refresh(excluded) do
      {:ok, count} ->
        Mix.shell().info("Schemas installation has finished. #{count} installed")

      {:error, reason} ->
        Mix.raise("Schema installation failed: #{inspect(reason)}")
    end
  end
end

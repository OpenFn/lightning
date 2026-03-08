defmodule Mix.Tasks.Lightning.InstallSchemas do
  @shortdoc "Install the credential json schemas"

  @moduledoc """
  Install the credential json schemas.

  ## Modes

  - Default (filesystem): writes schemas to `schemas_path` for baking into
    Docker images at build time.
  - `--db`: starts the app and writes schemas directly to the database via
    `Lightning.AdaptorData`. Useful for seeding a fresh database.

  Use `--exclude language-package1 language-package2` to exclude specific
  packages.

  All core logic lives in `Lightning.CredentialSchemas`; this task only
  handles HTTP startup and CLI output.
  """

  use Mix.Task

  @impl true
  def run(["--db" | rest]) do
    Mix.Task.run("app.start")

    excluded = Lightning.CredentialSchemas.parse_excluded(rest)

    case Lightning.CredentialSchemas.fetch_and_store(excluded) do
      {:ok, count} ->
        Mix.shell().info("Schemas stored in database. #{count} installed")

      {:error, reason} ->
        Mix.raise("Schema installation (DB) failed: #{inspect(reason)}")
    end
  end

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

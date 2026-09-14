defmodule Mix.Tasks.Lightning.Kickstart do
  @shortdoc "Populates Lightning from a declarative scenario file"

  @moduledoc """
  Populates Lightning from a declarative scenario file.

  Creates users (with optional API tokens), credentials and projects, and
  provisions workflows through the same engine as the `/api/provision` HTTP
  API. Idempotent: re-running the same scenario converges instead of
  duplicating. See `Lightning.Kickstart` for the file format and semantics.

  The database must already be migrated (`mix ecto.migrate`). Kickstarting is
  a dev/test facility — see `Lightning.Kickstart` — so this task is the only
  way in; there is no release equivalent.

  ## Usage

      mix lightning.kickstart SCENARIO_FILE [OPTIONS]

  ## Arguments

    * `SCENARIO_FILE` - Path to a `.yaml`, `.yml` or `.json` scenario file

  ## Options

    * `--manifest PATH` - Also write a JSON manifest (record ids, API tokens,
      webhook paths) for consumption by scripts or test harnesses

  ## Examples

      mix lightning.kickstart bin/e2e.d/scenarios/example.yaml
      mix lightning.kickstart state.yaml --manifest /tmp/manifest.json
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [manifest: :string])

    unless invalid == [] do
      Mix.raise("Unknown options: #{inspect(invalid)}")
    end

    path =
      case argv do
        [path] ->
          path

        _other ->
          Mix.raise(
            "Usage: mix lightning.kickstart SCENARIO_FILE [--manifest PATH]"
          )
      end

    Mix.Task.run("app.config")

    # Start the repo, the vault (credential bodies are encrypted) and a stub
    # PubSub — but not the endpoint: seeding often runs against an instance
    # that is already serving traffic, and booting it here would fight the
    # running server for the port.
    {:ok, _pid} = Lightning.Setup.ensure_minimum_setup()

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
        Lightning.Kickstart.run_file(path, opts)
      end)

    Mix.shell().info(Lightning.Kickstart.summary(result))
  end
end

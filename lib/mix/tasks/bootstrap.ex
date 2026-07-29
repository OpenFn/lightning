defmodule Mix.Tasks.Lightning.Bootstrap do
  @shortdoc "Populates Lightning from a declarative scenario file"

  @moduledoc """
  Populates Lightning from a declarative scenario file.

  Creates users (with optional API tokens), credentials and projects, and
  provisions workflows through the same engine as the `/api/provision` HTTP
  API. Idempotent: re-running the same scenario converges instead of
  duplicating. See `Lightning.Bootstrap` for the file format and semantics.

  The database must already be migrated (`mix ecto.migrate`). For releases,
  use `bin/lightning eval 'Lightning.Setup.bootstrap("/path/state.yaml")'`
  with `ALLOW_BOOTSTRAP=true` instead.

  ## Usage

      mix lightning.bootstrap SCENARIO_FILE [OPTIONS]

  ## Arguments

    * `SCENARIO_FILE` - Path to a `.yaml`, `.yml` or `.json` scenario file

  ## Options

    * `--manifest PATH` - Also write a JSON manifest (record ids, API tokens,
      webhook paths) for consumption by scripts or test harnesses

  ## Examples

      mix lightning.bootstrap bin/e2e.d/scenarios/example.yaml
      mix lightning.bootstrap state.yaml --manifest /tmp/manifest.json
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
            "Usage: mix lightning.bootstrap SCENARIO_FILE [--manifest PATH]"
          )
      end

    Mix.Task.run("app.config")

    Lightning.Setup.bootstrap(path, opts)
  end
end

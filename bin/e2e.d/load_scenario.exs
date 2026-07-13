# Bootstraps Lightning from a declarative scenario file.
#
# Run via: SCENARIO_FILE=path/to/scenario.yaml mix run --no-start bin/e2e.d/load_scenario.exs
#
# Parsing lives here (rather than in lib/) so the YAML dependency stays out of
# the compiled application. The actual record creation is delegated to
# Lightning.Bootstrap, which uses the regular contexts.

path =
  System.get_env("SCENARIO_FILE") ||
    raise "SCENARIO_FILE environment variable is not set"

unless File.exists?(path) do
  raise "Scenario file not found: #{path}"
end

scenario =
  case Path.extname(path) do
    ext when ext in [".yaml", ".yml"] ->
      {:ok, _} = Application.ensure_all_started(:yamerl)
      YamlElixir.read_from_file!(path)

    ".json" ->
      path |> File.read!() |> Jason.decode!()

    other ->
      raise "Unsupported scenario file extension: #{other} (use .yaml, .yml or .json)"
  end

Lightning.Setup.ensure_minimum_setup()

Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
  result = Lightning.Bootstrap.create_from_map(scenario)
  IO.puts(Lightning.Bootstrap.summary(result))
end)

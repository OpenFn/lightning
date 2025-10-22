defmodule Mix.Tasks.Lightning.MergeProjects do
  @moduledoc """
  Merges two project state files (JSON) and outputs the result.

  This task is useful for merging sandbox projects without requiring database
  access. It takes two state files (source and target) and produces a merged
  state that can be imported.

  ## Usage

      mix lightning.merge_projects SOURCE_FILE TARGET_FILE [OPTIONS]

  ## Arguments

    * `SOURCE_FILE` - Path to the source project state JSON file
    * `TARGET_FILE` - Path to the target project state JSON file

  ## Options

    * `-o, --output PATH` - Write output to file instead of stdout

  ## Examples

      # Merge staging into main, output to stdout
      mix lightning.merge_projects staging.state.json main.state.json

      # Merge and save to file
      mix lightning.merge_projects staging.state.json main.state.json -o merged.json

      # Merge with explicit output flag
      mix lightning.merge_projects staging.state.json main.state.json --output result.json
  """
  use Mix.Task

  alias Lightning.Projects.MergeProjects

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [output: :string],
        aliases: [o: :output]
      )

    cond do
      length(invalid) > 0 ->
        Mix.raise("Invalid options: #{inspect(invalid)}")

      length(positional) != 2 ->
        Mix.raise("""
        Expected exactly 2 arguments: SOURCE_FILE and TARGET_FILE

        Usage:
          mix lightning.merge_projects SOURCE_FILE TARGET_FILE [OPTIONS]

        Run `mix help lightning.merge_projects` for more information.
        """)

      true ->
        [source_file, target_file] = positional
        merge_and_output(source_file, target_file, opts)
    end
  end

  defp merge_and_output(source_file, target_file, opts) do
    source_project = read_state_file(source_file, "source")

    target_project = read_state_file(target_file, "target")

    Mix.shell().info("Merging #{source_file} into #{target_file}...")

    merged_project = MergeProjects.merge_project(source_project, target_project)

    output =
      Jason.encode!(merged_project, pretty: true)

    case Keyword.get(opts, :output) do
      nil ->
        IO.puts(output)

      output_path ->
        File.write!(output_path, output)

        Mix.shell().info("Merged project written to #{output_path}")
    end
  end

  defp read_state_file(path, label) do
    unless File.exists?(path) do
      Mix.raise("#{String.capitalize(label)} file not found: #{path}")
    end

    case File.read!(path) |> Jason.decode() do
      {:ok, data} ->
        # Convert string keys to atom keys for nested structures
        # The merge_project function expects maps with atom keys for
        # workflows, jobs, triggers, edges
        atomize_keys(data)

      {:error, error} ->
        Mix.raise("Failed to parse #{label} file as JSON: #{inspect(error)}")
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      atom_key = convert_to_atom(key)
      {atom_key, atomize_keys(value)}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value

  defp convert_to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp convert_to_atom(key), do: key
end

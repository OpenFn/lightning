defmodule Mix.Tasks.Lightning.MergeProjects do
  @moduledoc """
  Merges two project state files (JSON) and outputs the result.

  This task is useful for merging sandbox projects.
  It takes two state files (source and target) and produces a merged
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
        invalid_opts = Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)

        Mix.raise("""
        Unknown option(s): #{invalid_opts}

        Valid options:
          -o, --output PATH    Write output to file instead of stdout

        Run `mix help lightning.merge_projects` for more information.
        """)

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
    output_path = Keyword.get(opts, :output)

    if output_path do
      validate_output_path(output_path)
      Mix.shell().info("Merging #{source_file} into #{target_file}...")
    end

    source_project = read_state_file(source_file, "source")

    target_project = read_state_file(target_file, "target")

    merged_project = perform_merge(source_project, target_project)

    output = encode_json(merged_project)
    write_output(output, output_path)
  end

  defp perform_merge(source_data, target_data) do
    source_project = atomize_keys(source_data)
    target_project = atomize_keys(target_data)

    MergeProjects.merge_project(source_project, target_project)
  rescue
    ArgumentError ->
      Mix.raise("""
      Failed to merge projects - encountered unknown field in JSON

      This may indicate the JSON contains invalid or unexpected fields.
      Please ensure both files are valid Lightning project exports.
      """)
  end

  defp atomize_keys(data) when is_map(data) do
    Map.new(data, fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_existing_atom(key), else: key
      {atom_key, atomize_keys(value)}
    end)
  end

  defp atomize_keys(data) when is_list(data) do
    Enum.map(data, &atomize_keys/1)
  end

  defp atomize_keys(data), do: data

  defp encode_json(project) do
    Jason.encode!(project, pretty: true)
  rescue
    e in Protocol.UndefinedError ->
      Mix.raise("""
      Failed to encode merged project as JSON

      #{Exception.message(e)}

      This is unexpected and may indicate a bug.
      Please report this issue with your input files (if possible).
      """)

    e ->
      Mix.raise("""
      Failed to encode merged project as JSON

      #{Exception.message(e)}
      """)
  end

  defp write_output(output, nil), do: IO.puts(output)

  defp write_output(output, output_path) do
    case File.write(output_path, output) do
      :ok ->
        Mix.shell().info("Merged project written to #{output_path}")

      {:error, :eacces} ->
        Mix.raise("""
        Permission denied writing to: #{output_path}

        Please check:
          - You have write permissions for this location
          - The file is not locked by another process
        """)

      {:error, :enospc} ->
        Mix.raise("""
        Not enough disk space to write: #{output_path}

        Please free up disk space and try again.
        """)

      {:error, :enoent} ->
        parent_dir = Path.dirname(output_path)

        Mix.raise("""
        Output directory does not exist: #{parent_dir}

        Create the directory first:
          mkdir -p #{parent_dir}
        """)

      {:error, reason} ->
        Mix.raise("""
        Failed to write merged project to: #{output_path}

        Error: #{:file.format_error(reason)}
        """)
    end
  end

  defp validate_output_path(path) do
    parent_dir = Path.dirname(path)

    unless File.dir?(parent_dir) do
      Mix.raise("""
      Output directory does not exist: #{parent_dir}

      Create the directory first:
        mkdir -p #{parent_dir}
      """)
    end

    case File.stat(parent_dir) do
      {:ok, %File.Stat{access: access}} when access in [:read_write, :write] ->
        :ok

      {:ok, %File.Stat{}} ->
        Mix.raise("""
        No write permission for directory: #{parent_dir}

        Please check directory permissions:
          chmod +w #{parent_dir}
        """)

      {:error, reason} ->
        Mix.raise("""
        Cannot access output directory: #{parent_dir}

        Error: #{:file.format_error(reason)}
        """)
    end
  end

  defp read_state_file(path, label) do
    unless File.exists?(path) do
      Mix.raise("#{String.capitalize(label)} file not found: #{path}")
    end

    content =
      case File.read(path) do
        {:ok, content} ->
          content

        {:error, :eacces} ->
          Mix.raise("""
          Permission denied reading #{label} file: #{path}

          Please check file permissions:
            chmod +r #{path}
          """)

        {:error, reason} ->
          Mix.raise("""
          Failed to read #{label} file: #{path}

          Error: #{:file.format_error(reason)}
          """)
      end

    case Jason.decode(content, keys: :atoms) do
      {:ok, data} ->
        # Jason's keys: :atoms option converts all string keys to atoms
        # This is safe for controlled JSON file input (not arbitrary user input)
        # The merge_project function requires atom keys for dot notation access
        data

      {:error, %Jason.DecodeError{} = error} ->
        Mix.raise("""
        Failed to parse #{label} file as JSON: #{path}

        #{Exception.message(error)}
        """)
    end
  end
end

defmodule Mix.Tasks.Lightning.GenWorkflowHash do
  @shortdoc "Generate the version hash for a workflow"

  @moduledoc """
  Generates a deterministic version hash for an existing workflow.

  ## Usage

      mix lightning.gen_workflow_hash WORKFLOW_UUID [--no-hash]

  ## Arguments

    * `WORKFLOW_UUID` - The UUID of the workflow to hash

  ## Options

    * `--no-hash` - Print the joined pre-hash string instead of the hash.
      Useful for debugging what's fed into the hash.

  ## Examples

      mix lightning.gen_workflow_hash 550e8400-e29b-41d4-a716-446655440000
      mix lightning.gen_workflow_hash 550e8400-e29b-41d4-a716-446655440000 --no-hash
  """
  use Mix.Task

  alias Lightning.Workflows
  alias Lightning.WorkflowVersions

  require Logger

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args, strict: [hash: :boolean])

    cond do
      length(invalid) > 0 ->
        invalid_opts = Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)
        Mix.raise("Unknown option(s): #{invalid_opts}")

      length(positional) != 1 ->
        Mix.raise("""
        Expected exactly 1 argument: WORKFLOW_UUID

        Usage:
          mix lightning.gen_workflow_hash WORKFLOW_UUID [--no-hash]
        """)

      true ->
        [workflow_id] = positional
        quietly(fn -> print_hash_from_repo(workflow_id, opts) end)
    end
  end

  defp print_hash_from_repo(workflow_id, opts) do
    start_repo()
    print_hash(workflow_id, opts)
  end

  # The logger level is one setting for the whole VM, and this task also runs
  # inside the test suite, where leaving it raised silences every later
  # assertion on a log line.
  defp quietly(fun) do
    previous_level = Logger.level()
    Logger.configure(level: :error)

    try do
      fun.()
    after
      Logger.configure(level: previous_level)
    end
  end

  defp start_repo do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    case Lightning.Repo.start_link(pool_size: 1) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp print_hash(workflow_id, opts) do
    case Workflows.get_workflow(workflow_id) do
      nil ->
        Mix.raise("Workflow #{workflow_id} not found")

      workflow ->
        if Keyword.get(opts, :hash, true) do
          WorkflowVersions.generate_hash(workflow)
        else
          WorkflowVersions.canonical_form(workflow)
        end
        |> IO.puts()
    end
  end
end

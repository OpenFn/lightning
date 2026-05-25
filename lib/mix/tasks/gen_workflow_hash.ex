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

  require Logger

  alias Lightning.Workflows
  alias Lightning.WorkflowVersions

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
        start_repo()
        print_hash(workflow_id, opts)
    end
  end

  defp start_repo do
    Logger.configure(level: :error)
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Lightning.Repo.start_link(pool_size: 1)
  end

  defp print_hash(workflow_id, opts) do
    case Workflows.get_workflow(workflow_id) do
      nil ->
        Mix.raise("Workflow #{workflow_id} not found")

      workflow ->
        workflow
        |> WorkflowVersions.generate_hash(opts)
        |> IO.puts()
    end
  end
end

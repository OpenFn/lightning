defmodule Mix.Tasks.Lightning.GenWorkflowHash do
  @shortdoc "Generate the version hash for a workflow"

  @moduledoc """
  Generates a deterministic version hash for an existing workflow.

  ## Usage

      mix lightning.gen_workflow_hash WORKFLOW_UUID

  ## Arguments

    * `WORKFLOW_UUID` - The UUID of the workflow to hash

  ## Examples

      mix lightning.gen_workflow_hash 550e8400-e29b-41d4-a716-446655440000
  """
  use Mix.Task

  require Logger

  alias Lightning.Workflows
  alias Lightning.WorkflowVersions

  @impl Mix.Task
  def run(args) do
    case args do
      [workflow_id] ->
        start_repo()
        print_hash(workflow_id)

      _ ->
        Mix.raise("""
        Expected exactly 1 argument: WORKFLOW_UUID

        Usage:
          mix lightning.gen_workflow_hash WORKFLOW_UUID
        """)
    end
  end

  defp start_repo do
    Logger.configure(level: :error)
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Lightning.Repo.start_link(pool_size: 1)
  end

  defp print_hash(workflow_id) do
    case Workflows.get_workflow(workflow_id) do
      nil ->
        Mix.raise("Workflow #{workflow_id} not found")

      workflow ->
        workflow
        |> WorkflowVersions.generate_hash()
        |> IO.puts()
    end
  end
end

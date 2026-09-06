defmodule Mix.Tasks.Lightning.GenWorkflowHashTest do
  use Lightning.DataCase

  import ExUnit.CaptureIO

  alias Lightning.WorkflowVersions
  alias Mix.Tasks.Lightning.GenWorkflowHash

  defp run(args) do
    capture_io(fn -> GenWorkflowHash.run(args) end) |> String.trim()
  end

  describe "run/1" do
    test "prints the 12-char hash for an existing workflow" do
      workflow = build_workflow()

      output = run([workflow.id])

      assert output == WorkflowVersions.generate_hash(workflow)
      assert String.match?(output, ~r/^[a-f0-9]{12}$/)
    end

    test "with --no-hash prints the canonical pre-hash string" do
      workflow = build_workflow()

      output = run([workflow.id, "--no-hash"])

      assert output == WorkflowVersions.canonical_form(workflow)
      # The canonical form is the un-digested input, so it is not a bare hash.
      refute String.match?(output, ~r/^[a-f0-9]{12}$/)
    end

    test "raises when the workflow does not exist" do
      id = Ecto.UUID.generate()

      assert_raise Mix.Error, "Workflow #{id} not found", fn ->
        run([id])
      end
    end
  end

  defp build_workflow do
    workflow = insert(:workflow, name: "Hashable Workflow")
    trigger = insert(:trigger, workflow: workflow, type: :webhook)
    job = insert(:job, workflow: workflow, name: "Process")

    insert(:edge,
      workflow: workflow,
      source_trigger: trigger,
      target_job: job,
      condition_type: :always
    )

    Repo.preload(workflow, [:triggers, :jobs, :edges])
  end
end

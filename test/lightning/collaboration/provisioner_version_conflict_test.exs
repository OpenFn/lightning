defmodule Lightning.Collaboration.ProvisionerVersionConflictTest do
  @moduledoc """
  Fixes version conflict bug

  Steps to reproduce:
    1. User A opens a workflow in Tab A and adds a job (unsaved).
    2. User B merges a sandbox into the workflow (provisioner import → v2 in DB).
    3. User B opens the workflow in Tab B.
    4. Tab B loads v1 instead of the latest version they just merged.

  The test is written RED-first: it asserts correct behaviour and FAILS today.
  It will pass once the bug is fixed.
  """

  # async: false — we start supervised GenServers (DocumentSupervisor, Session)
  # that are not owned by the test process.
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Mox

  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.Session
  alias Lightning.Projects.Provisioner

  setup :verify_on_exit!

  setup do
    Mox.stub(
      Lightning.Extensions.MockUsageLimiter,
      :limit_action,
      fn _action, _context -> :ok end
    )

    # set_mox_global so the mock is reachable from spawned GenServer processes
    # (e.g. Session calling LightningMock.broadcast inside save_workflow)
    Mox.set_mox_global(LightningMock)
    Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

    :ok
  end

  describe "User B opens workflow after sandbox merge" do
    test "Tab B sees the job provisioned by User B, not the stale SharedDoc state" do
      user_a = insert(:user)
      user_b = insert(:user)

      workflow =
        insert(:simple_workflow)
        |> Lightning.Repo.preload([:jobs, :triggers, :edges])

      project =
        Lightning.Repo.get!(Lightning.Projects.Project, workflow.project_id)

      [original_job] = workflow.jobs
      document_name = "workflow:#{workflow.id}"

      start_supervised!(
        {DocumentSupervisor, workflow: workflow, document_name: document_name}
      )

      # --- Tab A: User A opens the workflow and adds an unsaved job ---
      session_a =
        start_supervised!(
          {Session,
           user: user_a, workflow: workflow, document_name: document_name},
          id: :session_a
        )

      Session.update_doc(session_a, fn doc ->
        Yex.Doc.get_array(doc, "jobs")
        |> Yex.Array.push(
          Yex.MapPrelim.from(%{
            "id" => Ecto.UUID.generate(),
            "name" => "tab-a-unsaved-job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(state => state)"
          })
        )
      end)

      # --- User B merges the sandbox (provisioner import, adds a new job) ---
      v2_body = build_provisioner_body(project, workflow, add_new_job: true)
      [%{"id" => provisioner_job_id}] = new_jobs_in(v2_body, [original_job.id])

      {:ok, _} = Provisioner.import_document(project, user_b, v2_body)

      # --- Tab B: User B opens the workflow to verify what they just merged ---
      session_b =
        start_supervised!(
          {Session,
           user: user_b, workflow: workflow, document_name: document_name},
          id: :session_b
        )

      # User B should see the job they just deployed.
      # THIS FAILS TODAY — the SharedDoc is never reconciled after a provisioner
      # import, so Tab B reads the stale Y.Doc (original job + Tab A's unsaved job)
      # rather than the v2 content User B just merged.
      doc = Session.get_doc(session_b)

      job_ids =
        doc
        |> Yex.Doc.get_array("jobs")
        |> Yex.Array.to_json()
        |> Enum.map(& &1["id"])

      assert provisioner_job_id in job_ids,
             "Tab B should see the job that User B just deployed (#{provisioner_job_id}), " <>
               "but the SharedDoc was not reconciled after the sandbox merge. " <>
               "Got job ids: #{inspect(job_ids)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_provisioner_body(project, workflow, opts) do
    base_jobs =
      Enum.map(workflow.jobs, fn job ->
        %{
          "id" => job.id,
          "name" => job.name,
          "adaptor" => job.adaptor,
          "body" => job.body
        }
      end)

    extra_jobs =
      if opts[:add_new_job] do
        [
          %{
            "id" => Ecto.UUID.generate(),
            "name" => "provisioner-added-job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(state => state)"
          }
        ]
      else
        []
      end

    %{
      "id" => project.id,
      "name" => project.name,
      "workflows" => [
        %{
          "id" => workflow.id,
          "name" => workflow.name,
          "jobs" => base_jobs ++ extra_jobs,
          "triggers" =>
            Enum.map(workflow.triggers, fn t ->
              %{"id" => t.id, "enabled" => t.enabled}
            end),
          "edges" =>
            Enum.map(workflow.edges, fn e ->
              %{
                "id" => e.id,
                "source_trigger_id" => e.source_trigger_id,
                "source_job_id" => e.source_job_id,
                "target_job_id" => e.target_job_id,
                "condition_type" => to_string(e.condition_type),
                "condition_expression" => e.condition_expression,
                "condition_label" => e.condition_label
              }
              |> Map.reject(fn {_, v} -> is_nil(v) end)
            end)
        }
      ]
    }
  end

  defp new_jobs_in(body, existing_job_ids) do
    body
    |> get_in(["workflows", Access.at(0), "jobs"])
    |> Enum.reject(&(&1["id"] in existing_job_ids))
  end
end

defmodule Lightning.Collaboration.ExternalWorkflowUpdateTest do
  @moduledoc """
  Tests that the collaborative editor stays in sync when the workflow is
  updated externally (provisioner import, sandbox merge) without going through
  the Y.doc.

  Covers two failure modes:
  - Someone is online when the external update runs (SharedDoc is alive but
    never notified — currently red, fix pending)
  - Nobody is online (stale DocumentState is loaded on next open — fixed)
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

  describe "after a sandbox merge" do
    test "a new tab sees the merged version, not the stale editor state with unsaved changes" do
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
               "but the SharedDoc was not reset after the sandbox merge. " <>
               "Got job ids: #{inspect(job_ids)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Tab A saves after a provisioner import
  # ---------------------------------------------------------------------------
  #
  # After the provisioner import the SharedDoc should be reset to v2.
  # So when Tab A saves, the result should be v2 (provisioner's job present).
  # Today it fails because the SharedDoc is never reset — Tab A saves v1 +
  # unsaved changes, producing a v3 that skips v2's content entirely.

  describe "after a sandbox merge, saving from an open tab" do
    test "saves the merged version, not the unsaved changes" do
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

      # Tab A: User A opens the workflow and adds an unsaved job
      session_a =
        start_supervised!(
          {Session,
           user: user_a, workflow: workflow, document_name: document_name},
          id: :session_a
        )

      tab_a_unsaved_job_id = Ecto.UUID.generate()

      Session.update_doc(session_a, fn doc ->
        Yex.Doc.get_array(doc, "jobs")
        |> Yex.Array.push(
          Yex.MapPrelim.from(%{
            "id" => tab_a_unsaved_job_id,
            "name" => "tab-a-unsaved-job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(state => state)"
          })
        )
      end)

      # User B does a provisioner import (sandbox merge / CLI deploy)
      v2_body = build_provisioner_body(project, workflow, add_new_job: true)
      [%{"id" => provisioner_job_id}] = new_jobs_in(v2_body, [original_job.id])

      {:ok, _} = Provisioner.import_document(project, user_b, v2_body)

      # Tab A saves
      {:ok, saved_workflow} = Session.save_workflow(session_a, user_a)

      saved_job_ids = Enum.map(saved_workflow.jobs, & &1.id)

      # The SharedDoc should have been reset to the merged version (v2),
      # so the save reflects v2 — not Tab A's stale pre-merge state.
      # THIS FAILS TODAY — the SharedDoc is never reset, so Tab A saves
      # v1 + unsaved changes and the provisioner's job is absent from the result.
      assert provisioner_job_id in saved_job_ids,
             "Saved workflow should include the provisioner's job (#{provisioner_job_id}). " <>
               "Got jobs: #{saved_workflow.jobs |> Enum.map(& &1.name) |> inspect()}"

      refute tab_a_unsaved_job_id in saved_job_ids,
             "Saved workflow should not include Tab A's unsaved job — " <>
               "the SharedDoc should have been reset to the merged version before the save."
    end
  end

  # ---------------------------------------------------------------------------
  # Unsaved changes indicator base workflow not updated after sandbox merge
  # ---------------------------------------------------------------------------
  #
  # The unsaved changes indicator compares the Y.Doc's workflow.lock_version
  # against the server's latest_snapshot_lock_version to detect unsaved changes.
  # After a provisioner import (sandbox merge), the Y.Doc's lock_version should
  # be updated to the new DB version so the indicator uses v2 as its base.
  # Today it fails because the SharedDoc is never reset — lock_version in the
  # Y.Doc stays at v1, so the indicator compares against the wrong baseline.

  describe "after a sandbox merge, the unsaved changes indicator" do
    test "reflects the merged version as the new base, not the stale pre-merge version" do
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

      # Tab A: User A opens the workflow and adds an unsaved job
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

      # User B opens sandbox, adds a job at the same node, saves, and merges sandbox.
      # The provisioner import updates the DB to v2.
      v2_body = build_provisioner_body(project, workflow, add_new_job: true)
      {:ok, _} = Provisioner.import_document(project, user_b, v2_body)

      # After the merge the DB lock_version has incremented (v2).
      # The Y.Doc's workflow.lock_version is the "base" the unsaved changes
      # indicator compares against — it must be updated to v2 so Tab A knows
      # its unsaved diff is relative to the sandbox-merged state.
      #
      # THIS FAILS TODAY — the SharedDoc is never reconciled after a provisioner
      # import, so lock_version in the Y.Doc stays at v1. The indicator
      # will compare Tab A's changes against the wrong (pre-merge) baseline.
      v2_workflow =
        Lightning.Workflows.get_workflow(workflow.id,
          include: [:jobs, :edges, :triggers]
        )

      doc = Session.get_doc(session_a)
      workflow_map = Yex.Doc.get_map(doc, "workflow")
      ydoc_lock_version = Yex.Map.fetch!(workflow_map, "lock_version")

      assert ydoc_lock_version == v2_workflow.lock_version,
             "Y.Doc lock_version should reflect the merged version " <>
               "(#{v2_workflow.lock_version}) so the unsaved changes indicator " <>
               "uses v2 as its base — but got #{ydoc_lock_version}. " <>
               "Tab A's indicator will compare unsaved changes against v1 " <>
               "instead of the sandbox-merged v2."
    end
  end

  # ---------------------------------------------------------------------------
  # Nobody online during provisioner import
  # ---------------------------------------------------------------------------
  #
  # Scenario: a user had the workflow open, made unsaved changes, and closed
  # their browser. The SharedDoc shut down and flushed a stale Y.Doc to
  # DocumentState (v1 content + phantom unsaved job). Later, a provisioner
  # import writes v2 to the DB. When the next user opens the workflow, a fresh
  # SharedDoc starts and loads that stale DocumentState.
  #
  # Without a fix, Persistence.bind loads the stale content as-is — the new
  # user sees v1 + phantom job instead of the provisioner's v2.
  #
  # We insert the stale DocumentState directly (bypassing PersistenceWriter)
  # so the scenario is deterministic in tests.
  #
  # This test CURRENTLY FAILS because reconcile_or_reset has been removed.
  # It will PASS once the provisioner fix also handles the nobody-online path
  # (e.g. by invalidating stale DocumentState when writing to the DB).

  describe "when nobody is online during the provisioner import" do
    test "a new tab sees the merged version, not stale persisted editor state" do
      user_b = insert(:user)

      workflow =
        insert(:simple_workflow)
        |> Lightning.Repo.preload([:jobs, :triggers, :edges])

      project =
        Lightning.Repo.get!(Lightning.Projects.Project, workflow.project_id)

      [original_job] = workflow.jobs
      document_name = "workflow:#{workflow.id}"

      # Build stale Y.Doc state: v1 workflow + a phantom unsaved job left behind
      # by a previous user who closed their browser without saving.
      stale_doc = Yex.Doc.new()
      Session.initialize_workflow_document(stale_doc, workflow)

      Yex.Doc.get_array(stale_doc, "jobs")
      |> Yex.Array.push(
        Yex.MapPrelim.from(%{
          "id" => Ecto.UUID.generate(),
          "name" => "previous-user-unsaved-job",
          "adaptor" => "@openfn/language-common@latest",
          "body" => "fn(state => state)"
        })
      )

      stale_update = Yex.encode_state_as_update!(stale_doc)

      Lightning.Repo.insert!(%Lightning.Collaboration.DocumentState{
        document_name: document_name,
        version: :update,
        state_data: stale_update
      })

      # Provisioner runs while nobody is online (no active SharedDoc)
      v2_body = build_provisioner_body(project, workflow, add_new_job: true)
      [%{"id" => provisioner_job_id}] = new_jobs_in(v2_body, [original_job.id])
      {:ok, _} = Provisioner.import_document(project, user_b, v2_body)

      # New user opens the workflow — Persistence.bind finds the stale
      # DocumentState and loads it. Without a fix, the stale content is used
      # as-is and the new user sees v1 + phantom job, not the provisioner's v2.
      v2_workflow =
        Lightning.Workflows.get_workflow(workflow.id,
          include: [:jobs, :edges, :triggers]
        )

      start_supervised!(
        {DocumentSupervisor, workflow: v2_workflow, document_name: document_name}
      )

      session_b =
        start_supervised!(
          {Session,
           user: user_b, workflow: v2_workflow, document_name: document_name},
          id: :session_b
        )

      doc = Session.get_doc(session_b)

      job_ids =
        doc
        |> Yex.Doc.get_array("jobs")
        |> Yex.Array.to_json()
        |> Enum.map(& &1["id"])

      assert provisioner_job_id in job_ids,
             "User B should see the provisioner's job (#{provisioner_job_id}) " <>
               "when opening the workflow after the merge. " <>
               "The stale persisted Y.Doc should not be loaded as-is. " <>
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

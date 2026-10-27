defmodule LightningWeb.SandboxLive.MergeSelectionTest do
  use LightningWeb.ConnCase, async: true
  use Mimic
  use LightningWeb.SandboxPageHelpers

  import Ecto.Query
  import Lightning.Factories
  import Phoenix.LiveViewTest

  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.Sandboxes
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkflowVersions

  # The merge dialog is drawn by the design system from what these two events
  # reply (ticked-by-default and select-all belong to the page and are tested
  # in the design system's own SandboxesIndexPage.test.tsx, in @openfn/ui).
  defp open(conn, project), do: live(conn, ~p"/projects/#{project.id}/sandboxes")

  defp wf(reply, name), do: Enum.find(reply.workflows, &(&1.name == name))

  defp version(workflow, hash),
    do: {:ok, _} = WorkflowVersions.record_version(workflow, hash, "app")

  defp live_workflow_count, do: Repo.aggregate(Workflow, :count)

  defp deleted?(workflow), do: !!Repo.reload(workflow).deleted_at

  defp attached?(project, credential) do
    Repo.exists?(
      from(pc in ProjectCredential,
        where:
          pc.project_id == ^project.id and pc.credential_id == ^credential.id
      )
    )
  end

  describe "authorization" do
    setup :register_and_log_in_user

    setup %{user: owner} do
      viewer = insert(:user)

      parent =
        insert(:project,
          name: "parent",
          project_users: [
            %{user: owner, role: :owner},
            %{user: viewer, role: :viewer}
          ]
        )

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [
            %{user: owner, role: :owner},
            %{user: viewer, role: :viewer}
          ]
        )

      %{owner: owner, viewer: viewer, parent: parent, sandbox: sandbox}
    end

    test "a viewer, and an editor, cannot preview or merge, and nothing changes",
         %{conn: conn, viewer: viewer, parent: parent, sandbox: sandbox} do
      parent_wf = insert(:workflow, project: parent, name: "Alpha")
      insert(:workflow, project: sandbox, name: "Alpha")
      before_count = live_workflow_count()

      editor = insert(:user)
      insert(:project_user, user: editor, project: parent, role: :editor)
      insert(:project_user, user: editor, project: sandbox, role: :editor)

      for user <- [viewer, editor] do
        {:ok, view, _html} = open(log_in_user(conn, user), parent)

        Mimic.reject(&Sandboxes.merge/4)
        allow_mocks(view)

        assert %{
                 "canMerge" => false,
                 "canEdit" => false
               } = row(view, sandbox)

        assert %{error: "You are not authorized to merge this sandbox"} =
                 preview(view, sandbox, parent.id)

        merge(view, sandbox, parent.id, %{
          "workflowIds" => [parent_wf.id],
          "deletedWorkflowIds" => [parent_wf.id]
        })

        assert_reply(view, %{
          error: "You are not authorized to merge this sandbox"
        })
      end

      assert live_workflow_count() == before_count
      refute deleted?(parent_wf)
      assert is_nil(Repo.reload(sandbox).scheduled_deletion)
    end

    test "a user who is only a viewer on the target is refused, and the target is unchanged",
         %{conn: conn, parent: parent, sandbox: sandbox} do
      actor = insert(:user)
      insert(:project_user, user: actor, project: parent, role: :editor)
      insert(:project_user, user: actor, project: sandbox, role: :admin)

      restricted =
        insert(:project,
          name: "restricted-target",
          parent: parent,
          project_users: [%{user: actor, role: :viewer}]
        )

      restricted_wf = insert(:workflow, project: restricted, name: "Keep")
      insert(:workflow, project: sandbox, name: "Keep")
      before_count = live_workflow_count()

      {:ok, view, _html} = open(log_in_user(conn, actor), parent)

      assert %{targets: targets} = preview(view, sandbox, parent.id)
      refute restricted.id in Enum.map(targets, & &1.id)

      assert %{error: "Target project not found"} =
               preview(view, sandbox, restricted.id)

      Mimic.reject(&Sandboxes.merge/4)
      allow_mocks(view)

      merge(view, sandbox, restricted.id, %{"workflowIds" => []})

      assert_reply(view, %{
        error: "You are not authorized to merge into this project"
      })

      assert live_workflow_count() == before_count
      refute deleted?(restricted_wf)
    end

    test "a user who may not merge into the parent gets no default target",
         %{conn: conn, parent: parent, sandbox: sandbox} do
      actor = insert(:user)
      insert(:project_user, user: actor, project: parent, role: :viewer)
      insert(:project_user, user: actor, project: sandbox, role: :admin)
      insert(:workflow, project: sandbox, name: "Alpha")

      {:ok, view, _html} = open(log_in_user(conn, actor), parent)

      reply = preview(view, sandbox)

      refute parent.id in Enum.map(reply.targets, & &1.id)
      assert reply.targetId == nil

      assert [%{name: "Alpha", isNew: true, isDiverged: false, isDeleted: false}] =
               reply.workflows

      assert reply.credentials == []
      assert reply.collectionsToAdd == []
    end

    test "targets are live projects outside the sandbox where the viewer is editor or above",
         %{conn: conn, user: user, parent: parent, sandbox: sandbox} do
      actor = insert(:user)
      insert(:project_user, user: actor, project: parent, role: :editor)
      insert(:project_user, user: actor, project: sandbox, role: :admin)

      viewer_only =
        insert(:project,
          parent: parent,
          project_users: [%{user: actor, role: :viewer}]
        )

      no_membership = insert(:project, parent: parent, project_users: [])

      {:ok, view, _html} = open(log_in_user(conn, actor), parent)
      reply = preview(view, sandbox)
      ids = Enum.map(reply.targets, & &1.id)

      assert parent.id in ids
      assert reply.targetId == parent.id
      refute viewer_only.id in ids
      refute no_membership.id in ids
      refute sandbox.id in ids

      # An owner also sees live siblings, but not retiring ones, nor the
      # sandbox's own descendants, and may not merge into any of those.
      sibling =
        insert(:project,
          name: "sibling-active",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      retiring =
        insert(:project,
          name: "sibling-scheduled",
          parent: parent,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second),
          project_users: [%{user: user, role: :owner}]
        )

      child =
        insert(:project,
          name: "child-of-sandbox",
          parent: sandbox,
          project_users: [%{user: user, role: :owner}]
        )

      insert(:workflow, project: sandbox, name: "Alpha")
      insert(:workflow, project: child, name: "Only In Child")
      before_count = live_workflow_count()

      {:ok, view, _html} = open(log_in_user(conn, user), parent)
      ids = view |> preview(sandbox) |> Map.fetch!(:targets) |> Enum.map(& &1.id)

      assert parent.id in ids
      assert sibling.id in ids
      refute retiring.id in ids
      refute child.id in ids
      refute sandbox.id in ids

      for refused <- [retiring, child, sandbox] do
        assert %{error: "Target project not found"} =
                 preview(view, sandbox, refused.id)

        merge(view, sandbox, refused.id)
        assert_reply(view, %{error: "Target project not found"})
      end

      assert live_workflow_count() == before_count
    end

    test "previews in a workspace deeper than two levels", %{
      conn: conn,
      user: user,
      parent: parent,
      sandbox: sandbox
    } do
      a =
        insert(:project,
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      b =
        insert(:project, parent: a, project_users: [%{user: user, role: :owner}])

      insert(:project, parent: b, project_users: [%{user: user, role: :owner}])
      insert(:workflow, project: sandbox, name: "Alpha")

      {:ok, view, _html} = open(conn, parent)

      assert %{targetId: target_id, workflows: [%{name: "Alpha"}]} =
               preview(view, sandbox)

      assert target_id == parent.id
    end

    test "a stale target workflow is overwritten when the sandbox is merged back",
         %{conn: conn, owner: owner, parent: parent} do
      parent_workflow = insert(:workflow, project: parent, name: "Main Workflow")

      job1 =
        insert(:job,
          workflow: parent_workflow,
          name: "Initial Job",
          body: "job1()"
        )

      trigger = insert(:trigger, workflow: parent_workflow, type: :webhook)

      insert(:edge,
        workflow: parent_workflow,
        source_trigger: trigger,
        target_job: job1
      )

      with_version(parent_workflow)

      sandbox =
        insert(:project,
          name: "Sandbox",
          parent: parent,
          project_users: [%{user: owner, role: :owner}]
        )

      sandbox_workflow =
        insert(:workflow,
          project: sandbox,
          name: "Main Workflow",
          lock_version: parent_workflow.lock_version
        )

      with_version(sandbox_workflow)

      sandbox_job =
        insert(:job,
          workflow: sandbox_workflow,
          name: "Initial Job",
          body: "job1_modified()"
        )

      sandbox_trigger =
        insert(:trigger, workflow: sandbox_workflow, type: :webhook)

      insert(:edge,
        workflow: sandbox_workflow,
        source_trigger: sandbox_trigger,
        target_job: sandbox_job
      )

      job2 =
        insert(:job,
          workflow: parent_workflow,
          name: "New Job Added After Sandbox",
          body: "job2()"
        )

      new_edge =
        insert(:edge,
          workflow: parent_workflow,
          source_job: job1,
          target_job: job2
        )

      parent_workflow =
        parent_workflow
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.optimistic_lock(:lock_version)
        |> Repo.update!()

      initial_lock_version = parent_workflow.lock_version

      {:ok, view, _html} = open(conn, parent)
      assert %{workflows: [%{id: id}]} = preview(view, sandbox, parent.id)

      merge(view, sandbox, parent.id, %{"workflowIds" => [id]})
      assert_redirect(view, ~p"/projects/#{parent.id}/w")

      updated = Repo.reload(parent_workflow) |> Repo.preload([:edges, :jobs])

      assert updated.lock_version > initial_lock_version
      refute new_edge.id in Enum.map(updated.edges, & &1.id)
      assert length(updated.edges) == 1
      refute job2.id in Enum.map(updated.jobs, & &1.id)

      assert Enum.find(updated.jobs, &(&1.name == "Initial Job")).body ==
               "job1_modified()"
    end
  end

  describe "preview of workflows" do
    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          project_users: [%{user: user, role: :owner}]
        )

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      %{parent: parent, sandbox: sandbox}
    end

    test "flags each workflow as diverged, new, unchanged or deleted, and hides ones added after the fork",
         %{conn: conn, parent: parent, sandbox: sandbox} do
      parent_alpha = insert(:workflow, project: parent, name: "Alpha")
      version(parent_alpha, "aaaaaa000000")
      sandbox_alpha = insert(:workflow, project: sandbox, name: "Alpha")
      version(sandbox_alpha, "bbbbbb111111")

      insert(:workflow, project: sandbox, name: "Beta")

      shared = "cccccc222222"
      version(insert(:workflow, project: parent, name: "Unchanged"), shared)
      version(insert(:workflow, project: sandbox, name: "Unchanged"), shared)

      gamma =
        insert(:workflow,
          project: parent,
          name: "Gamma",
          inserted_at: DateTime.add(sandbox.inserted_at, -3600, :second)
        )

      insert(:workflow,
        project: parent,
        name: "Added Later",
        inserted_at: DateTime.add(sandbox.inserted_at, 3600, :second)
      )

      {:ok, view, _html} = open(conn, parent)
      reply = preview(view, sandbox)

      assert reply.targetId == parent.id
      assert parent.id in Enum.map(reply.targets, & &1.id)

      assert %{isDiverged: true, isNew: false, isChanged: true, isDeleted: false} =
               wf(reply, "Alpha")

      assert wf(reply, "Alpha").id == sandbox_alpha.id

      assert %{isDiverged: false, isNew: true, isChanged: true, isDeleted: false} =
               wf(reply, "Beta")

      assert %{isDiverged: false, isNew: false, isChanged: false} =
               wf(reply, "Unchanged")

      assert %{id: gamma_id, isDeleted: true, isNew: false, isChanged: false} =
               wf(reply, "Gamma")

      assert gamma_id == gamma.id
      refute wf(reply, "Added Later")
      assert length(reply.workflows) == 4
    end

    test "matching workflows are not flagged as diverged", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox
    } do
      version(
        insert(:workflow, project: parent, name: "Matching"),
        "aabbccddee00"
      )

      version(
        insert(:workflow, project: sandbox, name: "Matching"),
        "aabbccddee00"
      )

      {:ok, view, _html} = open(conn, parent)

      assert %{isDiverged: false, isChanged: false} =
               view |> preview(sandbox) |> wf("Matching")
    end

    test "changing the target recomputes divergence and newness", %{
      conn: conn,
      user: user,
      parent: parent,
      sandbox: sandbox
    } do
      sibling =
        insert(:project,
          name: "sibling",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      version(insert(:workflow, project: parent, name: "Shared"), "aaaaaa000010")

      version(
        insert(:workflow, project: sandbox, name: "Shared"),
        "bbbbbb111120"
      )

      version(
        insert(:workflow, project: sibling, name: "Only In Sibling"),
        "cccccc222220"
      )

      version(
        insert(:workflow, project: sandbox, name: "Only In Sibling"),
        "dddddd333330"
      )

      {:ok, view, _html} = open(conn, parent)

      to_parent = preview(view, sandbox)
      assert to_parent.targetId == parent.id
      assert wf(to_parent, "Shared").isDiverged
      assert wf(to_parent, "Only In Sibling").isNew

      to_sibling = preview(view, sandbox, sibling.id)
      assert to_sibling.targetId == sibling.id
      assert wf(to_sibling, "Shared").isNew
      assert wf(to_sibling, "Only In Sibling").isDiverged
    end

    test "the preview offers sandbox-only credentials", %{
      conn: conn,
      user: user,
      parent: parent
    } do
      %{sandbox: sandbox, sandbox_pc: pc} = sandbox_with_credential(parent, user)
      {:ok, view, _html} = open(conn, parent)

      assert %{credentials: [%{id: id, name: "sandbox-only-cred"}]} =
               preview(view, sandbox)

      assert id == pc.id
    end
  end

  describe "merging with the ids the page sends" do
    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          project_users: [%{user: user, role: :owner}]
        )

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      parent_alpha = insert(:workflow, project: parent, name: "Alpha")
      insert(:workflow, project: sandbox, name: "Alpha")

      gamma =
        insert(:workflow,
          project: parent,
          name: "Gamma",
          inserted_at: DateTime.add(sandbox.inserted_at, -3600, :second)
        )

      added =
        insert(:workflow,
          project: parent,
          name: "Added Later",
          inserted_at: DateTime.add(sandbox.inserted_at, 3600, :second)
        )

      %{
        parent: parent,
        sandbox: sandbox,
        parent_alpha: parent_alpha,
        gamma: gamma,
        added: added
      }
    end

    test "a target-only workflow is kept unless it is sent as deleted", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox,
      parent_alpha: alpha,
      gamma: gamma,
      added: added
    } do
      {:ok, view, _html} = open(conn, parent)
      merge(view, sandbox, parent.id)
      assert_redirect(view, ~p"/projects/#{parent.id}/w")

      refute deleted?(gamma)
      refute deleted?(added)
      refute deleted?(alpha)
    end

    test "a target-only workflow sent as deleted is deleted, others stay", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox,
      parent_alpha: alpha,
      gamma: gamma,
      added: added
    } do
      {:ok, view, _html} = open(conn, parent)

      merge(view, sandbox, parent.id, %{"deletedWorkflowIds" => [gamma.id]})
      assert_redirect(view, ~p"/projects/#{parent.id}/w")

      assert deleted?(gamma)
      refute deleted?(added)
      refute deleted?(alpha)
    end

    test "ids the preview does not offer for that list are ignored", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox,
      parent_alpha: alpha,
      gamma: gamma,
      added: added
    } do
      {:ok, view, _html} = open(conn, parent)

      # Added after the fork is never offered; Gamma is offered only as a
      # deletion, and Alpha only as a workflow to carry.
      merge(view, sandbox, parent.id, %{
        "workflowIds" => [gamma.id, added.id, Ecto.UUID.generate()],
        "deletedWorkflowIds" => [added.id, alpha.id, Ecto.UUID.generate()]
      })

      assert_redirect(view, ~p"/projects/#{parent.id}/w")

      refute deleted?(gamma)
      refute deleted?(added)
      refute deleted?(alpha)
    end
  end

  describe "merging credentials" do
    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          project_users: [%{user: user, role: :owner}]
        )

      Map.put(sandbox_with_credential(parent, user), :parent, parent)
    end

    test "a credential that is not sent is not attached", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox,
      credential: credential
    } do
      {:ok, view, _html} = open(conn, parent)

      merge(view, sandbox, parent.id)
      assert_redirect(view, ~p"/projects/#{parent.id}/w")

      refute attached?(parent, credential)
    end

    test "a credential that is sent is attached", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox,
      credential: credential,
      sandbox_pc: pc
    } do
      {:ok, view, _html} = open(conn, parent)

      merge(view, sandbox, parent.id, %{"credentialIds" => [pc.id]})
      assert_redirect(view, ~p"/projects/#{parent.id}/w")

      assert attached?(parent, credential)
    end
  end

  # Provisions a real sandbox from the parent, then adds a credential that
  # lives only in the sandbox and wires the sandbox's job to it.
  defp sandbox_with_credential(parent, user) do
    wf = insert(:workflow, project: parent, name: "Alpha")
    trigger = insert(:trigger, workflow: wf, type: :webhook)

    job =
      insert(:job,
        workflow: wf,
        name: "A1",
        adaptor: "@openfn/language-common@latest",
        body: "console.log('A1');"
      )

    insert(:edge,
      workflow: wf,
      source_trigger_id: trigger.id,
      target_job_id: job.id,
      condition_type: :always,
      enabled: true
    )

    {:ok, sandbox} =
      Sandboxes.provision(parent, user, %{name: "sb"})

    credential =
      insert(:credential,
        name: "sandbox-only-cred",
        body: %{"token" => "x"},
        user: user
      )

    sandbox_pc =
      insert(:project_credential, project: sandbox, credential: credential)

    from(j in Lightning.Workflows.Job,
      join: w in assoc(j, :workflow),
      where: w.project_id == ^sandbox.id and j.name == "A1"
    )
    |> Repo.one!()
    |> Ecto.Changeset.change(project_credential_id: sandbox_pc.id)
    |> Repo.update!()

    %{sandbox: sandbox, credential: credential, sandbox_pc: sandbox_pc}
  end
end

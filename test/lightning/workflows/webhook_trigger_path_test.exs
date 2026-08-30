defmodule Lightning.Workflows.WebhookTriggerPathTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Plug.Test
  import Lightning.Factories

  alias Lightning.Workflows
  alias Lightning.Workflows.Trigger
  alias LightningWeb.Plugs.WebhookAuth

  @moduletag capture_log: true

  defp webhook_trigger(attrs \\ []) do
    project = Keyword.get_lazy(attrs, :project, fn -> insert(:project) end)
    workflow = insert(:workflow, project: project)

    trigger =
      insert(
        :trigger,
        Keyword.merge(
          [workflow: workflow, type: :webhook, enabled: true],
          Keyword.delete(attrs, :project)
        )
      )

    {project, trigger}
  end

  # Only the migration sets this, so tests standing in for pre-existing data
  # write it directly.
  defp grandfather(trigger) do
    {1, _} =
      Lightning.Repo.update_all(
        from(t in Trigger, where: t.id == ^trigger.id),
        set: [legacy_bare_path: true]
      )

    trigger
  end

  describe "get_webhook_trigger/2" do
    test "resolves a trigger by its generated id" do
      {_project, trigger} = webhook_trigger()

      assert Workflows.get_webhook_trigger([trigger.id]).id == trigger.id
    end

    test "resolves a custom path within its project" do
      {project, trigger} = webhook_trigger(custom_path: "facility-001")

      assert Workflows.get_webhook_trigger([project.id, "facility-001"]).id ==
               trigger.id
    end

    test "keeps the generated id URL working once a custom path is set" do
      {project, trigger} = webhook_trigger(custom_path: "facility-001")

      assert Workflows.get_webhook_trigger([trigger.id]).id == trigger.id

      assert Workflows.get_webhook_trigger([project.id, "facility-001"]).id ==
               trigger.id
    end

    test "the same custom path in two projects does not collide" do
      {project_a, trigger_a} = webhook_trigger(custom_path: "facility-001")
      {project_b, trigger_b} = webhook_trigger(custom_path: "facility-001")

      refute trigger_a.id == trigger_b.id

      assert Workflows.get_webhook_trigger([project_a.id, "facility-001"]).id ==
               trigger_a.id

      assert Workflows.get_webhook_trigger([project_b.id, "facility-001"]).id ==
               trigger_b.id
    end

    test "a custom path cannot shadow another trigger's generated id URL" do
      {_project, victim} = webhook_trigger()
      {other_project, _} = webhook_trigger()

      workflow = insert(:workflow, project: other_project)

      assert {:error, changeset} =
               %Trigger{}
               |> Trigger.changeset(%{
                 workflow_id: workflow.id,
                 type: :webhook,
                 custom_path: victim.id
               })
               |> Lightning.Repo.insert()

      assert "cannot be a UUID" in errors_on(changeset).custom_path
      assert Workflows.get_webhook_trigger([victim.id]).id == victim.id
    end

    test "ignores cron triggers" do
      workflow = insert(:workflow, project: insert(:project))
      trigger = insert(:trigger, workflow: workflow, type: :cron)

      assert Workflows.get_webhook_trigger([trigger.id]) == nil
    end

    test "a 16-character path is a name, not a raw UUID" do
      # Ecto.UUID.cast/1 accepts any 16-byte binary, so this used to be read as
      # a trigger id and rejected on write.
      {project, trigger} = webhook_trigger(custom_path: "orders_intake_v1")

      assert trigger.custom_path == "orders_intake_v1"

      assert Workflows.get_webhook_trigger([project.id, "orders_intake_v1"]).id ==
               trigger.id
    end

    test "ignores trailing segments for both URL forms" do
      {project, trigger} = webhook_trigger(custom_path: "facility-001")

      assert Workflows.get_webhook_trigger([trigger.id, "Patient"]).id ==
               trigger.id

      assert Workflows.get_webhook_trigger([
               project.id,
               "facility-001",
               "Patient"
             ]).id == trigger.id
    end

    test "answers a bare path only for a trigger that already held that URL" do
      {_project, trigger} = webhook_trigger(custom_path: "facility-001")

      assert Workflows.get_webhook_trigger(["facility-001"]) == nil

      grandfather(trigger)

      assert Workflows.get_webhook_trigger(["facility-001"]).id == trigger.id
    end

    test "renaming a grandfathered path gives up the bare URL" do
      {project, trigger} = webhook_trigger(custom_path: "orders")
      grandfather(trigger)

      assert Workflows.get_webhook_trigger(["orders"]).id == trigger.id

      {:ok, renamed} =
        trigger
        |> Trigger.changeset(%{custom_path: "invoices"})
        |> Lightning.Repo.update()

      refute renamed.legacy_bare_path
      assert Workflows.get_webhook_trigger(["invoices"]) == nil

      assert Workflows.get_webhook_trigger([project.id, "invoices"]).id ==
               trigger.id
    end

    test "resubmitting the same path keeps the bare URL" do
      # Trimming can leave a change registered whose value equals the row's.
      # Treating that as a rename would retire a URL that never moved.
      {_project, trigger} = webhook_trigger(custom_path: "orders")
      grandfather(trigger)

      assert {:ok, saved} =
               Lightning.Repo.get!(Trigger, trigger.id)
               |> Trigger.changeset(%{custom_path: "  orders  "})
               |> Lightning.Repo.update()

      assert saved.custom_path == "orders"
      assert saved.legacy_bare_path
      assert Workflows.get_webhook_trigger(["orders"]).id == trigger.id
    end

    test "a rename onto another project's bare URL does not take it" do
      {_incumbent_project, incumbent} = webhook_trigger(custom_path: "orders")
      grandfather(incumbent)

      {other_project, other} = webhook_trigger(custom_path: "invoices")
      grandfather(other)

      # Allowed: two projects may both name a path `orders`. Renaming just
      # gives up the bare URL that came with the old name.
      assert {:ok, renamed} =
               other
               |> Trigger.changeset(%{custom_path: "orders"})
               |> Lightning.Repo.update()

      refute renamed.legacy_bare_path
      assert Workflows.get_webhook_trigger(["orders"]).id == incumbent.id

      assert Workflows.get_webhook_trigger([other_project.id, "orders"]).id ==
               other.id
    end

    test "a grandfathered path that looks like a UUID still resolves" do
      {_project, trigger} = webhook_trigger()
      uuid_path = Ecto.UUID.generate()

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^trigger.id),
          set: [custom_path: uuid_path, legacy_bare_path: true]
        )

      assert Workflows.get_webhook_trigger([uuid_path]).id == trigger.id
    end

    test "a cron trigger's stale path never answers a webhook URL" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      cron = insert(:trigger, workflow: workflow, type: :cron)

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^cron.id),
          set: [custom_path: "orders", legacy_bare_path: true]
        )

      assert Workflows.get_webhook_trigger(["orders"]) == nil
      assert Workflows.get_webhook_trigger([project.id, "orders"]) == nil
    end

    test "a newer project cannot take an existing bare URL" do
      {_incumbent_project, incumbent} =
        webhook_trigger(custom_path: "facility-001")

      grandfather(incumbent)

      {squatter_project, squatter} = webhook_trigger(custom_path: "facility-001")

      assert Workflows.get_webhook_trigger(["facility-001"]).id == incumbent.id

      assert Workflows.get_webhook_trigger([squatter_project.id, "facility-001"]).id ==
               squatter.id
    end

    test "returns nil for unknown, malformed and over-long paths" do
      assert Workflows.get_webhook_trigger(["nothing-here"]) == nil
      assert Workflows.get_webhook_trigger([Ecto.UUID.generate()]) == nil
      assert Workflows.get_webhook_trigger(["not-a-uuid", "facility-001"]) == nil
      assert Workflows.get_webhook_trigger([]) == nil
      assert Workflows.get_webhook_trigger(["a", "b", "c"]) == nil
    end
  end

  describe "the /i/ plug" do
    test "resolves the generated URL" do
      {_project, trigger} = webhook_trigger()

      conn = conn(:post, "/i/#{trigger.id}", %{"a" => 1}) |> WebhookAuth.call([])

      refute conn.halted
      assert conn.assigns[:trigger].id == trigger.id
    end

    test "resolves a project-namespaced custom path" do
      {project, trigger} = webhook_trigger(custom_path: "facility-001")

      conn =
        conn(:post, "/i/#{project.id}/facility-001", %{"a" => 1})
        |> WebhookAuth.call([])

      refute conn.halted
      assert conn.assigns[:trigger].id == trigger.id
    end

    test "resolves a grandfathered bare custom path" do
      {_project, trigger} = webhook_trigger(custom_path: "facility-001")
      grandfather(trigger)

      conn = conn(:post, "/i/facility-001", %{}) |> WebhookAuth.call([])

      refute conn.halted
      assert conn.assigns[:trigger].id == trigger.id
    end

    test "matches a legacy path against the raw URL segment" do
      # `conn.path_info` is not percent-decoded, so a stored path containing a
      # percent sequence is reached by sending it verbatim.
      {project, trigger} = webhook_trigger()

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^trigger.id),
          set: [custom_path: "a%20b"]
        )

      conn =
        conn(:post, "/i/#{project.id}/a%20b", %{}) |> WebhookAuth.call([])

      refute conn.halted
      assert conn.assigns[:trigger].id == trigger.id
    end

    test "404s a bare custom path that was never a bare URL" do
      {_project, _trigger} = webhook_trigger(custom_path: "facility-001")

      conn = conn(:post, "/i/facility-001", %{}) |> WebhookAuth.call([])

      assert conn.status == 404
    end
  end

  describe "valid_custom_path?/1" do
    test "accepts what the changeset accepts" do
      assert Trigger.valid_custom_path?("facility-001")
      assert Trigger.valid_custom_path?("orders_intake_v1")
    end

    test "rejects a trailing newline" do
      # `$` also matches before a final newline in PCRE, so this would have been
      # called usable and then silently trimmed on the way through.
      refute Trigger.valid_custom_path?("orders\n")
    end

    test "rejects what the changeset rejects" do
      refute Trigger.valid_custom_path?("orders.v1")
      refute Trigger.valid_custom_path?("Orders")
      refute Trigger.valid_custom_path?(Ecto.UUID.generate())
      refute Trigger.valid_custom_path?(String.duplicate("a", 256))
      refute Trigger.valid_custom_path?(nil)
    end
  end

  describe "custom_path" do
    test "is unique within a project" do
      {project, _first} = webhook_trigger(custom_path: "facility-001")
      workflow = insert(:workflow, project: project)

      assert {:error, changeset} =
               %Trigger{}
               |> Trigger.changeset(%{
                 workflow_id: workflow.id,
                 type: :webhook,
                 custom_path: "facility-001"
               })
               |> Lightning.Repo.insert()

      assert "is already used by another workflow in this project" in errors_on(
               changeset
             ).custom_path
    end

    test "accepts lowercase letters, numbers, hyphens and underscores" do
      {_project, trigger} = webhook_trigger(custom_path: "et-emr_facility-001")

      assert trigger.custom_path == "et-emr_facility-001"
    end

    test "rejects characters that would not survive a URL segment" do
      for path <- ["Orders Intake", "orders/intake", "orders?a=1", "ORDERS"] do
        changeset =
          Trigger.changeset(%Trigger{}, %{type: :webhook, custom_path: path})

        assert %{custom_path: [_ | _]} = errors_on(changeset),
               "expected #{inspect(path)} to be rejected"
      end
    end

    test "rejects a path longer than 255 characters" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          custom_path: String.duplicate("a", 256)
        })

      assert %{custom_path: [_ | _]} = errors_on(changeset)
    end

    test "a rejected path reports against the field the form renders" do
      workflow = insert(:workflow, project: insert(:project))

      assert {:error, changeset} =
               %Trigger{}
               |> Trigger.changeset(%{
                 workflow_id: workflow.id,
                 type: :webhook,
                 custom_path: "Orders Intake"
               })
               |> Lightning.Repo.insert()

      assert Map.has_key?(errors_on(changeset), :custom_path)
      refute Map.has_key?(errors_on(changeset), :project_id)
    end

    test "build_trigger/1 reports a duplicate rather than raising" do
      {project, _first} = webhook_trigger(custom_path: "facility-001")
      workflow = insert(:workflow, project: project)

      assert {:error, changeset} =
               Workflows.build_trigger(%{
                 type: :webhook,
                 workflow_id: workflow.id,
                 custom_path: "facility-001"
               })

      assert Map.has_key?(errors_on(changeset), :custom_path)
    end

    test "build_trigger/1 validates the path like the changeset does" do
      workflow = insert(:workflow, project: insert(:project))

      assert {:error, changeset} =
               Workflows.build_trigger(%{
                 type: :webhook,
                 workflow_id: workflow.id,
                 custom_path: "Orders Intake"
               })

      assert Map.has_key?(errors_on(changeset), :custom_path)
    end

    test "treats a blank path as no path" do
      changeset =
        Trigger.changeset(%Trigger{}, %{type: :webhook, custom_path: "   "})

      assert Ecto.Changeset.get_field(changeset, :custom_path) == nil
    end
  end

  describe "a sandbox of a project with a custom path" do
    test "keeps the path and gets its own URL" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      insert(:project_user, project: parent, user: actor, role: :owner)

      workflow = insert(:workflow, project: parent)

      parent_trigger =
        insert(:trigger,
          workflow: workflow,
          type: :webhook,
          enabled: true,
          custom_path: "facility-001"
        )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, actor, %{
                 name: "sb"
               })

      assert Workflows.get_webhook_trigger([parent.id, "facility-001"]).id ==
               parent_trigger.id

      sandbox_trigger =
        Workflows.get_webhook_trigger([sandbox.id, "facility-001"])

      assert sandbox_trigger
      refute sandbox_trigger.id == parent_trigger.id
    end
  end

  describe "a legacy path the new rules reject" do
    test "does not stop a sandbox being provisioned" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      insert(:project_user, project: parent, user: actor, role: :owner)

      workflow = insert(:workflow, project: parent)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      # Paths written before the naming rules existed were never validated, so
      # write one the way the old code could.
      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^trigger.id),
          set: [custom_path: "some/legacy/path"]
        )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, actor, %{
                 name: "sb"
               })

      # The clone carries the parent's path verbatim, so promoting it back is a
      # no-op rather than an instruction to clear the parent's path.
      assert Lightning.Repo.get!(Trigger, trigger.id).custom_path ==
               "some/legacy/path"

      [clone] =
        Lightning.Repo.all(
          from(t in Trigger, where: t.project_id == ^sandbox.id)
        )

      assert clone.custom_path == "some/legacy/path"
    end

    test "survives a round trip through a sandbox" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      insert(:project_user, project: parent, user: actor, role: :owner)

      workflow = insert(:workflow, project: parent, name: "Alpha")
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always
      )

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^trigger.id),
          set: [custom_path: "orders.v1", legacy_bare_path: true]
        )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, actor, %{
                 name: "sb"
               })

      assert {:ok, _} =
               Lightning.Projects.Sandboxes.merge(sandbox, parent, actor)

      after_promote = Lightning.Repo.get!(Trigger, trigger.id)

      assert after_promote.custom_path == "orders.v1"
      assert after_promote.legacy_bare_path
      assert Workflows.get_webhook_trigger(["orders.v1"]).id == trigger.id
    end
  end

  describe "merging a sandbox that carries a legacy path" do
    test "does not fail the merge" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      insert(:project_user, project: parent, user: actor, role: :owner)
      workflow = insert(:workflow, project: parent, name: "Alpha")
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always
      )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, actor, %{
                 name: "sb"
               })

      [sandbox_workflow] =
        Lightning.Repo.all(
          from(w in Lightning.Workflows.Workflow,
            where: w.project_id == ^sandbox.id
          )
        )

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.workflow_id == ^sandbox_workflow.id),
          set: [custom_path: "v1/orders"]
        )

      assert {:ok, _merged} =
               Lightning.Projects.Sandboxes.merge(sandbox, parent, actor)

      # The parent's trigger is left on its generated URL rather than the
      # merge failing outright.
      assert Lightning.Repo.get!(Trigger, trigger.id).custom_path == nil
    end
  end

  describe "a legacy path on a workflow nobody merged" do
    test "survives a merge of a different workflow" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      insert(:project_user, project: parent, user: actor, role: :owner)

      merged = insert(:workflow, project: parent, name: "Merged")
      merged_job = insert(:job, workflow: merged)
      merged_trigger = insert(:trigger, workflow: merged, type: :webhook)

      insert(:edge,
        workflow: merged,
        source_trigger: merged_trigger,
        target_job: merged_job,
        condition_type: :always
      )

      bystander = insert(:workflow, project: parent, name: "Bystander")
      bystander_job = insert(:job, workflow: bystander)
      bystander_trigger = insert(:trigger, workflow: bystander, type: :webhook)

      insert(:edge,
        workflow: bystander,
        source_trigger: bystander_trigger,
        target_job: bystander_job,
        condition_type: :always
      )

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^bystander_trigger.id),
          set: [custom_path: "orders.v1", legacy_bare_path: true]
        )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, actor, %{
                 name: "sb"
               })

      [sandbox_merged] =
        Lightning.Repo.all(
          from(w in Lightning.Workflows.Workflow,
            where: w.project_id == ^sandbox.id and w.name == "Merged"
          )
        )

      assert {:ok, _} =
               Lightning.Projects.Sandboxes.merge(sandbox, parent, actor, %{
                 selected_workflow_ids: [sandbox_merged.id]
               })

      untouched = Lightning.Repo.get!(Trigger, bystander_trigger.id)

      assert untouched.custom_path == "orders.v1"
      assert untouched.legacy_bare_path

      assert Workflows.get_webhook_trigger(["orders.v1"]).id ==
               bystander_trigger.id
    end
  end

  describe "a merge that would collide on a path" do
    test "fails rather than corrupting either side" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      insert(:project_user, project: parent, user: actor, role: :owner)

      incumbent = insert(:workflow, project: parent, name: "Incumbent")
      incumbent_job = insert(:job, workflow: incumbent)

      incumbent_trigger =
        insert(:trigger,
          workflow: incumbent,
          type: :webhook,
          custom_path: "orders"
        )

      insert(:edge,
        workflow: incumbent,
        source_trigger: incumbent_trigger,
        target_job: incumbent_job,
        condition_type: :always
      )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, actor, %{
                 name: "sb"
               })

      # The sandbox's clone of the incumbent gives up the name, so a new
      # workflow in the sandbox can take it. The parent still holds it.
      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger,
            where: t.project_id == ^sandbox.id and t.custom_path == "orders"
          ),
          set: [custom_path: nil]
        )

      newcomer = insert(:workflow, project: sandbox, name: "Newcomer")
      newcomer_job = insert(:job, workflow: newcomer)

      newcomer_trigger =
        insert(:trigger, workflow: newcomer, type: :webhook)

      insert(:edge,
        workflow: newcomer,
        source_trigger: newcomer_trigger,
        target_job: newcomer_job,
        condition_type: :always
      )

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^newcomer_trigger.id),
          set: [custom_path: "orders"]
        )

      # The incoming trigger lands on a name already taken and the unique index
      # stops it. Dropping the path instead would discard the user's name.
      assert {:error, :merge_failed} =
               Lightning.Projects.Sandboxes.merge(sandbox, parent, actor, %{
                 selected_workflow_ids: [newcomer.id]
               })

      assert Lightning.Repo.get!(Trigger, incumbent_trigger.id).custom_path ==
               "orders"

      assert Workflows.get_webhook_trigger([parent.id, "orders"]).id ==
               incumbent_trigger.id
    end
  end

  describe "deleting a workflow" do
    test "frees its path for a replacement" do
      project = insert(:project)
      workflow = insert(:workflow, project: project, name: "Facility 1")
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^trigger.id),
          set: [custom_path: "facility-001", legacy_bare_path: true]
        )

      assert {:ok, _} =
               Workflows.mark_for_deletion(workflow, insert(:user))

      # A hidden row holding the name would refuse it to the replacement,
      # naming a workflow the user can no longer see.
      replacement = insert(:workflow, project: project, name: "Facility 1 v2")

      assert {:ok, taken_over} =
               %Trigger{}
               |> Trigger.changeset(%{
                 workflow_id: replacement.id,
                 type: :webhook,
                 custom_path: "facility-001"
               })
               |> Lightning.Repo.insert()

      assert Workflows.get_webhook_trigger([project.id, "facility-001"]).id ==
               taken_over.id
    end
  end

  describe "a merge that replaces a trigger on the same path" do
    test "succeeds" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      insert(:project_user, project: parent, user: actor, role: :owner)

      workflow = insert(:workflow, project: parent, name: "Alpha")
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always
      )

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^trigger.id),
          set: [custom_path: "orders"]
        )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, actor, %{
                 name: "sb"
               })

      [sandbox_workflow] =
        Lightning.Repo.all(
          from(w in Lightning.Workflows.Workflow,
            where: w.project_id == ^sandbox.id
          )
        )

      [sandbox_job] =
        Lightning.Repo.all(
          from(j in Lightning.Workflows.Job,
            where: j.workflow_id == ^sandbox_workflow.id
          )
        )

      # The incoming trigger has a new id, so the merge inserts it while the old
      # one still holds the path.
      Lightning.Repo.delete_all(
        from(e in Lightning.Workflows.Edge,
          where: e.workflow_id == ^sandbox_workflow.id
        )
      )

      Lightning.Repo.delete_all(
        from(t in Trigger, where: t.workflow_id == ^sandbox_workflow.id)
      )

      replacement =
        insert(:trigger,
          workflow: sandbox_workflow,
          type: :webhook,
          custom_path: "orders"
        )

      insert(:edge,
        workflow: sandbox_workflow,
        source_trigger: replacement,
        target_job: sandbox_job,
        condition_type: :always
      )

      assert {:ok, _} =
               Lightning.Projects.Sandboxes.merge(sandbox, parent, actor)

      assert Workflows.get_webhook_trigger([parent.id, "orders"])
    end
  end

  describe "one deploy that drops a workflow and claims its path" do
    test "succeeds" do
      # Renaming a workflow file while keeping its webhook path is this shape.
      # The release has to happen before the insert or the unique index stops
      # the whole deploy.
      user = insert(:user)
      project = insert(:project)
      insert(:project_user, project: project, user: user, role: :owner)

      old_workflow = insert(:workflow, project: project, name: "Facility 1")
      old_trigger = insert(:trigger, workflow: old_workflow, type: :webhook)

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^old_trigger.id),
          set: [custom_path: "facility-001"]
        )

      new_workflow_id = Ecto.UUID.generate()
      new_trigger_id = Ecto.UUID.generate()
      new_job_id = Ecto.UUID.generate()

      body = %{
        "id" => project.id,
        "name" => project.name,
        "workflows" => [
          %{"id" => old_workflow.id, "delete" => true},
          %{
            "id" => new_workflow_id,
            "name" => "Facility 1 renamed",
            "jobs" => [
              %{
                "id" => new_job_id,
                "name" => "step",
                "body" => "fn(s => s)",
                "adaptor" => "@openfn/language-common@latest"
              }
            ],
            "triggers" => [
              %{
                "id" => new_trigger_id,
                "type" => "webhook",
                "enabled" => true,
                "custom_path" => "facility-001"
              }
            ],
            "edges" => [
              %{
                "id" => Ecto.UUID.generate(),
                "source_trigger_id" => new_trigger_id,
                "target_job_id" => new_job_id,
                "condition_type" => "always",
                "enabled" => true
              }
            ]
          }
        ]
      }

      assert {:ok, _} =
               Lightning.Projects.Provisioner.import_document(
                 project,
                 user,
                 body
               )

      assert Workflows.get_webhook_trigger([project.id, "facility-001"]).id ==
               new_trigger_id
    end
  end

  describe "changing a trigger's type" do
    test "revalidates a path that was never checked" do
      # The migration leaves custom_path on cron rows, where it meant nothing.
      # Becoming a webhook would make it a live URL unvalidated.
      workflow = insert(:workflow, project: insert(:project))
      cron = insert(:trigger, workflow: workflow, type: :cron)

      {1, _} =
        Lightning.Repo.update_all(
          from(t in Trigger, where: t.id == ^cron.id),
          set: [custom_path: "Orders.v1"]
        )

      assert {:error, changeset} =
               Lightning.Repo.get!(Trigger, cron.id)
               |> Trigger.changeset(%{type: :webhook})
               |> Lightning.Repo.update()

      assert Map.has_key?(errors_on(changeset), :custom_path)
    end

    test "drops a meaningless path when becoming a cron trigger" do
      workflow = insert(:workflow, project: insert(:project))

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :webhook,
          custom_path: "facility-001"
        )

      assert {:ok, saved} =
               trigger
               |> Trigger.changeset(%{type: :cron, cron_expression: "0 0 * * *"})
               |> Lightning.Repo.update()

      assert saved.custom_path == nil
    end
  end

  describe "project_id" do
    test "is copied from the workflow when a workflow is saved" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      trigger_id = Ecto.UUID.generate()

      {:ok, workflow} =
        workflow
        |> Lightning.Repo.preload([:triggers, :jobs, :edges])
        |> Lightning.Workflows.Workflow.changeset(%{
          triggers: [%{id: trigger_id, type: :webhook, enabled: true}]
        })
        |> Lightning.Repo.update()

      [trigger] = Lightning.Repo.preload(workflow, :triggers).triggers

      assert trigger.project_id == project.id
    end

    test "new/1 ignores project_id and legacy_bare_path from its attrs" do
      workflow = insert(:workflow, project: insert(:project))
      other_project = insert(:project)

      assert {:ok, trigger} =
               Workflows.build_trigger(%{
                 type: :webhook,
                 workflow_id: workflow.id,
                 project_id: other_project.id,
                 legacy_bare_path: true
               })

      assert trigger.project_id == workflow.project_id
      refute trigger.legacy_bare_path
    end

    test "legacy_bare_path cannot be granted from params" do
      # Only the migration marks a bare URL. If this were settable, anyone could
      # claim an instance-wide URL for their own project.
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          custom_path: "facility-001",
          legacy_bare_path: true
        })

      # Never true. It is forced to false alongside the path it would apply to.
      refute Ecto.Changeset.get_field(changeset, :legacy_bare_path)
    end

    test "cannot be set from params" do
      other_project = insert(:project)

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          project_id: other_project.id
        })

      assert Ecto.Changeset.get_change(changeset, :project_id) == nil
    end
  end
end

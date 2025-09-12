defmodule Lightning.Projects.SandboxesTest do
  use Lightning.DataCase, async: true

  import Ecto.Query
  import Lightning.Factories
  alias Lightning.Repo

  alias Lightning.Accounts.User
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.Sandboxes
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Edge
  alias Lightning.Invocation.Dataclip

  defp ensure_member!(%Project{} = project, %User{} = user, role) do
    insert(:project_user, %{project: project, user: user, role: role})
  end

  defp attach_credential!(%Project{} = project, owner) do
    cred =
      insert(:credential,
        body: %{"token" => "secret"},
        user: owner
      )

    insert(:project_credential, %{project: project, credential: cred})
  end

  defp add_version!(%Workflow{} = w, hash) do
    insert(:workflow_version, workflow: w, hash: hash)
  end

  defp with_positions!(%Workflow{} = w, pos_map) do
    Repo.update!(Ecto.Changeset.change(w, positions: pos_map))
  end

  defp add_wam_to_trigger!(%Trigger{} = trigger, %Project{} = project) do
    wam = insert(:webhook_auth_method, project: project)

    trigger
    |> Repo.preload(:webhook_auth_methods)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [wam])
    |> Repo.update!()

    wam
  end

  # Builds a parent project with a small graph:
  # Two workflows:
  #  - Alpha: trigger -> j1 -> j2 (positions set)
  #  - Beta:  trigger -> j3       (positions set)
  # Adds credentials (referenced by jobs), versions (multiple for Alpha),
  # plus a couple of dataclips (named/eligible + forbidden).
  defp build_parent_fixture!(actor_role) do
    actor = insert(:user)
    other = insert(:user)
    parent = insert(:project, %{name: "parent", color: "#112233", env: "dev"})

    ensure_member!(parent, actor, actor_role)
    ensure_member!(parent, other, :editor)

    pc = attach_credential!(parent, actor)

    # Workflow Alpha
    w1 = insert(:workflow, %{project: parent, name: "Alpha"})
    t1 = insert(:trigger, %{workflow: w1, enabled: true, type: :webhook})

    j1 =
      insert(:job, %{
        workflow: w1,
        name: "A1",
        project_credential: pc,
        adaptor: "@openfn/language-common@latest",
        body: "console.log('A1');"
      })

    j2 =
      insert(:job, %{
        workflow: w1,
        name: "A2",
        project_credential: pc,
        adaptor: "@openfn/language-common@latest",
        body: "console.log('A2');"
      })

    insert(:edge, %{
      workflow: w1,
      source_trigger_id: t1.id,
      target_job_id: j1.id,
      condition_type: :always,
      enabled: true
    })

    insert(:edge, %{
      workflow: w1,
      source_job_id: j1.id,
      target_job_id: j2.id,
      condition_type: :on_job_success,
      enabled: true
    })

    with_positions!(w1, %{
      t1.id => %{x: 5, y: 5},
      j1.id => %{x: 105, y: 5},
      j2.id => %{x: 205, y: 5}
    })

    # Workflow Beta
    w2 = insert(:workflow, %{project: parent, name: "Beta"})
    t2 = insert(:trigger, %{workflow: w2, enabled: true, type: :webhook})

    j3 =
      insert(:job, %{
        workflow: w2,
        name: "B1",
        project_credential: pc,
        adaptor: "@openfn/language-common@latest",
        body: "console.log('B1');"
      })

    insert(:edge, %{
      workflow: w2,
      source_trigger_id: t2.id,
      target_job_id: j3.id,
      condition_type: :always,
      enabled: true
    })

    with_positions!(w2, %{
      t2.id => %{x: 10, y: 10},
      j3.id => %{x: 110, y: 10}
    })

    # Versions (Alpha has multiple; only latest should be cloned)
    add_version!(w1, "111111111111")
    add_version!(w1, "aaaaaaaaaaaa")
    add_version!(w2, "bbbbbbbbbbbb")

    # Dataclips
    dc1 =
      insert(:dataclip, %{
        project: parent,
        type: :global,
        name: "g1",
        body: %{"k" => "v"}
      })

    # unnamed → should not be copied
    insert(:dataclip, %{project: parent, type: :global, body: %{}})

    dc2 =
      insert(:dataclip, %{
        project: parent,
        type: :http_request,
        name: "req1",
        body: %{"headers" => %{}}
      })

    dc_forbidden =
      insert(:dataclip, %{
        project: parent,
        type: :step_result,
        name: "sr",
        body: %{}
      })

    # Optional: webhook auth methods on t1
    _ = add_wam_to_trigger!(t1, parent)

    %{
      actor: actor,
      other: other,
      parent: parent,
      pc: pc,
      flows: %{w1: w1, w2: w2},
      nodes: %{t1: t1, t2: t2, j1: j1, j2: j2, j3: j3},
      dataclips: %{ok1: dc1, ok2: dc2, forbidden: dc_forbidden}
    }
  end

  describe "authorization" do
    test "rejects non-admin/editor" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:editor)

      assert {:error, :unauthorized} =
               Sandboxes.provision(parent, actor, %{name: "SB"})
    end

    test "allows admin/owner" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:owner)

      assert {:ok, %Project{}} =
               Sandboxes.provision(parent, actor, %{name: "sb-ok"})
    end
  end

  describe "merge_workflow/2" do
    test "matches nodes structurally despite name and adaptor changes" do
      # Parent: webhook -> "Extract Data" (@openfn/http@1.0.0) -> "Transform" (@openfn/common@1.0.0)
      parent_workflow = insert(:workflow)

      parent_trigger =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      parent_job1 =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Extract Data",
          adaptor: "@openfn/http@1.0.0",
          body: "fetch()"
        })

      parent_job2 =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Transform",
          adaptor: "@openfn/common@1.0.0",
          body: "transform()"
        })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job1.id
      })

      insert(:edge, %{
        workflow: parent_workflow,
        source_job_id: parent_job1.id,
        target_job_id: parent_job2.id
      })

      # Sandbox: webhook -> "Fetch Data" (@openfn/http@2.0.0) -> "Process" (@openfn/common@2.0.0)
      sandbox_workflow = insert(:workflow)

      sandbox_trigger =
        insert(:trigger, %{workflow: sandbox_workflow, type: :webhook})

      sandbox_job1 =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Fetch Data",
          adaptor: "@openfn/http@2.0.0",
          body: "fetchV2()"
        })

      sandbox_job2 =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Process",
          adaptor: "@openfn/common@2.0.0",
          body: "processV2()"
        })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job1.id
      })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_job_id: sandbox_job1.id,
        target_job_id: sandbox_job2.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      # Jobs should match structurally and keep parent UUIDs with sandbox properties
      jobs = result["jobs"]
      assert length(jobs) == 2

      job1 = Enum.find(jobs, &(&1["name"] == "Fetch Data"))
      assert job1["id"] == parent_job1.id
      assert job1["adaptor"] == "@openfn/http@2.0.0"
      assert job1["body"] == "fetchV2()"

      job2 = Enum.find(jobs, &(&1["name"] == "Process"))
      assert job2["id"] == parent_job2.id
      assert job2["adaptor"] == "@openfn/common@2.0.0"
      assert job2["body"] == "processV2()"

      # Trigger should match
      triggers = result["triggers"]
      assert length(triggers) == 1
      trigger = hd(triggers)
      assert trigger["id"] == parent_trigger.id
    end

    test "uses name to disambiguate when structure is ambiguous" do
      # Parent: webhook -> "Job A" (@openfn/http@1.0.0)
      #                  -> "Job B" (@openfn/http@1.0.0)
      parent_workflow = insert(:workflow)

      parent_trigger =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      parent_job_a =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Job A",
          adaptor: "@openfn/http@1.0.0"
        })

      parent_job_b =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Job B",
          adaptor: "@openfn/http@1.0.0"
        })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job_a.id
      })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job_b.id
      })

      # Sandbox: webhook -> "Job A" (@openfn/http@2.0.0)
      #                  -> "Job C" (@openfn/http@1.0.0)
      sandbox_workflow = insert(:workflow)

      sandbox_trigger =
        insert(:trigger, %{workflow: sandbox_workflow, type: :webhook})

      sandbox_job_a =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Job A",
          adaptor: "@openfn/http@2.0.0"
        })

      sandbox_job_c =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Job C",
          adaptor: "@openfn/http@1.0.0"
        })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job_a.id
      })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job_c.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      jobs = result["jobs"]
      assert length(jobs) == 3

      # Job A matches by name
      job_a = Enum.find(jobs, &(&1["name"] == "Job A"))
      assert job_a["id"] == parent_job_a.id
      assert job_a["adaptor"] == "@openfn/http@2.0.0"

      # Job B marked for deletion
      job_b = Enum.find(jobs, &(&1["id"] == parent_job_b.id))
      assert job_b["delete"] == true

      # Job C is new
      job_c = Enum.find(jobs, &(&1["name"] == "Job C"))
      refute job_c["id"] == parent_job_a.id
      refute job_c["id"] == parent_job_b.id
      assert job_c["adaptor"] == "@openfn/http@1.0.0"
    end

    test "treats as no match when ambiguity cannot be resolved" do
      # Parent: webhook -> "Process" (@openfn/common@1.0.0)
      #                 -> "Process" (@openfn/common@1.0.0) [duplicate]
      parent_workflow = insert(:workflow)

      parent_trigger =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      parent_job1 =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Process 1",
          adaptor: "@openfn/common@1.0.0"
        })

      parent_job2 =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Process 2",
          adaptor: "@openfn/common@1.0.0"
        })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job1.id
      })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job2.id
      })

      # Sandbox: webhook -> "Transform" (@openfn/http@1.0.0)
      sandbox_workflow = insert(:workflow)

      sandbox_trigger =
        insert(:trigger, %{workflow: sandbox_workflow, type: :webhook})

      sandbox_job =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Transform",
          adaptor: "@openfn/http@1.0.0"
        })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      jobs = result["jobs"]
      assert length(jobs) == 3

      # Both parent jobs marked for deletion
      deleted_jobs = Enum.filter(jobs, &(&1["delete"] == true))
      assert length(deleted_jobs) == 2
      assert parent_job1.id in Enum.map(deleted_jobs, & &1["id"])
      assert parent_job2.id in Enum.map(deleted_jobs, & &1["id"])

      # Transform is new
      transform_job = Enum.find(jobs, &(&1["name"] == "Transform"))
      refute transform_job["id"] == parent_job1.id
      refute transform_job["id"] == parent_job2.id
      refute transform_job["delete"]
    end

    test "handles complex DAG with additions and branches" do
      # Parent: cron -> "Job1" -> "Job2"
      parent_workflow = insert(:workflow)

      parent_trigger =
        insert(:trigger, %{
          workflow: parent_workflow,
          type: :cron,
          cron_expression: "0 * * * *"
        })

      parent_job1 =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Job1"
        })

      parent_job2 =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Job2"
        })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job1.id
      })

      insert(:edge, %{
        workflow: parent_workflow,
        source_job_id: parent_job1.id,
        target_job_id: parent_job2.id
      })

      # Sandbox: cron -> "Step1" -> "Step2" -> "Step3" [added]
      #                          \-> "Step4" [added branch]
      sandbox_workflow = insert(:workflow)

      sandbox_trigger =
        insert(:trigger, %{
          workflow: sandbox_workflow,
          type: :cron,
          cron_expression: "0 * * * *"
        })

      sandbox_job1 =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Step1"
        })

      sandbox_job2 =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Step2"
        })

      sandbox_job3 =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Step3"
        })

      sandbox_job4 =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Step4"
        })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job1.id
      })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_job_id: sandbox_job1.id,
        target_job_id: sandbox_job2.id
      })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_job_id: sandbox_job2.id,
        target_job_id: sandbox_job3.id
      })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_job_id: sandbox_job1.id,
        target_job_id: sandbox_job4.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      jobs = result["jobs"]
      assert length(jobs) == 4

      # Step1 matches Job1
      step1 = Enum.find(jobs, &(&1["name"] == "Step1"))
      assert step1["id"] == parent_job1.id

      # Step2 matches Job2
      step2 = Enum.find(jobs, &(&1["name"] == "Step2"))
      assert step2["id"] == parent_job2.id

      # Step3 and Step4 are new
      step3 = Enum.find(jobs, &(&1["name"] == "Step3"))
      step4 = Enum.find(jobs, &(&1["name"] == "Step4"))
      refute step3["id"] in [parent_job1.id, parent_job2.id]
      refute step4["id"] in [parent_job1.id, parent_job2.id]

      # Edges are remapped correctly
      edges = result["edges"]
      assert length(edges) == 4

      # Check edge connections use correct IDs
      edge_to_step2 = Enum.find(edges, &(&1["target_job_id"] == step2["id"]))
      assert edge_to_step2["source_job_id"] == step1["id"]

      edge_to_step3 = Enum.find(edges, &(&1["target_job_id"] == step3["id"]))
      assert edge_to_step3["source_job_id"] == step2["id"]

      edge_to_step4 = Enum.find(edges, &(&1["target_job_id"] == step4["id"]))
      assert edge_to_step4["source_job_id"] == step1["id"]
    end

    test "preserves target credential references for matched jobs" do
      parent_workflow = insert(:workflow)

      parent_trigger =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      # Create credentials
      parent_pc = insert(:project_credential)
      _parent_kc = insert(:keychain_credential)

      parent_job =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Job",
          project_credential_id: parent_pc.id
        })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job.id
      })

      # Sandbox with different credentials
      sandbox_workflow = insert(:workflow)

      sandbox_trigger =
        insert(:trigger, %{workflow: sandbox_workflow, type: :webhook})

      sandbox_pc = insert(:project_credential)
      _sandbox_kc = insert(:keychain_credential)

      sandbox_job =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Modified Job",
          project_credential_id: sandbox_pc.id
        })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      jobs = result["jobs"]
      job = hd(jobs)

      # Should keep parent's credentials
      assert job["project_credential_id"] == parent_pc.id
      # But use sandbox's other properties
      assert job["name"] == "Modified Job"
    end

    test "preserves target keychain credential references for matched jobs" do
      parent_workflow = insert(:workflow)

      parent_trigger =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      # Create keychain credential
      parent_kc = insert(:keychain_credential)

      parent_job =
        insert(:job, %{
          workflow: parent_workflow,
          name: "Job",
          keychain_credential_id: parent_kc.id
        })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job.id
      })

      # Sandbox with different keychain credential
      sandbox_workflow = insert(:workflow)

      sandbox_trigger =
        insert(:trigger, %{workflow: sandbox_workflow, type: :webhook})

      sandbox_kc = insert(:keychain_credential)

      sandbox_job =
        insert(:job, %{
          workflow: sandbox_workflow,
          name: "Modified Job",
          keychain_credential_id: sandbox_kc.id
        })

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      jobs = result["jobs"]
      job = hd(jobs)

      # Should keep parent's keychain credential
      assert job["keychain_credential_id"] == parent_kc.id
      # But use sandbox's other properties
      assert job["name"] == "Modified Job"
    end

    test "handles multiple triggers correctly" do
      # Parent with webhook and cron
      parent_workflow = insert(:workflow)

      parent_webhook =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      parent_cron =
        insert(:trigger, %{
          workflow: parent_workflow,
          type: :cron,
          cron_expression: "0 * * * *"
        })

      parent_job = insert(:job, %{workflow: parent_workflow, name: "Job"})

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_webhook.id,
        target_job_id: parent_job.id
      })

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_cron.id,
        target_job_id: parent_job.id
      })

      # Sandbox with modified cron and removed webhook
      sandbox_workflow = insert(:workflow)

      sandbox_cron =
        insert(:trigger, %{
          workflow: sandbox_workflow,
          type: :cron,
          cron_expression: "*/5 * * * *"
        })

      sandbox_job = insert(:job, %{workflow: sandbox_workflow, name: "Job"})

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_cron.id,
        target_job_id: sandbox_job.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      triggers = result["triggers"]
      assert length(triggers) == 2

      # Webhook marked for deletion
      webhook = Enum.find(triggers, &(&1["id"] == parent_webhook.id))
      assert webhook["delete"] == true

      # Cron updated with new expression
      cron = Enum.find(triggers, &(&1["type"] == "cron" && !&1["delete"]))
      assert cron["cron_expression"] == "*/5 * * * *"
    end

    test "ignores kafka triggers" do
      parent_workflow = insert(:workflow)

      _parent_kafka =
        insert(:trigger, %{workflow: parent_workflow, type: :kafka})

      _parent_webhook =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      sandbox_workflow = insert(:workflow)

      _sandbox_kafka =
        insert(:trigger, %{workflow: sandbox_workflow, type: :kafka})

      _sandbox_webhook =
        insert(:trigger, %{workflow: sandbox_workflow, type: :webhook})

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      triggers = result["triggers"]
      # Only webhook trigger should be in result
      assert length(triggers) == 1
      assert hd(triggers)["type"] == "webhook"
    end

    test "returns proper format for Provisioner.import_document" do
      parent_workflow = insert(:workflow, name: "Parent Workflow")

      parent_trigger =
        insert(:trigger, %{workflow: parent_workflow, type: :webhook})

      parent_job = insert(:job, %{workflow: parent_workflow})

      insert(:edge, %{
        workflow: parent_workflow,
        source_trigger_id: parent_trigger.id,
        target_job_id: parent_job.id
      })

      sandbox_workflow = insert(:workflow, name: "Modified Workflow")

      sandbox_trigger =
        insert(:trigger, %{workflow: sandbox_workflow, type: :webhook})

      sandbox_job = insert(:job, %{workflow: sandbox_workflow})

      insert(:edge, %{
        workflow: sandbox_workflow,
        source_trigger_id: sandbox_trigger.id,
        target_job_id: sandbox_job.id
      })

      result = Sandboxes.merge_workflow(sandbox_workflow, parent_workflow)

      # Check required fields for import_document
      assert result["id"] == parent_workflow.id
      assert result["name"] == "Modified Workflow"
      assert is_list(result["jobs"])
      assert is_list(result["triggers"])
      assert is_list(result["edges"])

      # All jobs should have required fields
      Enum.each(result["jobs"], fn job ->
        assert job["id"]
        assert is_binary(job["name"]) || job["delete"] == true
      end)

      # All triggers should have required fields
      Enum.each(result["triggers"], fn trigger ->
        assert trigger["id"]
        assert is_binary(trigger["type"]) || trigger["delete"] == true
      end)

      # All edges should have required fields
      Enum.each(result["edges"], fn edge ->
        assert edge["id"]
        assert edge["condition_type"]
      end)
    end
  end

  defp attach_keychain!(
         %Project{} = project,
         %User{} = creator,
         default_cred,
         attrs \\ %{}
       ) do
    insert(
      :keychain_credential,
      Map.merge(
        %{
          project: project,
          created_by: creator,
          default_credential: default_cred,
          name: "kc-main",
          path: "$.org_id"
        },
        attrs
      )
    )
  end

  defp rewire_job_to_keychain!(%Job{} = job, %KeychainCredential{} = kc) do
    job
    |> Ecto.Changeset.change(%{
      project_credential_id: nil,
      keychain_credential_id: kc.id
    })
    |> Repo.update!()
  end

  defp find_sandbox_job!(%Project{} = sandbox, wf_name, job_name) do
    from(j in Job,
      join: w in assoc(j, :workflow),
      where:
        w.project_id == ^sandbox.id and w.name == ^wf_name and
          j.name == ^job_name,
      select: j
    )
    |> Repo.one!()
  end

  describe "provisioning end-to-end" do
    test "clones settings, references credentials, clones DAG, disables triggers, remaps positions, copies latest heads" do
      %{actor: actor, parent: parent, flows: %{w1: w1, w2: w2}} =
        build_parent_fixture!(:owner)

      {:ok, sandbox} =
        Sandboxes.provision(parent, actor, %{
          name: "sandbox-x",
          color: "#abcdef",
          env: "staging",
          collaborators: [%{user_id: actor.id, role: :owner}]
        })

      sandbox = Repo.preload(sandbox, [:project_users, :project_credentials])

      # basics & clone fields
      assert sandbox.parent_id == parent.id
      assert sandbox.name == "sandbox-x"
      assert sandbox.color == "#abcdef"
      assert sandbox.env == "staging"
      assert sandbox.allow_support_access == parent.allow_support_access
      assert sandbox.retention_policy == parent.retention_policy

      # collaborators (actor owner)
      assert Enum.any?(
               sandbox.project_users,
               &(&1.user_id == actor.id and &1.role == :owner)
             )

      # credentials referenced (same credential_ids)
      parent_cred_ids =
        from(pc in ProjectCredential,
          where: pc.project_id == ^parent.id,
          select: pc.credential_id
        )
        |> Repo.all()
        |> MapSet.new()

      sandbox_cred_ids =
        from(pc in ProjectCredential,
          where: pc.project_id == ^sandbox.id,
          select: pc.credential_id
        )
        |> Repo.all()
        |> MapSet.new()

      assert sandbox_cred_ids == parent_cred_ids

      # workflows cloned (names preserved, new ids)
      s_wfs =
        Repo.all(
          from w in Workflow,
            where: w.project_id == ^sandbox.id,
            order_by: w.name
        )

      assert Enum.map(s_wfs, & &1.name) |> Enum.sort() == ["Alpha", "Beta"]

      # build old->new workflow id map
      old_to_new =
        for sw <- s_wfs, into: %{} do
          {Repo.get_by!(Workflow, project_id: parent.id, name: sw.name).id,
           sw.id}
        end

      # positions remapped to new node ids (no old ids present; counts preserved when present)
      for {old_wf_id, new_wf_id} <- old_to_new do
        old = Repo.get!(Workflow, old_wf_id)
        new = Repo.get!(Workflow, new_wf_id)

        parent_node_ids =
          Repo.all(from j in Job, where: j.workflow_id == ^old.id, select: j.id) ++
            Repo.all(
              from t in Trigger, where: t.workflow_id == ^old.id, select: t.id
            )

        if map_size(old.positions || %{}) > 0 do
          assert map_size(new.positions) == map_size(old.positions)
        end

        unless is_nil(new.positions) do
          refute Enum.any?(Map.keys(new.positions), &(&1 in parent_node_ids))
        end
      end

      # triggers are cloned and DISABLED
      s_triggers =
        from(t in Trigger,
          join: w in assoc(t, :workflow),
          where: w.project_id == ^sandbox.id
        )
        |> Repo.all()

      assert s_triggers != []
      assert Enum.all?(s_triggers, &match?(false, &1.enabled))

      # edges remapped (no references to parent node ids)
      s_edges =
        from(e in Edge,
          join: w in assoc(e, :workflow),
          where: w.project_id == ^sandbox.id
        )
        |> Repo.all()

      parent_ids =
        [w1.id, w2.id] ++
          Repo.all(
            from j in Job, where: j.workflow_id in ^[w1.id, w2.id], select: j.id
          ) ++
          Repo.all(
            from t in Trigger,
              where: t.workflow_id in ^[w1.id, w2.id],
              select: t.id
          )

      for e <- s_edges do
        refute e.source_job_id in parent_ids
        refute e.source_trigger_id in parent_ids
        refute e.target_job_id in parent_ids
      end

      # jobs cloned and keep code/adaptor
      s_jobs =
        from(j in Job,
          join: w in assoc(j, :workflow),
          where: w.project_id == ^sandbox.id
        )
        |> Repo.all()

      assert s_jobs != []
      assert Enum.all?(s_jobs, &(is_binary(&1.body) and is_binary(&1.adaptor)))

      # workflow versions: only latest per parent workflow
      for {old_wf, new_wf} <- old_to_new do
        old_latest =
          from(v in WorkflowVersion,
            where: v.workflow_id == ^old_wf,
            order_by: [desc: v.inserted_at, desc: v.id],
            limit: 1
          )
          |> Repo.one!()

        new_versions =
          Repo.all(from v in WorkflowVersion, where: v.workflow_id == ^new_wf)

        assert length(new_versions) == 1
        assert hd(new_versions).hash == old_latest.hash
      end
    end

    test "copies only requested eligible named dataclips" do
      %{
        actor: actor,
        parent: parent,
        dataclips: %{ok1: dc1, ok2: dc2, forbidden: dc_forbidden}
      } =
        build_parent_fixture!(:admin)

      {:ok, sandbox} =
        Sandboxes.provision(parent, actor, %{
          name: "sb-clips",
          dataclip_ids: [dc1.id, dc2.id, dc_forbidden.id]
        })

      copied =
        from(d in Dataclip,
          where: d.project_id == ^sandbox.id,
          select: {d.name, d.type}
        )
        |> Repo.all()
        |> MapSet.new()

      assert copied == MapSet.new([{"g1", :global}, {"req1", :http_request}])
    end

    test "copies trigger webhook auth methods when present" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:admin)

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-wam"})

      cnt =
        from(t in Trigger,
          join: w in assoc(t, :workflow),
          where: w.project_id == ^sandbox.id,
          join: j in "trigger_webhook_auth_methods",
          on: j.trigger_id == t.id,
          select: count(j.webhook_auth_method_id)
        )
        |> Repo.one()

      assert cnt >= 1
    end
  end

  describe "keychains" do
    test "clones only used keychains and rewires jobs to cloned keychains" do
      # Parent with credential + keychain used by one job
      %{
        actor: actor,
        parent: parent,
        pc: pc,
        flows: %{w1: w1},
        nodes: %{j1: j1, j2: j2}
      } = build_parent_fixture!(:owner)

      # Create a keychain in the parent that points to the same default credential
      kc = attach_keychain!(parent, actor, pc.credential)

      # Rewire j2 in parent to use the keychain (and drop project_credential)
      rewire_job_to_keychain!(Repo.preload(j2, [:workflow]), kc)

      # Provision sandbox
      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      # The sandbox should contain exactly one keychain (the used one)
      s_kcs =
        from(k in KeychainCredential, where: k.project_id == ^sandbox.id)
        |> Repo.all()

      assert length(s_kcs) == 1
      s_kc = hd(s_kcs)
      assert s_kc.name == kc.name
      assert s_kc.path == kc.path
      assert s_kc.default_credential_id == kc.default_credential_id
      assert s_kc.created_by_id == actor.id

      # j2 should be rewired to the sandbox keychain (no project_credential)
      s_j2 =
        find_sandbox_job!(sandbox, w1.name, j2.name)
        |> Repo.preload(:project_credential)

      assert s_j2.keychain_credential_id == s_kc.id
      assert is_nil(s_j2.project_credential_id)

      # j1 should still use a project_credential (no keychain)
      s_j1 =
        find_sandbox_job!(sandbox, w1.name, j1.name)
        |> Repo.preload(:project_credential)

      assert is_nil(s_j1.keychain_credential_id)
      assert not is_nil(s_j1.project_credential_id)

      # Ensure we didn't duplicate underlying credentials: child project_credentials
      # should reference the same credential_ids as parent
      parent_cred_ids =
        from(pc in ProjectCredential,
          where: pc.project_id == ^parent.id,
          select: pc.credential_id
        )
        |> Repo.all()
        |> MapSet.new()

      sandbox_cred_ids =
        from(pc in ProjectCredential,
          where: pc.project_id == ^sandbox.id,
          select: pc.credential_id
        )
        |> Repo.all()
        |> MapSet.new()

      assert sandbox_cred_ids == parent_cred_ids
    end

    test "does not clone unused keychains" do
      %{
        actor: actor,
        parent: parent,
        pc: pc
      } = build_parent_fixture!(:admin)

      # Parent keychain exists but is not referenced by any job
      _unused =
        attach_keychain!(parent, actor, pc.credential, %{name: "kc-unused"})

      {:ok, sandbox} =
        Sandboxes.provision(parent, actor, %{name: "sb-kc-unused"})

      # No keychains should be present in sandbox because none were used by jobs
      cnt =
        from(k in KeychainCredential,
          where: k.project_id == ^sandbox.id,
          select: count(k.id)
        )
        |> Repo.one()

      assert cnt == 0
    end

    test "clones keychain credentials and rewires jobs to the cloned keychain" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:owner)

      kc =
        insert(:keychain_credential,
          project: parent,
          created_by: actor,
          name: "kc-1",
          path: "$.user_id"
        )

      w = insert(:workflow, project: parent, name: "KC Flow")
      _t = insert(:trigger, workflow: w, enabled: true)

      _j =
        insert(:job,
          workflow: w,
          name: "UsesKC",
          keychain_credential: kc,
          project_credential: nil
        )

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      # child keychain exists in sandbox
      kc_child =
        from(k in Lightning.Credentials.KeychainCredential,
          where: k.project_id == ^sandbox.id and k.name == "kc-1"
        )
        |> Repo.one!()

      # cloned job points to child keychain, not to project_credential
      sj =
        from(j in Job,
          join: w in assoc(j, :workflow),
          where: w.project_id == ^sandbox.id and j.name == "UsesKC",
          select: %{
            kc_id: j.keychain_credential_id,
            pc_id: j.project_credential_id
          }
        )
        |> Repo.one!()

      assert sj.kc_id == kc_child.id
      assert is_nil(sj.pc_id)
    end

    test "raises when cloning an invalid keychain (invalid JSONPath etc.)" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:owner)

      # invalid path (doesn't start with '$')
      _kc_bad =
        insert(:keychain_credential,
          project: parent,
          created_by: actor,
          name: "kc-bad",
          path: "user.id"
        )

      w = insert(:workflow, project: parent, name: "Bad KC Flow")
      _t = insert(:trigger, workflow: w, enabled: true)

      _j =
        insert(:job,
          workflow: w,
          name: "UsesBadKC",
          keychain_credential:
            Repo.get_by!(Lightning.Credentials.KeychainCredential,
              project_id: parent.id,
              name: "kc-bad"
            ),
          project_credential: nil
        )

      assert_raise Ecto.InvalidChangesetError, fn ->
        Sandboxes.provision(parent, actor, %{name: "sb-kc-bad"})
      end
    end
  end

  describe "errors" do
    test "returns {:error, changeset} when project creation fails" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:owner)

      assert {:error, :rollback} =
               Sandboxes.provision(parent, actor, %{name: ""})
    end
  end

  describe "collaborators" do
    test "adds non-owner collaborators" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:owner)
      other = insert(:user)

      {:ok, sandbox} =
        Sandboxes.provision(parent, actor, %{
          name: "sb-with-collab",
          collaborators: [
            # should be added
            %{user_id: other.id, role: :editor},
            # ignored (creator is the only owner)
            %{user_id: actor.id, role: :owner}
          ]
        })

      # <-- reload association
      sandbox = Repo.preload(sandbox, :project_users)

      assert Enum.any?(
               sandbox.project_users,
               &(&1.user_id == other.id and &1.role == :editor)
             )

      assert Enum.count(sandbox.project_users, &(&1.role == :owner)) == 1
    end
  end

  describe "dataclips guards" do
    test "does nothing when dataclip_ids key is omitted (nil branch)" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:owner)
      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-no-clips"})

      assert Repo.aggregate(
               from(d in Dataclip, where: d.project_id == ^sandbox.id),
               :count,
               :id
             ) == 0
    end

    test "does nothing when dataclip_ids is [] (empty branch)" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:admin)

      {:ok, sandbox} =
        Sandboxes.provision(parent, actor, %{
          name: "sb-empty-clips",
          dataclip_ids: []
        })

      assert Repo.aggregate(
               from(d in Dataclip, where: d.project_id == ^sandbox.id),
               :count,
               :id
             ) == 0
    end
  end

  describe "positions remapping" do
    test "drops positions whose node ids are not in the cloned graph" do
      %{actor: actor, parent: parent, flows: %{w1: w1}} =
        build_parent_fixture!(:owner)

      # add an extra bogus position
      bogus_id = Ecto.UUID.generate()

      Repo.update!(
        Ecto.Changeset.change(w1,
          positions: Map.put(w1.positions || %{}, bogus_id, %{x: 999, y: 999})
        )
      )

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-pos-drop"})

      [sw1] =
        Repo.all(
          from w in Workflow,
            where: w.project_id == ^sandbox.id and w.name == "Alpha"
        )

      # no parent ids should appear in the child positions, and bogus was dropped
      refute Map.has_key?(sw1.positions || %{}, bogus_id)
    end

    test "returns nil when no positions remap (all keys unknown)" do
      %{actor: actor} = ctx = build_parent_fixture!(:owner)
      parent = ctx.parent

      # Make a brand new workflow with positions only for unknown ids
      w3 = insert(:workflow, project: parent, name: "Gamma")
      only_bogus = %{Ecto.UUID.generate() => %{x: 1, y: 2}}
      Repo.update!(Ecto.Changeset.change(w3, positions: only_bogus))

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-pos-nil"})

      sw3 = Repo.get_by!(Workflow, project_id: sandbox.id, name: "Gamma")
      assert is_nil(sw3.positions)
    end
  end

  describe "jobs without credentials" do
    test "clones a job with no project_credential and no keychain (both nil)" do
      %{actor: actor, parent: parent} = build_parent_fixture!(:owner)

      w = insert(:workflow, project: parent, name: "Bare")
      _t = insert(:trigger, workflow: w, enabled: true)

      j0 =
        insert(:job,
          workflow: w,
          name: "NoCreds",
          project_credential: nil,
          keychain_credential: nil
        )

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-nocreds"})

      sj =
        from(j in Job,
          join: w in assoc(j, :workflow),
          where: w.project_id == ^sandbox.id and j.name == ^j0.name,
          select: %{
            pc_id: j.project_credential_id,
            kc_id: j.keychain_credential_id
          }
        )
        |> Repo.one!()

      assert is_nil(sj.pc_id)
      assert is_nil(sj.kc_id)
    end
  end
end

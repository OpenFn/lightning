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

  describe "update_sandbox/3" do
    setup do
      parent = insert(:project, name: "parent")
      actor = insert(:user)
      sandbox = insert(:project, parent: parent, name: "child")
      {:ok, parent: parent, actor: actor, sandbox: sandbox}
    end

    test "fails with unauthorized actor", %{
      actor: actor,
      sandbox: sb
    } do
      assert {:error, :unauthorized} =
               Sandboxes.update_sandbox(sb, actor, %{name: "X"})
    end

    test "succeeds with owner", %{
      actor: actor,
      sandbox: sb
    } do
      ensure_member!(sb, actor, :owner)

      {:ok, updated} =
        Sandboxes.update_sandbox(sb, actor, %{name: "updated"})

      assert updated.name == "updated"
    end

    test "succeeds with admin", %{
      actor: actor,
      sandbox: sb
    } do
      ensure_member!(sb, actor, :admin)

      {:ok, updated} =
        Sandboxes.update_sandbox(sb, actor, %{name: "updated"})

      assert updated.name == "updated"
    end

    test "uuid not found returns not_found", %{actor: actor} do
      bad_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               Sandboxes.update_sandbox(bad_id, actor, %{name: "x"})
    end

    test "uuid found delegates to project update", %{
      parent: parent,
      actor: actor
    } do
      sb = insert(:project, parent: parent, name: "to-change")
      ensure_member!(sb, actor, :owner)

      {:ok, updated} =
        Sandboxes.update_sandbox(sb.id, actor, %{name: "changed"})

      assert updated.name == "changed"
    end
  end

  describe "delete_sandbox/2 with complex lineages" do
    test "deletes simple parent-child lineage" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      child = insert(:project, name: "child", parent: parent)

      ensure_member!(parent, actor, :owner)
      ensure_member!(child, actor, :owner)

      # Add some data to both projects
      parent_workflow = insert(:workflow, project: parent, name: "parent_wf")
      child_workflow = insert(:workflow, project: child, name: "child_wf")

      {:ok, _} = Sandboxes.delete_sandbox(parent, actor)

      # Both parent and child should be deleted
      refute Repo.get(Project, parent.id)
      refute Repo.get(Project, child.id)
      refute Repo.get(Workflow, parent_workflow.id)
      refute Repo.get(Workflow, child_workflow.id)
    end

    test "deletes three-level lineage (grandparent -> parent -> child)" do
      actor = insert(:user)
      grandparent = insert(:project, name: "grandparent")
      parent = insert(:project, name: "parent", parent: grandparent)
      child = insert(:project, name: "child", parent: parent)

      ensure_member!(grandparent, actor, :owner)
      ensure_member!(parent, actor, :owner)
      ensure_member!(child, actor, :owner)

      # Add workflows to track deletion
      gp_wf = insert(:workflow, project: grandparent, name: "gp_wf")
      p_wf = insert(:workflow, project: parent, name: "p_wf")
      c_wf = insert(:workflow, project: child, name: "c_wf")

      {:ok, _} = Sandboxes.delete_sandbox(grandparent, actor)

      # All three levels should be deleted
      refute Repo.get(Project, grandparent.id)
      refute Repo.get(Project, parent.id)
      refute Repo.get(Project, child.id)
      refute Repo.get(Workflow, gp_wf.id)
      refute Repo.get(Workflow, p_wf.id)
      refute Repo.get(Workflow, c_wf.id)
    end

    test "deletes complex tree with multiple branches" do
      actor = insert(:user)
      root = insert(:project, name: "root")

      # Create multiple branches
      branch_a = insert(:project, name: "branch_a", parent: root)
      branch_b = insert(:project, name: "branch_b", parent: root)

      # Each branch has children
      branch_a_child1 = insert(:project, name: "a_child1", parent: branch_a)
      branch_a_child2 = insert(:project, name: "a_child2", parent: branch_a)
      branch_b_child1 = insert(:project, name: "b_child1", parent: branch_b)

      # One branch has grandchildren
      branch_a_grandchild =
        insert(:project, name: "a_grandchild", parent: branch_a_child1)

      # Set permissions
      for project <- [
            root,
            branch_a,
            branch_b,
            branch_a_child1,
            branch_a_child2,
            branch_b_child1,
            branch_a_grandchild
          ] do
        ensure_member!(project, actor, :owner)
      end

      # Add data to track deletions
      workflows =
        Enum.map(
          [
            root,
            branch_a,
            branch_b,
            branch_a_child1,
            branch_a_child2,
            branch_b_child1,
            branch_a_grandchild
          ],
          fn project ->
            insert(:workflow, project: project, name: "wf_#{project.name}")
          end
        )

      {:ok, _} = Sandboxes.delete_sandbox(root, actor)

      # All projects in the tree should be deleted
      for project <- [
            root,
            branch_a,
            branch_b,
            branch_a_child1,
            branch_a_child2,
            branch_b_child1,
            branch_a_grandchild
          ] do
        refute Repo.get(Project, project.id)
      end

      # All workflows should be deleted
      for workflow <- workflows do
        refute Repo.get(Workflow, workflow.id)
      end
    end

    test "deletes middle node while preserving unrelated branches" do
      actor = insert(:user)
      root = insert(:project, name: "root")

      # Create separate branches
      branch_to_delete = insert(:project, name: "delete_me", parent: root)
      branch_to_keep = insert(:project, name: "keep_me", parent: root)

      # Children of the branch to delete
      child_to_delete =
        insert(:project, name: "child_delete", parent: branch_to_delete)

      # Children of the branch to keep
      child_to_keep =
        insert(:project, name: "child_keep", parent: branch_to_keep)

      # Set permissions
      for project <- [
            root,
            branch_to_delete,
            branch_to_keep,
            child_to_delete,
            child_to_keep
          ] do
        ensure_member!(project, actor, :owner)
      end

      # Add workflows
      keep_wf = insert(:workflow, project: branch_to_keep, name: "keep_wf")

      keep_child_wf =
        insert(:workflow, project: child_to_keep, name: "keep_child_wf")

      delete_wf = insert(:workflow, project: branch_to_delete, name: "delete_wf")

      delete_child_wf =
        insert(:workflow, project: child_to_delete, name: "delete_child_wf")

      {:ok, _} = Sandboxes.delete_sandbox(branch_to_delete, actor)

      # Only the targeted branch should be deleted
      refute Repo.get(Project, branch_to_delete.id)
      refute Repo.get(Project, child_to_delete.id)
      refute Repo.get(Workflow, delete_wf.id)
      refute Repo.get(Workflow, delete_child_wf.id)

      # Root and other branch should remain
      assert Repo.get(Project, root.id)
      assert Repo.get(Project, branch_to_keep.id)
      assert Repo.get(Project, child_to_keep.id)
      assert Repo.get(Workflow, keep_wf.id)
      assert Repo.get(Workflow, keep_child_wf.id)
    end

    test "deletes leaf node without affecting ancestors or siblings" do
      actor = insert(:user)
      root = insert(:project, name: "root")
      parent = insert(:project, name: "parent", parent: root)
      sibling = insert(:project, name: "sibling", parent: parent)
      target_leaf = insert(:project, name: "target_leaf", parent: parent)

      # Set permissions
      for project <- [root, parent, sibling, target_leaf] do
        ensure_member!(project, actor, :owner)
      end

      # Add workflows to track what gets deleted
      root_wf = insert(:workflow, project: root, name: "root_wf")
      parent_wf = insert(:workflow, project: parent, name: "parent_wf")
      sibling_wf = insert(:workflow, project: sibling, name: "sibling_wf")
      leaf_wf = insert(:workflow, project: target_leaf, name: "leaf_wf")

      {:ok, _} = Sandboxes.delete_sandbox(target_leaf, actor)

      # Only the leaf should be deleted
      refute Repo.get(Project, target_leaf.id)
      refute Repo.get(Workflow, leaf_wf.id)

      # Everything else should remain
      assert Repo.get(Project, root.id)
      assert Repo.get(Project, parent.id)
      assert Repo.get(Project, sibling.id)
      assert Repo.get(Workflow, root_wf.id)
      assert Repo.get(Workflow, parent_wf.id)
      assert Repo.get(Workflow, sibling_wf.id)
    end

    test "deletes projects with complex associated data (workorders, steps, credentials)" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      child = insert(:project, name: "child", parent: parent)

      ensure_member!(parent, actor, :owner)
      ensure_member!(child, actor, :owner)

      # Create complex data structure for parent
      parent_cred = insert(:credential, user: actor)

      parent_pc =
        insert(:project_credential, project: parent, credential: parent_cred)

      parent_workflow = insert(:workflow, project: parent, name: "parent_wf")

      parent_job =
        insert(:job, workflow: parent_workflow, project_credential: parent_pc)

      parent_trigger = insert(:trigger, workflow: parent_workflow)

      # Create workorder and associated data
      parent_dataclip = insert(:dataclip, project: parent)

      parent_workorder =
        insert(:workorder,
          workflow: parent_workflow,
          trigger: parent_trigger,
          dataclip: parent_dataclip
        )

      parent_run =
        insert(:run,
          work_order: parent_workorder,
          dataclip: parent_dataclip,
          # Fix: add required starting_trigger
          starting_trigger: parent_trigger
        )

      parent_step = insert(:step, runs: [parent_run], job: parent_job)

      # Create similar structure for child
      child_cred = insert(:credential, user: actor)

      child_pc =
        insert(:project_credential, project: child, credential: child_cred)

      child_workflow = insert(:workflow, project: child, name: "child_wf")

      child_job =
        insert(:job, workflow: child_workflow, project_credential: child_pc)

      child_trigger = insert(:trigger, workflow: child_workflow)

      child_dataclip = insert(:dataclip, project: child)

      child_workorder =
        insert(:workorder,
          workflow: child_workflow,
          trigger: child_trigger,
          dataclip: child_dataclip
        )

      child_run =
        insert(:run,
          work_order: child_workorder,
          dataclip: child_dataclip,
          # Fix: add required starting_trigger
          starting_trigger: child_trigger
        )

      child_step = insert(:step, runs: [child_run], job: child_job)

      {:ok, _} = Sandboxes.delete_sandbox(parent, actor)

      # Verify all associated data is deleted
      refute Repo.get(Project, parent.id)
      refute Repo.get(Project, child.id)

      # Parent data should be deleted
      refute Repo.get(Lightning.Workflows.Workflow, parent_workflow.id)
      refute Repo.get(Lightning.Workflows.Job, parent_job.id)
      refute Repo.get(Lightning.Workflows.Trigger, parent_trigger.id)
      refute Repo.get(Lightning.WorkOrder, parent_workorder.id)
      refute Repo.get(Lightning.Run, parent_run.id)
      refute Repo.get(Lightning.Invocation.Step, parent_step.id)
      refute Repo.get(Lightning.Projects.ProjectCredential, parent_pc.id)
      refute Repo.get(Lightning.Invocation.Dataclip, parent_dataclip.id)

      # Child data should be deleted
      refute Repo.get(Lightning.Workflows.Workflow, child_workflow.id)
      refute Repo.get(Lightning.Workflows.Job, child_job.id)
      refute Repo.get(Lightning.Workflows.Trigger, child_trigger.id)
      refute Repo.get(Lightning.WorkOrder, child_workorder.id)
      refute Repo.get(Lightning.Run, child_run.id)
      refute Repo.get(Lightning.Invocation.Step, child_step.id)
      refute Repo.get(Lightning.Projects.ProjectCredential, child_pc.id)
      refute Repo.get(Lightning.Invocation.Dataclip, child_dataclip.id)

      # But the underlying credentials should still exist (they're user-owned)
      assert Repo.get(Lightning.Credentials.Credential, parent_cred.id)
      assert Repo.get(Lightning.Credentials.Credential, child_cred.id)
    end

    test "handles deletion when intermediate project has mixed children (some with/without permission)" do
      actor = insert(:user)
      unauthorized_user = insert(:user)

      root = insert(:project, name: "root")
      middle = insert(:project, name: "middle", parent: root)

      # Child where actor has permission
      authorized_child = insert(:project, name: "auth_child", parent: middle)

      # Child where actor lacks permission
      unauthorized_child = insert(:project, name: "unauth_child", parent: middle)

      # Set permissions - actor owns root and middle, but not unauthorized_child
      ensure_member!(root, actor, :owner)
      ensure_member!(middle, actor, :owner)
      ensure_member!(authorized_child, actor, :owner)
      # Different owner
      ensure_member!(unauthorized_child, unauthorized_user, :owner)

      # Add workflows to track deletion
      root_wf = insert(:workflow, project: root, name: "root_wf")
      middle_wf = insert(:workflow, project: middle, name: "middle_wf")
      auth_wf = insert(:workflow, project: authorized_child, name: "auth_wf")

      unauth_wf =
        insert(:workflow, project: unauthorized_child, name: "unauth_wf")

      # Deleting the root should cascade delete everything, regardless of individual permissions
      # The handle_delete_project function doesn't check permissions on children - it just deletes them
      {:ok, _} = Sandboxes.delete_sandbox(root, actor)

      # All projects should be deleted via cascading deletion
      refute Repo.get(Project, root.id)
      refute Repo.get(Project, middle.id)
      refute Repo.get(Project, authorized_child.id)
      refute Repo.get(Project, unauthorized_child.id)

      # All workflows should be deleted
      refute Repo.get(Workflow, root_wf.id)
      refute Repo.get(Workflow, middle_wf.id)
      refute Repo.get(Workflow, auth_wf.id)
      refute Repo.get(Workflow, unauth_wf.id)
    end

    test "deletes very deep lineage (5+ levels) without stack overflow" do
      actor = insert(:user)

      # Create a 7-level deep hierarchy
      projects =
        Enum.reduce(1..7, [], fn level, acc ->
          parent = if level == 1, do: nil, else: List.first(acc)
          project = insert(:project, name: "level_#{level}", parent: parent)
          ensure_member!(project, actor, :owner)
          [project | acc]
        end)

      # Add workflows to each level
      workflows =
        Enum.map(projects, fn project ->
          insert(:workflow, project: project, name: "wf_#{project.name}")
        end)

      # Delete from the root (deepest in our list due to how we built it)
      root = List.last(projects)

      {:ok, _} = Sandboxes.delete_sandbox(root, actor)

      # All projects should be deleted
      for project <- projects do
        refute Repo.get(Project, project.id)
      end

      # All workflows should be deleted
      for workflow <- workflows do
        refute Repo.get(Workflow, workflow.id)
      end
    end

    test "deletes projects with keychain credentials and complex job references" do
      actor = insert(:user)
      parent = insert(:project, name: "parent")
      child = insert(:project, name: "child", parent: parent)

      ensure_member!(parent, actor, :owner)
      ensure_member!(child, actor, :owner)

      # Create credential and keychain in parent
      cred = insert(:credential, user: actor)
      pc = insert(:project_credential, project: parent, credential: cred)

      kc =
        insert(:keychain_credential,
          project: parent,
          created_by: actor,
          default_credential: cred
        )

      # Create jobs that reference both types of credentials
      parent_workflow = insert(:workflow, project: parent)

      job_with_pc =
        insert(:job, workflow: parent_workflow, project_credential: pc)

      job_with_kc =
        insert(:job, workflow: parent_workflow, keychain_credential: kc)

      # Create similar structure in child
      child_cred = insert(:credential, user: actor)

      child_pc =
        insert(:project_credential, project: child, credential: child_cred)

      child_kc =
        insert(:keychain_credential,
          project: child,
          created_by: actor,
          default_credential: child_cred
        )

      child_workflow = insert(:workflow, project: child)

      child_job_pc =
        insert(:job, workflow: child_workflow, project_credential: child_pc)

      child_job_kc =
        insert(:job, workflow: child_workflow, keychain_credential: child_kc)

      {:ok, _} = Sandboxes.delete_sandbox(parent, actor)

      # Projects should be deleted
      refute Repo.get(Project, parent.id)
      refute Repo.get(Project, child.id)

      # Workflows and jobs should be deleted
      refute Repo.get(Workflow, parent_workflow.id)
      refute Repo.get(Workflow, child_workflow.id)
      refute Repo.get(Job, job_with_pc.id)
      refute Repo.get(Job, job_with_kc.id)
      refute Repo.get(Job, child_job_pc.id)
      refute Repo.get(Job, child_job_kc.id)

      # Project credentials should be deleted
      refute Repo.get(Lightning.Projects.ProjectCredential, pc.id)
      refute Repo.get(Lightning.Projects.ProjectCredential, child_pc.id)

      # Keychain credentials should be deleted
      refute Repo.get(Lightning.Credentials.KeychainCredential, kc.id)
      refute Repo.get(Lightning.Credentials.KeychainCredential, child_kc.id)

      # But underlying credentials should remain
      assert Repo.get(Lightning.Credentials.Credential, cred.id)
      assert Repo.get(Lightning.Credentials.Credential, child_cred.id)
    end

    test "edge case: deleting project with no children (leaf node)" do
      actor = insert(:user)
      standalone = insert(:project, name: "standalone")
      ensure_member!(standalone, actor, :owner)

      workflow = insert(:workflow, project: standalone, name: "standalone_wf")

      {:ok, deleted} = Sandboxes.delete_sandbox(standalone, actor)

      assert deleted.id == standalone.id
      refute Repo.get(Project, standalone.id)
      refute Repo.get(Workflow, workflow.id)
    end

    test "edge case: empty project with no associated data" do
      actor = insert(:user)
      empty_parent = insert(:project, name: "empty_parent")
      empty_child = insert(:project, name: "empty_child", parent: empty_parent)

      ensure_member!(empty_parent, actor, :owner)
      ensure_member!(empty_child, actor, :owner)

      # No workflows, jobs, credentials, or other data - just empty projects

      {:ok, _} = Sandboxes.delete_sandbox(empty_parent, actor)

      refute Repo.get(Project, empty_parent.id)
      refute Repo.get(Project, empty_child.id)
    end
  end
end

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
end

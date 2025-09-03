defmodule Lightning.Projects.SandboxesTest do
  use Lightning.DataCase, async: true

  import Ecto.Query
  import Lightning.Factories
  alias Lightning.Repo

  alias Lightning.Accounts.User
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
      if Code.ensure_loaded?(Lightning.Workflows.WebhookAuthMethod) do
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
  end
end

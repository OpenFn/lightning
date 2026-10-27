defmodule LightningWeb.SandboxLive.MergeTest do
  use LightningWeb.ConnCase, async: true
  use Mimic
  use LightningWeb.SandboxPageHelpers

  import Ecto.Query
  import Lightning.Factories
  import Lightning.GithubHelpers
  import Phoenix.LiveViewTest

  alias Lightning.Projects.Project
  alias Lightning.Repo

  # The merge dialog is drawn by the design system from the preview reply;
  # ticking and unticking rows is its client state. These tests cover what the
  # server offers and what it does with the ids the page sends back.
  defp names(rows), do: rows |> Enum.map(& &1.name) |> Enum.sort()

  defp collection_names(project) do
    project
    |> Lightning.Collections.list_project_collections()
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp mock_provisioner_ok(target) do
    Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn _src,
                                                                      _tgt,
                                                                      _opts ->
      %{"workflows" => []}
    end)

    Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn _tgt,
                                                                      _actor,
                                                                      _yaml,
                                                                      _opts ->
      {:ok, target}
    end)

    Mimic.expect(
      Lightning.Projects.Sandboxes,
      :schedule_sandbox_deletion,
      fn source, _actor ->
        {:ok, source}
      end
    )
  end

  describe "merge preview and merge" do
    setup :register_and_log_in_user

    setup %{user: user} do
      # root
      # ├── child1
      # │   ├── grandchild1
      # │   └── grandchild2
      # ├── child2
      # └── child3
      owner = [%{user: user, role: :owner}]

      root = insert(:project, name: "root", project_users: owner)

      child1 =
        insert(:project, name: "child1", parent: root, project_users: owner)

      child2 =
        insert(:project, name: "child2", parent: root, project_users: owner)

      child3 =
        insert(:project, name: "child3", parent: root, project_users: owner)

      grandchild1 =
        insert(:project,
          name: "grandchild1",
          parent: child1,
          project_users: owner
        )

      grandchild2 =
        insert(:project,
          name: "grandchild2",
          parent: child1,
          project_users: owner
        )

      {:ok,
       root: root,
       child1: child1,
       child2: child2,
       child3: child3,
       grandchild1: grandchild1,
       grandchild2: grandchild2}
    end

    test "the preview offers every live project outside the sandbox's subtree and defaults to the parent",
         %{
           conn: conn,
           root: root,
           child1: child1,
           child2: child2,
           grandchild1: grandchild1,
           user: user
         } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      reply = preview(view, child1)

      assert names(reply.targets) == ["child2", "child3", "root"]
      assert reply.targetId == root.id

      # A leaf's parent is a sandbox, and its grandparent and uncles are offered.
      reply = preview(view, grandchild1)

      assert names(reply.targets) ==
               ["child1", "child2", "child3", "grandchild2", "root"]

      assert reply.targetId == child1.id

      # A named target is used instead of the parent.
      assert %{targetId: target_id} = preview(view, child1, child2.id)
      assert target_id == child2.id

      # Deeper descendants are excluded too.
      insert(:project,
        name: "great-grandchild",
        parent: grandchild1,
        project_users: [%{user: user, role: :owner}]
      )

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")
      refute "great-grandchild" in names(preview(view, child1).targets)

      # A project scheduled for deletion is not a target.
      Repo.update_all(from(p in Project, where: p.id == ^child2.id),
        set: [scheduled_deletion: DateTime.utc_now(:second)]
      )

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")
      refute "child2" in names(preview(view, child1).targets)
    end

    test "a target inside the sandbox's subtree or unknown is refused",
         %{
           conn: conn,
           root: root,
           child1: child1,
           grandchild1: grandchild1
         } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      for target_id <- [grandchild1.id, child1.id, Ecto.UUID.generate()] do
        assert %{error: "Target project not found"} =
                 preview(view, child1, target_id)

        merge(view, child1, target_id)
        assert_reply(view, %{error: "Target project not found"})
      end

      assert Repo.reload!(child1).scheduled_deletion == nil
    end

    test "an unknown sandbox is refused", %{conn: conn, root: root} do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")
      fake = %{id: Ecto.UUID.generate()}

      assert %{error: "Sandbox not found"} = preview(view, fake)

      merge(view, fake, root.id)
      assert_reply(view, %{error: "Sandbox not found"})
    end

    test "a viewer with no other project they may merge into gets an empty preview",
         %{conn: conn, user: user} do
      other_owner = insert(:user)

      parent =
        insert(:project,
          name: "viewed-parent",
          project_users: [
            %{user: user, role: :viewer},
            %{user: other_owner, role: :owner}
          ]
        )

      only_child =
        insert(:project,
          name: "only-child",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert %{
               targets: [],
               targetId: nil,
               workflows: [],
               credentials: [],
               collectionsToAdd: []
             } = preview(view, only_child)
    end

    test "a successful merge calls the merge, redirects to the target and schedules the sandbox's deletion",
         %{conn: conn, root: root, child1: child1, user: user} do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn source,
                                                                        target,
                                                                        _opts ->
        assert source.id == child1.id
        assert target.id == root.id
        %{"workflows" => []}
      end)

      Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn target,
                                                                        actor,
                                                                        yaml,
                                                                        opts ->
        assert target.id == root.id
        assert actor.id == user.id
        assert yaml == %{"workflows" => []}
        assert opts[:allow_stale] == true
        {:ok, target}
      end)

      Mimic.expect(
        Lightning.Projects.Sandboxes,
        :schedule_sandbox_deletion,
        fn source, actor ->
          assert source.id == child1.id
          assert actor.id == user.id
          {:ok, source}
        end
      )

      allow_mocks(view)

      merge(view, child1, root.id)

      flash = assert_redirect(view, ~p"/projects/#{root.id}/w")

      assert flash["info"] ==
               "Successfully merged child1 into root. Sandbox scheduled for deletion."
    end

    test "a merge that succeeds but cannot schedule the deletion says so",
         %{conn: conn, root: root, child1: child1} do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn _s,
                                                                        _t,
                                                                        _o ->
        %{"workflows" => []}
      end)

      Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn _t,
                                                                        _a,
                                                                        _y,
                                                                        _o ->
        {:ok, root}
      end)

      Mimic.expect(
        Lightning.Projects.Sandboxes,
        :schedule_sandbox_deletion,
        fn _s, _a ->
          {:error, :unauthorized}
        end
      )

      allow_mocks(view)

      merge(view, child1, root.id)

      flash = assert_redirect(view, ~p"/projects/#{root.id}/w")

      assert flash["info"] ==
               "Successfully merged child1 into root, but could not schedule the sandbox for deletion."
    end

    test "a failed merge replies with a message that leaks no internals and does not navigate",
         %{conn: conn, root: root, child1: child1} do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      nested_changeset =
        %Lightning.Workflows.Workflow{name: "Patient Sync"}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(
          :name,
          "A workflow with this name already exists"
        )

      nested =
        %Project{workflows: []}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:workflows, [nested_changeset])

      generic = "Couldn't merge this sandbox. Please try again."

      cases = [
        {:import_failed, generic},
        {%Ecto.Changeset{errors: [name: {"is invalid", []}], valid?: false},
         generic},
        {nested, generic},
        {{:unexpected, "something went wrong"}, generic},
        {%{text: "Custom import error message"}, "Custom import error message"}
      ]

      for {reason, message} <- cases do
        Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn _s,
                                                                          _t,
                                                                          _o ->
          %{"workflows" => []}
        end)

        Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn _t,
                                                                          _a,
                                                                          _y,
                                                                          _o ->
          {:error, reason}
        end)

        allow_mocks(view)

        merge(view, child1, root.id)
        assert_reply(view, %{error: ^message})
      end

      # The merge itself failing is reported the same way.
      Mimic.expect(Lightning.Projects.Sandboxes, :merge, fn _s, _t, _a, _o ->
        {:error, :merge_failed}
      end)

      merge(view, child1, root.id)
      assert_reply(view, %{error: ^generic})

      refute_redirected(view, ~p"/projects/#{root.id}/w")
      assert Repo.reload!(child1).scheduled_deletion == nil
    end

    test "the merge keeps only the ids and names the target's preview offers",
         %{conn: conn, user: user} do
      owner = [%{user: user, role: :owner}]
      target = insert(:project, name: "ids-target", project_users: owner)
      gone = insert(:workflow, project: target, name: "gone-in-sandbox")
      shared = insert(:workflow, project: target, name: "shared")

      sandbox =
        insert(:project,
          name: "ids-sandbox",
          parent: target,
          project_users: owner
        )

      added = insert(:workflow, project: sandbox, name: "added")
      kept = insert(:workflow, project: sandbox, name: "shared")
      other = insert(:project, name: "ids-other", project_users: owner)
      foreign = insert(:workflow, project: other, name: "foreign")

      pc =
        insert(:project_credential,
          project: sandbox,
          credential: build(:credential, name: "sandbox-only")
        )

      foreign_pc = insert(:project_credential, project: other)
      insert(:collection, project: sandbox, name: "col-a")
      insert(:collection, project: sandbox, name: "col-b")

      {:ok, view, _} = live(conn, ~p"/projects/#{target.id}/sandboxes")

      reply = preview(view, sandbox)

      assert reply.targetId == target.id

      by_name = Map.new(reply.workflows, &{&1.name, &1})

      assert by_name["added"] |> Map.take([:isNew, :isChanged, :isDeleted]) ==
               %{isNew: true, isChanged: true, isDeleted: false}

      assert by_name["shared"].isNew == false
      assert by_name["gone-in-sandbox"].isDeleted
      assert reply.credentials == [%{id: pc.id, name: "sandbox-only"}]
      assert Enum.sort(reply.collectionsToAdd) == ["col-a", "col-b"]

      test_pid = self()

      Mimic.expect(Lightning.Projects.Sandboxes, :merge, fn _s, t, _a, opts ->
        send(test_pid, {:merge_opts, t.id, opts})
        {:ok, t}
      end)

      Mimic.expect(
        Lightning.Projects.Sandboxes,
        :schedule_sandbox_deletion,
        fn s, _a ->
          {:ok, s}
        end
      )

      allow_mocks(view)

      merge(view, sandbox, target.id, %{
        "workflowIds" => [added.id, kept.id, gone.id, foreign.id, added.id],
        "deletedWorkflowIds" => [gone.id, shared.id, added.id],
        "credentialIds" => [pc.id, foreign_pc.id, "junk"],
        "skippedCollectionNames" => ["col-b", "ghost"]
      })

      assert_redirect(view, ~p"/projects/#{target.id}/w")
      target_id = target.id
      assert_received {:merge_opts, ^target_id, opts}

      assert Enum.sort(opts.selected_workflow_ids) ==
               Enum.sort([added.id, kept.id])

      assert opts.deleted_target_workflow_ids == [gone.id]
      assert opts.selected_credential_ids == [pc.id]
      assert opts.skip_collections == ["col-b"]
    end
  end

  describe "collection sync on merge" do
    setup :register_and_log_in_user

    setup %{user: user} do
      root =
        insert(:project,
          name: "root",
          project_users: [%{user: user, role: :owner}]
        )

      sandbox =
        insert(:project,
          name: "sandbox",
          parent: root,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, root: root, sandbox: sandbox}
    end

    test "the preview offers only collections the target lacks, and nothing when there are none",
         %{conn: conn, root: root, sandbox: sandbox} do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")
      assert preview(view, sandbox).collectionsToAdd == []

      insert(:collection, project: root, name: "shared")
      insert(:collection, project: sandbox, name: "shared")
      insert(:collection, project: sandbox, name: "sandbox-only-col")

      insert(:collection,
        project: root,
        name: "parent-only-col",
        items: [%{key: "k1", value: "v1"}, %{key: "k2", value: "v2"}]
      )

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")
      assert preview(view, sandbox).collectionsToAdd == ["sandbox-only-col"]
    end

    test "a merge creates new collections, keeps the target's own and leaves shared ones unchanged",
         %{conn: conn, root: root, sandbox: sandbox} do
      insert(:collection, project: sandbox, name: "new-col")
      insert(:collection, project: sandbox, name: "shared")
      insert(:collection, project: root, name: "shared")
      insert(:collection, project: root, name: "parent-only")

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")
      mock_provisioner_ok(root)
      allow_mocks(view)

      merge(view, sandbox, root.id)
      assert_redirect(view, ~p"/projects/#{root.id}/w")

      assert collection_names(root) == ["new-col", "parent-only", "shared"]
    end

    test "skipped collection names are left out, and one created in the sandbox after the preview is still created",
         %{conn: conn, root: root, sandbox: sandbox} do
      insert(:collection, project: sandbox, name: "col-a")
      insert(:collection, project: sandbox, name: "col-b")

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      assert Enum.sort(preview(view, sandbox).collectionsToAdd) == [
               "col-a",
               "col-b"
             ]

      insert(:collection, project: sandbox, name: "added-later")

      mock_provisioner_ok(root)
      allow_mocks(view)

      merge(view, sandbox, root.id, %{"skippedCollectionNames" => ["col-b"]})
      assert_redirect(view, ~p"/projects/#{root.id}/w")

      assert collection_names(root) == ["added-later", "col-a"]
    end

    test "skipped names are checked against the submitted target's own preview",
         %{conn: conn, root: root, sandbox: sandbox, user: user} do
      insert(:collection, project: sandbox, name: "col-a")
      insert(:collection, project: sandbox, name: "col-b")
      insert(:collection, project: root, name: "col-a")

      other =
        insert(:project,
          name: "other-target",
          parent: root,
          project_users: [%{user: user, role: :owner}]
        )

      insert(:collection, project: other, name: "other-only")

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      assert preview(view, sandbox, root.id).collectionsToAdd == ["col-b"]

      assert Enum.sort(preview(view, sandbox, other.id).collectionsToAdd) ==
               ["col-a", "col-b"]

      mock_provisioner_ok(other)
      allow_mocks(view)

      # col-a is skipped for the other target; "other-only" is not the
      # sandbox's, so skipping it changes nothing.
      merge(view, sandbox, other.id, %{
        "skippedCollectionNames" => ["col-a", "other-only"]
      })

      assert_redirect(view, ~p"/projects/#{other.id}/w")

      assert collection_names(other) == ["col-b", "other-only"]
      assert collection_names(root) == ["col-a"]
    end

    test "an editor on the target neither sees nor loses the target's own collections",
         %{conn: conn, root: root, sandbox: sandbox} do
      editor = insert(:user)
      insert(:project_user, project: root, user: editor, role: :editor)
      insert(:project_user, project: sandbox, user: editor, role: :admin)
      insert(:collection, project: root, name: "parent-only")

      conn = log_in_user(conn, editor)
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      assert preview(view, sandbox).collectionsToAdd == []

      mock_provisioner_ok(root)
      allow_mocks(view)

      merge(view, sandbox, root.id)
      assert_redirect(view, ~p"/projects/#{root.id}/w")

      assert collection_names(root) == ["parent-only"]
    end
  end

  describe "GitHub sync integration during merge" do
    setup do
      Mox.verify_on_exit!()
    end

    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          project_users: [%{user: user, role: :owner}]
        )

      workflow = insert(:simple_workflow, project: parent)
      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, parent: parent, sandbox: sandbox, snapshot: snapshot}
    end

    for sync_version <- [false, true] do
      test "commits to GitHub before and after the merge (sync_version: #{sync_version})",
           %{conn: conn, parent: parent, sandbox: sandbox, snapshot: snapshot} do
        repo_connection =
          insert(:project_repo_connection,
            project: parent,
            repo: "someaccount/somerepo",
            branch: "main",
            github_installation_id: "1234",
            sync_version: unquote(sync_version)
          )

        {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

        for message <- ["pre-merge commit", "Merged sandbox #{sandbox.name}"] do
          expect_create_installation_token(
            repo_connection.github_installation_id
          )

          expect_get_repo(repo_connection.repo)

          expect_create_workflow_dispatch_with_request_body(
            repo_connection.repo,
            "openfn-pull.yml",
            %{
              ref: "main",
              inputs: %{
                projectId: parent.id,
                apiSecretName: api_secret_name(parent),
                branch: repo_connection.branch,
                pathToConfig: path_to_config(repo_connection),
                commitMessage: message,
                snapshots: "#{snapshot.id}"
              }
            }
          )
        end

        merge(view, sandbox, parent.id)

        assert_redirect(view, ~p"/projects/#{parent.id}/w")
      end
    end

    test "does not commit to GitHub when the project has no GitHub sync",
         %{conn: conn, parent: parent, sandbox: sandbox} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      merge(view, sandbox, parent.id)

      assert_redirect(view, ~p"/projects/#{parent.id}/w")
    end

    defp api_secret_name(%{id: project_id}) do
      project_id
      |> String.replace("-", "_")
      |> then(&"OPENFN_#{&1}_API_KEY")
    end

    defp path_to_config(repo_connection) do
      Lightning.VersionControl.ProjectRepoConnection.config_path(repo_connection)
      |> Path.relative_to(".")
    end
  end
end

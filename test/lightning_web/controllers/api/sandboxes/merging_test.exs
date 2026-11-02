defmodule LightningWeb.API.Sandboxes.MergingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog
  import Lightning.RaceHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import LightningWeb.ApiSandboxesHelpers
  import Lightning.Factories

  alias Lightning.Projects.Project
  alias Lightning.Projects.Sandboxes
  alias Lightning.Repo
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow

  setup %{conn: conn} do
    owner = insert(:user, email: "owner@example.com")
    parent = insert(:project, project_users: [%{user: owner, role: :owner}])
    intake = insert(:simple_workflow, project: parent, name: "intake")

    {:ok, sandbox} = Sandboxes.provision(parent, owner, %{name: "staging"})

    reporting = insert(:simple_workflow, project: sandbox, name: "reporting")

    legacy =
      insert(:simple_workflow,
        project: parent,
        name: "legacy",
        inserted_at: DateTime.add(sandbox.inserted_at, -60)
      )

    # Made after the sandbox, so it was never in it.
    insert(:simple_workflow,
      project: parent,
      name: "since",
      inserted_at: DateTime.add(sandbox.inserted_at, 60)
    )

    credential = insert(:credential, name: "Acme DHIS2", user: owner)

    project_credential =
      insert(:project_credential, project: sandbox, credential: credential)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     owner: owner,
     parent: parent,
     sandbox: sandbox,
     intake: intake,
     reporting: reporting,
     legacy: legacy,
     credential: credential,
     project_credential: project_credential}
  end

  defp sandbox_workflow_id(sandbox, name),
    do: Repo.get_by!(Workflow, project_id: sandbox.id, name: name).id

  describe "previewing a merge" do
    test "answers what merging into the parent would do on a session token, pairing workflows by name and listing the credentials the parent lacks",
         ctx do
      conn =
        ctx.conn
        |> session_conn(ctx.owner)
        |> preview_merge(ctx.parent.id, ctx.sandbox.id)

      assert json_response(conn, 200) == %{
               "target_project_id" => ctx.parent.id,
               "workflows" => [
                 %{
                   "name" => "intake",
                   "source_workflow_id" =>
                     sandbox_workflow_id(ctx.sandbox, "intake"),
                   "target_workflow_id" => ctx.intake.id,
                   "change" => "unchanged",
                   "diverged" => false
                 },
                 %{
                   "name" => "legacy",
                   "source_workflow_id" => nil,
                   "target_workflow_id" => ctx.legacy.id,
                   "change" => "deleted",
                   "diverged" => false
                 },
                 %{
                   "name" => "reporting",
                   "source_workflow_id" => ctx.reporting.id,
                   "target_workflow_id" => nil,
                   "change" => "new",
                   "diverged" => false
                 }
               ],
               "credentials" => [
                 %{"credential_id" => ctx.credential.id, "name" => "Acme DHIS2"}
               ]
             }
    end

    test "a target the caller can't use, that is being deleted, that is the sandbox or one of its own, or that is in another workspace, answers 422 at target_project_id",
         ctx do
      %{conn: conn, owner: owner, sandbox: sandbox} = ctx

      nested =
        insert(:project,
          parent: sandbox,
          project_users: [%{user: owner, role: :owner}]
        )

      viewed = insert(:project, project_users: [%{user: owner, role: :viewer}])

      elsewhere =
        insert(:project, project_users: [%{user: owner, role: :editor}])

      scheduled = scheduled_project([%{user: owner, role: :owner}])
      caller = with_pat(conn, owner)

      for {target, entry} <- [
            {sandbox.id,
             {"not_allowed", "is the sandbox or one of its sandboxes"}},
            {nested.id,
             {"not_allowed", "is the sandbox or one of its sandboxes"}},
            {insert(:project).id, {"not_found", "names nothing you can see"}},
            {Ecto.UUID.generate(), {"not_found", "names nothing you can see"}},
            {viewed.id, {"no_access", "is a project you may not merge into"}},
            {scheduled.id, {"deleting", "is scheduled for deletion"}},
            {elsewhere.id,
             {"not_allowed", "is outside the sandbox's workspace"}},
            {"not-a-uuid", {"type", "is not a UUID"}}
          ] do
        {code, detail} = entry

        for send <- [&preview_merge/4, &merge_sandbox/4] do
          caller
          |> send.(ctx.parent.id, sandbox.id, %{"target_project_id" => target})
          |> assert_problem(422, :invalid, [
            %{
              "pointer" => "#/target_project_id",
              "code" => code,
              "detail" => detail
            }
          ])
        end
      end

      refute Repo.get_by(Workflow, project_id: ctx.parent.id, name: "reporting")
    end

    test "an unknown key answers 422", %{conn: conn, owner: owner} = ctx do
      conn
      |> with_pat(owner)
      |> preview_merge(ctx.parent.id, ctx.sandbox.id, %{"target" => "x"})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/target",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ])
    end
  end

  describe "merging" do
    test "copies the sandbox's workflows into its parent on a session token, answering 201 with the parent, and deletes nothing only the parent has",
         ctx do
      conn =
        ctx.conn
        |> session_conn(ctx.owner)
        |> merge_sandbox(ctx.parent.id, ctx.sandbox.id)

      url = "#{LightningWeb.Endpoint.url()}/api/projects/#{ctx.parent.id}"

      assert json_response(conn, 201) == %{
               "data" => %{
                 "type" => "projects",
                 "id" => ctx.parent.id,
                 "attributes" =>
                   Map.merge(default_settings(), %{
                     "name" => ctx.parent.name,
                     "description" => ctx.parent.description,
                     "members" => [
                       %{"email" => "owner@example.com", "role" => "owner"}
                     ]
                   }),
                 "relationships" => %{},
                 "links" => %{"self" => url}
               },
               "included" => [],
               "links" => %{
                 "self" => "#{url}/sandboxes/#{ctx.sandbox.id}/merges"
               }
             }

      names =
        Repo.all(
          from(w in Workflow,
            where: w.project_id == ^ctx.parent.id and is_nil(w.deleted_at),
            select: w.name,
            order_by: w.name
          )
        )

      assert names == ["intake", "legacy", "reporting", "since"]
    end

    test "workflow_ids limits the merge to those workflows, and one that isn't the sandbox's answers 422",
         ctx do
      caller = with_pat(ctx.conn, ctx.owner)

      caller
      |> merge_sandbox(ctx.parent.id, ctx.sandbox.id, %{
        "workflow_ids" => [ctx.intake.id, ctx.reporting.id, 7],
        "extra" => true
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/extra",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/workflow_ids/0",
          "code" => "not_found",
          "detail" => "names no workflow in the sandbox"
        },
        %{
          "pointer" => "#/workflow_ids/2",
          "code" => "not_found",
          "detail" => "names no workflow in the sandbox"
        }
      ])

      refute Repo.get_by(Workflow, project_id: ctx.parent.id, name: "reporting")

      caller
      |> merge_sandbox(ctx.parent.id, ctx.sandbox.id, %{
        "workflow_ids" => [sandbox_workflow_id(ctx.sandbox, "intake")]
      })
      |> json_response(201)

      refute Repo.get_by(Workflow, project_id: ctx.parent.id, name: "reporting")
    end

    test "a workflow_ids that isn't a list answers 422", ctx do
      ctx.conn
      |> with_pat(ctx.owner)
      |> merge_sandbox(ctx.parent.id, ctx.sandbox.id, %{"workflow_ids" => "all"})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/workflow_ids",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])

      refute Repo.get_by(Workflow, project_id: ctx.parent.id, name: "reporting")
    end

    test "links the sandbox's credentials the parent lacks, so a merged job keeps its credential",
         ctx do
      job = ctx.reporting |> Repo.preload(:jobs) |> Map.fetch!(:jobs) |> hd()

      job
      |> Ecto.Changeset.change(project_credential_id: ctx.project_credential.id)
      |> Repo.update!()

      ctx.conn
      |> with_pat(ctx.owner)
      |> merge_sandbox(ctx.parent.id, ctx.sandbox.id)
      |> json_response(201)

      merged =
        Repo.one!(
          from(j in Job,
            join: w in assoc(j, :workflow),
            join: pc in assoc(j, :project_credential),
            where: w.project_id == ^ctx.parent.id and w.name == "reporting",
            select: %{project_id: pc.project_id, credential_id: pc.credential_id}
          )
        )

      assert merged == %{
               project_id: ctx.parent.id,
               credential_id: ctx.credential.id
             }
    end

    test "a merge that fails for a reason of its own answers 500 and changes nothing",
         ctx do
      # A credential linked to neither project, which only a write around the
      # sandbox's own checks could leave on a job.
      foreign =
        insert(:project_credential,
          project: insert(:project),
          credential: insert(:credential, user: ctx.owner)
        )

      Repo.update_all(
        from(j in Job, where: j.workflow_id == ^ctx.reporting.id),
        set: [project_credential_id: foreign.id]
      )

      {conn, log} =
        with_log(fn ->
          ctx.conn
          |> with_pat(ctx.owner)
          |> merge_sandbox(ctx.parent.id, ctx.sandbox.id)
        end)

      assert_problem(conn, 500, :internal, [])
      assert log =~ "Sandbox merge failed."
      refute Repo.get_by(Workflow, project_id: ctx.parent.id, name: "reporting")
    end
  end

  describe "stale writes" do
    test "a target deleted just before the merge answers 409 and stays deleted",
         ctx do
      sibling =
        insert(:project,
          parent: ctx.parent,
          project_users: [%{user: ctx.owner, role: :owner}]
        )

      # The route reads the sandbox's credentials just before it merges.
      after_first_query("project_credentials", ctx.sandbox.id, fn _ ->
        id = Ecto.UUID.dump!(sibling.id)
        Repo.query!("DELETE FROM project_users WHERE project_id = $1", [id])
        Repo.query!("DELETE FROM projects WHERE id = $1", [id])
      end)

      ctx.conn
      |> with_pat(ctx.owner)
      |> merge_sandbox(ctx.parent.id, ctx.sandbox.id, %{
        "target_project_id" => sibling.id
      })
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.get(Project, sibling.id)
    end
  end
end

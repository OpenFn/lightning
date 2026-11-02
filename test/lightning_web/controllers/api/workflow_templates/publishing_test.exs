defmodule LightningWeb.API.WorkflowTemplates.PublishingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.RaceHelpers
  alias Lightning.Workflows
  alias Lightning.Workflows.WorkflowTemplate
  alias Lightning.Workflows.YamlFormat.V2

  setup %{conn: conn} do
    support = insert(:user, support_user: true)

    project =
      insert(:project, project_users: [%{user: support, role: :editor}])

    workflow =
      insert(:simple_workflow,
        name: "to publish",
        project: project,
        positions: %{"a" => %{"x" => 1, "y" => 2}}
      )

    %{
      conn:
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json"),
      support: support,
      project: project,
      workflow: workflow
    }
  end

  defp publish(conn, workflow_id, body),
    do:
      put(conn, ~p"/api/workflows/#{workflow_id}/template", Jason.encode!(body))

  defp saved_code(workflow) do
    {:ok, code} =
      workflow.id
      |> Workflows.get_workflow(include: [:edges, :jobs, :triggers])
      |> V2.serialize_workflow()

    code
  end

  describe "publishing" do
    test "a support user on a session token publishes the workflow as it is saved: 201 with the template",
         %{conn: conn, support: support, workflow: workflow} do
      conn =
        conn
        |> session_conn(support)
        |> publish(workflow.id, %{
          name: "DHIS2 to FHIR",
          description: "Moves events",
          tags: ["dhis2", "fhir"]
        })

      template = Repo.get_by!(WorkflowTemplate, workflow_id: workflow.id)

      assert json_response(conn, 201) == %{
               "template" => %{
                 "id" => template.id,
                 "name" => "DHIS2 to FHIR",
                 "description" => "Moves events",
                 "tags" => ["dhis2", "fhir"],
                 "workflow_id" => workflow.id,
                 "code" => saved_code(workflow)
               }
             }

      assert template.positions == %{"a" => %{"x" => 1, "y" => 2}}
    end

    test "publishing again replaces the workflow's one template: 200, with what the body leaves out cleared",
         %{conn: conn, support: support, workflow: workflow} do
      existing =
        insert(:workflow_template,
          workflow: workflow,
          workflow_id: workflow.id,
          name: "old",
          description: "old description",
          code: "old code",
          tags: ["old"]
        )

      conn =
        conn |> assign_bearer(support) |> publish(workflow.id, %{name: "new"})

      assert json_response(conn, 200) == %{
               "template" => %{
                 "id" => existing.id,
                 "name" => "new",
                 "description" => nil,
                 "tags" => [],
                 "workflow_id" => workflow.id,
                 "code" => saved_code(workflow)
               }
             }

      assert [%WorkflowTemplate{id: id}] = Repo.all(WorkflowTemplate)
      assert id == existing.id
    end

    test "a body it can't take answers 422 with every problem, an unknown key such as code among them, and publishes nothing",
         %{conn: conn, support: support, workflow: workflow} do
      conn =
        conn
        |> session_conn(support)
        |> publish(workflow.id, %{
          description: String.duplicate("d", 1001),
          tags: "dhis2",
          code: "my own yaml"
        })

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/code",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/description",
          "code" => "too_long",
          "detail" => "Description must be less than 1000 characters"
        },
        %{"pointer" => "#/tags", "code" => "type", "detail" => "is invalid"}
      ])

      refute Repo.exists?(WorkflowTemplate)
    end

    test "a body that isn't a JSON object answers 400 and publishes nothing",
         %{conn: conn, support: support, workflow: workflow} do
      conn
      |> session_conn(support)
      |> put(~p"/api/workflows/#{workflow.id}/template", "[1, 2]")
      |> assert_problem(400, :malformed, [])

      refute Repo.exists?(WorkflowTemplate)
    end

    test "publishing the same body again answers 200 and writes nothing",
         %{conn: conn, support: support, workflow: workflow} do
      body = %{name: "same", description: "unchanged", tags: ["dhis2"]}

      conn |> assign_bearer(support) |> publish(workflow.id, body)
      first = Repo.get_by!(WorkflowTemplate, workflow_id: workflow.id)

      # Any write would move updated_at off this mark.
      first =
        Repo.update!(
          Ecto.Changeset.change(first, updated_at: ~N[2000-01-01 00:00:00])
        )

      conn = conn |> assign_bearer(support) |> publish(workflow.id, body)

      assert json_response(conn, 200) == %{
               "template" => %{
                 "id" => first.id,
                 "name" => "same",
                 "description" => "unchanged",
                 "tags" => ["dhis2"],
                 "workflow_id" => workflow.id,
                 "code" => saved_code(workflow)
               }
             }

      assert Repo.reload!(first) == first
    end
  end

  describe "who may reach it" do
    test "only a support user who is a member, or whose project allows support access, may publish; anyone else gets 403 for every id",
         %{conn: conn, support: support, project: project, workflow: workflow} do
      owner = insert(:user)
      outside_support = insert(:user, support_user: true)
      short_of_mfa = insert(:user, support_user: true)
      insert(:project_user, project: project, user: owner, role: :owner)

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :editor}]
        )

      mfa_workflow = insert(:simple_workflow, project: mfa_project)
      open_project = insert(:project, allow_support_access: true)
      open_workflow = insert(:simple_workflow, project: open_project)
      elsewhere = insert(:simple_workflow)

      deleted =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      unknown = Ecto.UUID.generate()
      refused = {403, :forbidden, []}

      rows =
        for(
          caller <- [owner, outside_support],
          id <- [workflow.id, unknown, "not-a-uuid"],
          do: {caller, id, refused}
        ) ++
          for(
            id <- [mfa_workflow.id, unknown, "not-a-uuid"],
            do: {short_of_mfa, id, refused}
          ) ++
          [
            {support, unknown, refused},
            {support, "not-a-uuid", refused},
            {support, elsewhere.id, refused},
            {support, deleted.id, {404, :not_found, []}}
          ]

      for {caller, id, {status, code, entries}} <- rows do
        conn
        |> assign_bearer(caller)
        |> publish(id, %{name: "published"})
        |> assert_problem(status, code, entries)
      end

      refute Repo.exists?(WorkflowTemplate)

      conn
      |> assign_bearer(outside_support)
      |> publish(open_workflow.id, %{name: "published"})
      |> json_response(201)
    end
  end

  describe "stale writes" do
    test "a workflow another request deletes mid-publish answers 409 concurrent_edit and publishes nothing",
         %{conn: conn, support: support, workflow: workflow} do
      RaceHelpers.after_first_query("workflow_templates", workflow.id, fn id ->
        Repo.query!("DELETE FROM workflows WHERE id = $1", [id])
      end)

      conn
      |> session_conn(support)
      |> publish(workflow.id, %{name: "gone"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(workflow)
      refute Repo.exists?(WorkflowTemplate)
    end
  end
end

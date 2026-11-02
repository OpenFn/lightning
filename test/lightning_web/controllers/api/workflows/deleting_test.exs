defmodule LightningWeb.API.Workflows.DeletingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Auditing.Audit
  alias Lightning.RaceHelpers
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Trigger

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "deleting" do
    test "an editor on a session token marks the workflow deleted, disables its triggers, records it, and it leaves the list and GET",
         %{conn: conn} do
      editor = insert(:user)

      project =
        insert(:project, project_users: [%{user: editor, role: :editor}])

      workflow = insert(:simple_workflow, project: project)
      kept = insert(:simple_workflow, project: project)
      session = session_conn(conn, editor)

      conn =
        delete(session, ~p"/api/projects/#{project.id}/workflows/#{workflow.id}")

      assert conn.status == 204
      assert conn.resp_body == ""

      deleted = Repo.reload!(workflow)
      assert deleted.deleted_at
      assert deleted.name != workflow.name

      assert [%Trigger{enabled: false, custom_path: nil}] =
               Repo.all(from t in Trigger, where: t.workflow_id == ^workflow.id)

      assert [%Audit{actor_id: actor_id}] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^workflow.id and
                       a.event == "marked_for_deletion"
               )

      assert actor_id == editor.id

      listed =
        session
        |> get(~p"/api/projects/#{project.id}/workflows")
        |> json_response(200)

      assert Enum.map(listed["workflows"], & &1["id"]) == [kept.id]

      session
      |> get(~p"/api/projects/#{project.id}/workflows/#{workflow.id}")
      |> assert_problem(404, :not_found, [])
    end

    test "an owner, admin or editor may delete a workflow on a personal access token",
         %{conn: conn} do
      for role <- [:owner, :admin, :editor] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])
        workflow = insert(:simple_workflow, project: project)

        conn =
          conn
          |> assign_bearer(user)
          |> delete(~p"/api/projects/#{project.id}/workflows/#{workflow.id}")

        assert conn.status == 204, "expected #{role} to be allowed to delete"
        assert Repo.reload!(workflow).deleted_at
      end
    end

    test "a workflow open in the editor answers 409 being_edited and stays",
         %{conn: conn} do
      editor = insert(:user)

      project =
        insert(:project, project_users: [%{user: editor, role: :editor}])

      workflow = insert(:simple_workflow, project: project)
      Presence.track_user_presence(insert(:user), workflow, self())

      conn
      |> session_conn(editor)
      |> delete(~p"/api/projects/#{project.id}/workflows/#{workflow.id}")
      |> assert_problem(409, :being_edited, [])

      refute Repo.reload!(workflow).deleted_at
    end
  end

  describe "who may reach it" do
    test "a refused caller gets 403 for every id, a permitted one 404 for a workflow the project hasn't got and 400 for a malformed id, and nothing is deleted",
         %{conn: conn} do
      [editor, viewer, short_of_mfa, stranger] = insert_list(4, :user)
      superuser = insert(:user, role: :superuser)

      project =
        insert(:project,
          project_users: [
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :editor}]
        )

      scheduled =
        insert(:project,
          scheduled_deletion: DateTime.utc_now(),
          project_users: [%{user: editor, role: :editor}]
        )

      own = insert(:simple_workflow, project: project)
      mfa_own = insert(:simple_workflow, project: mfa_project)
      scheduled_own = insert(:simple_workflow, project: scheduled)
      elsewhere = insert(:simple_workflow)

      deleted =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      unknown = Ecto.UUID.generate()
      refused = {403, :forbidden, []}
      not_found = {404, :not_found, []}

      rows =
        for(
          caller <- [viewer, superuser],
          id <- [own.id, unknown, "not-a-uuid"],
          do: {caller, project.id, id, refused}
        ) ++
          for(
            id <- [own.id, unknown, "not-a-uuid", elsewhere.id],
            do: {stranger, project.id, id, refused}
          ) ++
          for(
            id <- [mfa_own.id, unknown, "not-a-uuid"],
            do: {short_of_mfa, mfa_project.id, id, refused}
          ) ++
          [
            {editor, unknown, unknown, refused},
            {superuser, unknown, unknown, not_found},
            {superuser, "not-a-uuid", unknown,
             {400, :invalid_parameter,
              [not_a_uuid_entry(%{"path" => "project_id"})]}},
            {editor, scheduled.id, scheduled_own.id,
             {409, :scheduled_for_deletion, []}},
            {editor, project.id, "not-a-uuid",
             {400, :invalid_parameter, [not_a_uuid_entry(%{"path" => "id"})]}},
            {editor, project.id, unknown, not_found},
            {editor, project.id, elsewhere.id, not_found},
            {editor, project.id, deleted.id, not_found}
          ]

      for {caller, pid, id, {status, code, entries}} <- rows do
        conn
        |> assign_bearer(caller)
        |> delete(~p"/api/projects/#{pid}/workflows/#{id}")
        |> assert_problem(status, code, entries)
      end

      for workflow <- [own, mfa_own, scheduled_own, elsewhere] do
        refute Repo.reload!(workflow).deleted_at
      end
    end
  end

  describe "stale writes" do
    test "a workflow another request deletes mid-delete answers 409 concurrent_edit and stays as that request left it",
         %{conn: conn} do
      editor = insert(:user)

      project =
        insert(:project, project_users: [%{user: editor, role: :editor}])

      workflow = insert(:simple_workflow, project: project)

      RaceHelpers.after_first_query("workflows", workflow.id, fn id ->
        Repo.query!(
          "UPDATE workflows SET deleted_at = now(), name = 'gone' WHERE id = $1",
          [id]
        )
      end)

      conn
      |> session_conn(editor)
      |> delete(~p"/api/projects/#{project.id}/workflows/#{workflow.id}")
      |> assert_problem(409, :concurrent_edit, [])

      assert Repo.reload!(workflow).name == "gone"

      refute Repo.exists?(
               from a in Audit,
                 where:
                   a.item_id == ^workflow.id and
                     a.event == "marked_for_deletion"
             )
    end
  end
end

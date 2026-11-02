defmodule LightningWeb.API.ProjectMembers.AddingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectMembersHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Extensions.Message

  setup %{conn: conn} do
    admin = insert(:user)
    owner = insert(:user)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin}
        ]
      )

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      admin: admin,
      project: project
    }
  end

  describe "adding a member" do
    test "an admin's session adds a user, answers 201 with the member, emails them and records who did it",
         %{conn: conn, admin: admin, project: project} do
      user = insert(:user)

      Oban.Testing.with_testing_mode(:manual, fn ->
        conn =
          conn
          |> session_conn(admin)
          |> put(
            member_path(project.id, user.id),
            Jason.encode!(%{"role" => "editor"})
          )

        assert json_response(conn, 201) == %{
                 "data" => member_json(project.id, user, :editor),
                 "included" => [],
                 "links" => %{
                   "self" =>
                     LightningWeb.Endpoint.url() <>
                       member_path(project.id, user.id)
                 }
               }

        assert [_email] = all_enqueued(worker: Lightning.Accounts.UserNotifier)
      end)

      assert role_of(project.id, user.id) == :editor
      assert audit_events(project.id) == [{"collaborator_added", admin.id}]
    end

    test "the service account adds a user without emailing them when told not to",
         %{conn: conn, project: project} do
      {conn, account} = with_service_account(conn, ["projects:write"])
      user = insert(:user)

      Oban.Testing.with_testing_mode(:manual, fn ->
        conn
        |> send_json(:put, member_path(project.id, user.id), %{
          "role" => "viewer",
          "notify" => false
        })
        |> json_response(201)

        assert all_enqueued(worker: Lightning.Accounts.UserNotifier) == []
      end)

      assert role_of(project.id, user.id) == :viewer
      assert audit_events(project.id) == [{"collaborator_added", account.uuid}]
    end

    test "a new member the plan has no seat for answers 402, after the body is checked",
         %{conn: conn, admin: admin, project: project} do
      user = insert(:user)

      for reason <- [:exceeds_limit, :too_many_users] do
        Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
          %{type: :new_user}, _context ->
            {:error, reason, %Message{text: "No more seats"}}
        end)

        conn
        |> with_pat(admin)
        |> send_json(:put, member_path(project.id, user.id), %{
          "role" => "editor"
        })
        |> assert_problem(402, :exceeds_limit, [])

        conn
        |> with_pat(admin)
        |> send_json(:put, member_path(project.id, user.id), %{
          "role" => "sideways"
        })
        |> assert_problem(422, :invalid)
      end

      refute role_of(project.id, user.id)
    end

    test "a user who doesn't exist answers 404", %{
      conn: conn,
      admin: admin,
      project: project
    } do
      conn
      |> with_pat(admin)
      |> send_json(:put, member_path(project.id, Ecto.UUID.generate()), %{
        "role" => "editor"
      })
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "changing a role" do
    test "changes a member's role and answers 200; the same body again writes nothing",
         %{conn: conn, admin: admin, project: project} do
      editor = insert(:user)
      insert(:project_user, project: project, user: editor, role: :editor)

      for _attempt <- 1..2 do
        conn
        |> with_pat(admin)
        |> send_json(:put, member_path(project.id, editor.id), %{
          "role" => "viewer"
        })
        |> json_response(200)
        |> Map.fetch!("data")
        |> then(&assert &1 == member_json(project.id, editor, :viewer))
      end

      assert role_of(project.id, editor.id) == :viewer

      assert audit_events(project.id) == [
               {"collaborator_role_changed", admin.id}
             ]
    end
  end

  describe "refusals" do
    test "a body it can't apply answers 422 with every problem and changes nothing",
         %{conn: conn, admin: admin, project: project} do
      user = insert(:user)

      [owner] =
        for %{role: :owner, user: owner} <- project.project_users, do: owner

      for {user_id, body, entries} <- [
            {user.id, %{"notify" => "loud", "colour" => "red"},
             [
               %{
                 "pointer" => "#/colour",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/notify",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/role",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {user.id, %{"role" => "sideways"},
             [
               %{
                 "pointer" => "#/role",
                 "code" => "not_allowed",
                 "detail" => "is invalid"
               }
             ]},
            {user.id, %{"role" => "owner"}, [one_owner()]},
            {owner.id, %{"role" => "admin"}, [one_owner()]}
          ] do
        conn
        |> with_pat(admin)
        |> send_json(:put, member_path(project.id, user_id), body)
        |> assert_problem(422, :invalid, entries)
      end

      conn
      |> with_pat(admin)
      |> send_json(:put, member_path(project.id, user.id), "[1]")
      |> assert_problem(400, :malformed, [])

      refute role_of(project.id, user.id)
      assert role_of(project.id, owner.id) == :owner
    end
  end

  describe "stale writes" do
    test "a project another request deletes mid-add answers 409 concurrent_edit",
         %{conn: conn, admin: admin, project: project} do
      user = insert(:user)
      delete_project_mid_save(project.id)

      conn
      |> with_pat(admin)
      |> send_json(:put, member_path(project.id, user.id), %{"role" => "editor"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Lightning.Repo.reload(project)
      refute role_of(project.id, user.id)
    end

    test "a member another request removes mid-change answers 409 concurrent_edit",
         %{conn: conn, admin: admin, project: project} do
      editor = insert(:user)

      project_user =
        insert(:project_user, project: project, user: editor, role: :editor)

      # After the route reads the membership, before it writes.
      after_first_query("project_users", editor.id, fn _user_id ->
        Lightning.Repo.delete!(project_user)
      end)

      conn
      |> with_pat(admin)
      |> send_json(:put, member_path(project.id, editor.id), %{
        "role" => "viewer"
      })
      |> assert_problem(409, :concurrent_edit, [])

      refute role_of(project.id, editor.id)
    end
  end

  defp one_owner do
    %{
      "pointer" => "#/role",
      "code" => "one_owner",
      "detail" =>
        "would change who owns the project, which has exactly one owner"
    }
  end
end

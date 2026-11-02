defmodule LightningWeb.API.ProjectMembers.InvitingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectMembersHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers

  alias Lightning.Accounts
  alias Lightning.Extensions.Message

  @invitee %{
    "email" => "new.person@example.com",
    "first_name" => "New",
    "last_name" => "Person",
    "role" => "editor"
  }

  setup %{conn: conn} do
    [owner, admin, editor] = insert_list(3, :user)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor}
        ]
      )

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      admin: admin,
      editor: editor,
      project: project
    }
  end

  describe "inviting" do
    test "an admin's session creates the user, adds them, emails them a link to set their password, and answers 201 with the member",
         %{conn: conn, admin: admin, project: project} do
      conn =
        conn
        |> session_conn(admin)
        |> post(
          ~p"/api/projects/#{project}/invitations",
          Jason.encode!(@invitee)
        )

      user = Accounts.get_user_by_email("new.person@example.com")

      assert json_response(conn, 201) == %{
               "data" => member_json(project.id, user, :editor),
               "included" => [],
               "links" => %{
                 "self" =>
                   "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/invitations"
               }
             }

      assert {user.first_name, user.last_name} == {"New", "Person"}
      assert role_of(project.id, user.id) == :editor
      assert audit_events(project.id) == [{"collaborator_added", admin.id}]

      assert_received {:email,
                       %{
                         subject: "Join " <> _project,
                         to: [{_name, "new.person@example.com"}],
                         text_body: text_body
                       }}

      assert text_body =~ "#{admin.first_name} has invited you to join project"
      assert text_body =~ "/users/reset_password/"
    end

    test "a new member the plan has no seat for answers 402, after the body is checked, and creates no one",
         %{conn: conn, admin: admin, project: project} do
      for reason <- [:exceeds_limit, :too_many_users] do
        Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
          %{type: :new_user}, _context ->
            {:error, reason, %Message{text: "No more seats"}}
        end)

        conn
        |> with_pat(admin)
        |> send_json(:post, ~p"/api/projects/#{project}/invitations", @invitee)
        |> assert_problem(402, :exceeds_limit, [])

        conn
        |> with_pat(admin)
        |> send_json(
          :post,
          ~p"/api/projects/#{project}/invitations",
          Map.put(@invitee, "role", "sideways")
        )
        |> assert_problem(422, :invalid)
      end

      refute Accounts.get_user_by_email("new.person@example.com")
    end
  end

  describe "refusals" do
    test "a body it can't apply answers 422 with every problem, naming nothing about an account that has the email",
         %{conn: conn, admin: admin, editor: editor, project: project} do
      for {body, entries} <- [
            {%{"email" => String.upcase(editor.email), "colour" => "red"},
             [
               %{
                 "pointer" => "#/colour",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/email",
                 "code" => "taken",
                 "detail" => "has already been taken"
               },
               %{
                 "pointer" => "#/first_name",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/last_name",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/role",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {Map.merge(@invitee, %{"email" => "not an email", "role" => "owner"}),
             [
               %{
                 "pointer" => "#/email",
                 "code" => "format",
                 "detail" => "must be a valid email address"
               },
               %{
                 "pointer" => "#/role",
                 "code" => "one_owner",
                 "detail" =>
                   "would change who owns the project, which has exactly one owner"
               }
             ]}
          ] do
        conn
        |> with_pat(admin)
        |> send_json(:post, ~p"/api/projects/#{project}/invitations", body)
        |> assert_problem(422, :invalid, entries)
        |> then(&refute(inspect(&1) =~ editor.id))
      end

      conn
      |> with_pat(admin)
      |> send_json(:post, ~p"/api/projects/#{project}/invitations", "[1]")
      |> assert_problem(400, :malformed, [])

      assert role_of(project.id, editor.id) == :editor
    end

    test "an editor and a stranger are refused 403, whether or not the project exists",
         %{conn: conn, editor: editor, project: project} do
      callers = [with_pat(conn, editor), with_pat(conn, insert(:user))]

      for caller <- callers,
          project_id <- [project.id, Ecto.UUID.generate(), "not-a-uuid"] do
        caller
        |> send_json(:post, "/api/projects/#{project_id}/invitations", @invitee)
        |> assert_problem(403, :forbidden, [])
      end

      refute Accounts.get_user_by_email("new.person@example.com")
    end

    test "a superuser gets 400 for a project id that isn't a UUID, and 404 for one that names no project",
         %{conn: conn} do
      conn = with_pat(conn, insert(:user, role: :superuser))

      conn
      |> send_json(
        :post,
        "/api/projects/#{Ecto.UUID.generate()}/invitations",
        @invitee
      )
      |> assert_problem(404, :not_found, [])

      conn
      |> send_json(:post, "/api/projects/not-a-uuid/invitations", @invitee)
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "project_id"})
      ])
    end

    test "a member short of the project's MFA requirement, and a project scheduled for deletion, are refused",
         %{conn: conn, admin: admin} do
      short_of_mfa = insert(:user, mfa_enabled: false)

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :owner}]
        )

      for project_id <- [mfa_project.id, Ecto.UUID.generate(), "not-a-uuid"] do
        conn
        |> with_pat(short_of_mfa)
        |> send_json(:post, "/api/projects/#{project_id}/invitations", @invitee)
        |> assert_problem(403, :forbidden, [])
      end

      scheduled = scheduled_project([%{user: admin, role: :admin}])

      conn
      |> with_pat(admin)
      |> send_json(:post, ~p"/api/projects/#{scheduled}/invitations", @invitee)
      |> assert_problem(409, :scheduled_for_deletion, [])
    end
  end

  describe "stale writes" do
    test "a project another request deletes mid-invite answers 409 concurrent_edit and creates no one",
         %{conn: conn, admin: admin, project: project} do
      delete_project_mid_save(project.id)

      conn
      |> with_pat(admin)
      |> send_json(:post, ~p"/api/projects/#{project}/invitations", @invitee)
      |> assert_problem(409, :concurrent_edit, [])

      refute Lightning.Repo.reload(project)
      refute Accounts.get_user_by_email("new.person@example.com")
    end
  end
end

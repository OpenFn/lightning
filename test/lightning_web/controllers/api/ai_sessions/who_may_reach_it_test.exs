defmodule LightningWeb.API.AiSessions.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.AiSessionHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  setup do
    %{project: project, workflow: workflow, user: user} = member = ai_member()

    session =
      workflow_session(project, workflow, user, [
        %{role: :user, status: :error, user: user}
      ])

    [message] = session.messages
    Map.merge(member, %{session: session, message: message})
  end

  @message %{"content" => "Hi"}
  @start %{"kind" => "workflow", "message" => @message}

  # Each route, given the id the path names.
  defp project_routes(conn, id) do
    [
      get(
        conn,
        "/api/projects/#{id}/ai_sessions?workflow_id=#{Ecto.UUID.generate()}"
      ),
      post(conn, "/api/projects/#{id}/ai_sessions", @start)
    ]
  end

  defp session_routes(conn, id, message_id) do
    [
      get(conn, "/api/ai_sessions/#{id}"),
      post(conn, "/api/ai_sessions/#{id}/messages", @message),
      post(conn, "/api/ai_sessions/#{id}/messages/#{message_id}/retries")
    ]
  end

  defp unmet_mfa_member(project) do
    user = insert(:user, mfa_enabled: false)
    insert(:project_user, project: project, user: user, role: :owner)
    Repo.update!(Ecto.Changeset.change(project, requires_mfa: true))
    user
  end

  describe "who may reach it" do
    test "a person with no standing, or without the MFA the project requires, is refused 403 for a session or project that exists, is unknown, or has an id that isn't a UUID",
         %{project: project, session: session, message: message} do
      stranger = insert(:user)
      unmet_mfa = unmet_mfa_member(insert(:project))
      Repo.update!(Ecto.Changeset.change(project, requires_mfa: true))
      mfa_project_member = unmet_mfa_member(project)

      for user <- [stranger, unmet_mfa, mfa_project_member],
          project_id <- [project.id, Ecto.UUID.generate(), "nope"] do
        conn = session_conn(build_conn(), user)

        for refused <- project_routes(conn, project_id),
            do: assert_problem(refused, 403, :forbidden, [])
      end

      for user <- [stranger, mfa_project_member],
          {id, message_id} <- [
            {session.id, message.id},
            {Ecto.UUID.generate(), Ecto.UUID.generate()},
            {"nope", "nope"}
          ] do
        conn = session_conn(build_conn(), user)

        for refused <- session_routes(conn, id, message_id),
            do: assert_problem(refused, 403, :forbidden, [])
      end
    end

    test "a member is refused 403 for a project that is unknown or isn't a UUID, and a superuser hears 404 and 400",
         %{conn: conn} do
      for project_id <- [Ecto.UUID.generate(), "nope"],
          refused <- project_routes(conn, project_id),
          do: assert_problem(refused, 403, :forbidden, [])

      superuser = session_conn(build_conn(), insert(:user, role: :superuser))

      for missing <- project_routes(superuser, Ecto.UUID.generate()),
          do: assert_problem(missing, 404, :not_found, [])

      for invalid <- project_routes(superuser, "nope"),
          do:
            assert_problem(invalid, 400, :invalid_parameter, [
              not_a_uuid_entry(%{"path" => "project_id"})
            ])
    end

    test "a session's project comes from the session, so an unknown session, or one whose id isn't a UUID, is 403 to its members too",
         %{conn: conn} do
      for id <- [Ecto.UUID.generate(), "nope"],
          refused <- session_routes(conn, id, Ecto.UUID.generate()),
          do: assert_problem(refused, 403, :forbidden, [])
    end

    test "a member retrying hears 404 for a message not in the session, or cancelled, and 400 for one whose id isn't a UUID",
         %{
           conn: conn,
           project: project,
           workflow: workflow,
           user: user,
           session: session
         } do
      other =
        workflow_session(project, workflow, user, [
          %{role: :user, status: :error}
        ])

      [elsewhere] = other.messages

      cancelled =
        insert(:chat_message,
          chat_session: session,
          role: :user,
          status: :cancelled
        )

      for message_id <- [Ecto.UUID.generate(), elsewhere.id, cancelled.id] do
        conn
        |> post(
          ~p"/api/ai_sessions/#{session.id}/messages/#{message_id}/retries"
        )
        |> assert_problem(404, :not_found, [])
      end

      conn
      |> post("/api/ai_sessions/#{session.id}/messages/nope/retries")
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "message_id"})
      ])
    end

    test "a project scheduled for deletion answers its members 409", %{
      conn: conn,
      project: project,
      session: session,
      message: message
    } do
      Repo.update!(
        Ecto.Changeset.change(project,
          scheduled_deletion: DateTime.utc_now(:second)
        )
      )

      for answer <-
            project_routes(conn, project.id) ++
              session_routes(conn, session.id, message.id),
          do: assert_problem(answer, 409, :scheduled_for_deletion, [])
    end
  end
end

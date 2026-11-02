defmodule LightningWeb.API.ProjectMembers.NotificationsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectMembersHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers

  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo

  setup %{conn: conn} do
    [owner, viewer] = insert_list(2, :user)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: viewer, role: :viewer}
        ]
      )

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      owner: owner,
      viewer: viewer,
      project: project
    }
  end

  describe "setting your notifications" do
    test "a viewer's session sets both of their own and answers with the member",
         %{conn: conn, viewer: viewer, project: project} do
      conn =
        conn
        |> session_conn(viewer)
        |> put(
          notifications_path(project, viewer),
          Jason.encode!(%{"failure_alert" => true, "digest" => "weekly"})
        )

      assert json_response(conn, 200) == %{
               "data" =>
                 member_json(project.id, viewer, :viewer,
                   failure_alert: true,
                   digest: :weekly
                 ),
               "included" => [],
               "links" => %{
                 "self" =>
                   LightningWeb.Endpoint.url() <>
                     notifications_path(project, viewer)
               }
             }

      assert %{failure_alert: true, digest: :weekly} =
               membership(project, viewer)
    end

    test "the same body again answers the same and changes nothing", %{
      conn: conn,
      viewer: viewer,
      project: project
    } do
      before = membership(project, viewer)

      conn
      |> with_pat(viewer)
      |> send_json(:put, notifications_path(project, viewer), %{
        "failure_alert" => false,
        "digest" => "never"
      })
      |> json_response(200)
      |> then(&assert &1["data"] == member_json(project.id, viewer, :viewer))

      assert membership(project, viewer).updated_at == before.updated_at
    end
  end

  describe "refusals" do
    test "another member's notifications are 403, whatever the caller's role and whether or not that member exists",
         %{conn: conn, owner: owner, viewer: viewer, project: project} do
      for {caller, user_id} <- [
            {owner, viewer.id},
            {viewer, owner.id},
            {owner, Ecto.UUID.generate()}
          ] do
        conn
        |> with_pat(caller)
        |> send_json(:put, notifications_path(project, user_id), %{
          "failure_alert" => true,
          "digest" => "daily"
        })
        |> assert_problem(403, :forbidden, [])
      end

      assert %{failure_alert: false, digest: :never} =
               membership(project, viewer)
    end

    test "a body it can't apply answers 422 with every problem, and one that isn't an object 400",
         %{conn: conn, viewer: viewer, project: project} do
      for {body, entries} <- [
            {%{},
             [
               %{
                 "pointer" => "#/digest",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/failure_alert",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{"failure_alert" => "often", "digest" => "hourly", "email" => "x"},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/digest",
                 "code" => "not_allowed",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/failure_alert",
                 "code" => "type",
                 "detail" => "is invalid"
               }
             ]}
          ] do
        conn
        |> with_pat(viewer)
        |> send_json(:put, notifications_path(project, viewer), body)
        |> assert_problem(422, :invalid, entries)
      end

      conn
      |> with_pat(viewer)
      |> send_json(:put, notifications_path(project, viewer), "[1]")
      |> assert_problem(400, :malformed, [])
    end
  end

  describe "stale writes" do
    test "a membership another request removes mid-write answers 409 concurrent_edit",
         %{conn: conn, viewer: viewer, project: project} do
      project_user = membership(project, viewer)

      after_first_query("project_users", viewer.id, fn _user_id ->
        Repo.delete!(project_user)
      end)

      conn
      |> with_pat(viewer)
      |> send_json(:put, notifications_path(project, viewer), %{
        "failure_alert" => true,
        "digest" => "daily"
      })
      |> assert_problem(409, :concurrent_edit, [])

      refute role_of(project.id, viewer.id)
    end
  end

  defp notifications_path(project, %{id: user_id}),
    do: notifications_path(project, user_id)

  defp notifications_path(project, user_id),
    do: ~p"/api/projects/#{project}/members/#{user_id}/notifications"

  defp membership(project, user),
    do: Repo.get_by!(ProjectUser, project_id: project.id, user_id: user.id)
end

defmodule LightningWeb.API.ChannelRequests.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  defp recorded_in(project) do
    channel = insert(:channel, project: project)

    insert(:channel_request,
      channel: channel,
      channel_snapshot: insert(:channel_snapshot, channel: channel)
    )
  end

  test "a project's requests are listed to its members, and refused with the same 403 to anyone else",
       %{conn: conn} do
    c = callers()
    pat = &with_pat(conn, &1)
    list = &"/api/projects/#{&1}/channel_requests"

    for {user, project_id, status, code, entries} <- [
          {c.stranger, c.project.id, 403, :forbidden, []},
          {c.superuser, c.project.id, 403, :forbidden, []},
          {c.short_of_mfa, c.mfa_project.id, 403, :forbidden, []},
          {c.stranger, c.scheduled.id, 403, :forbidden, []},
          {c.owner, Ecto.UUID.generate(), 403, :forbidden, []},
          {c.owner, "not-a-uuid", 403, :forbidden, []},
          {c.superuser, Ecto.UUID.generate(), 404, :not_found, []},
          {c.superuser, "not-a-uuid", 400, :invalid_parameter,
           [not_a_uuid_entry(%{"path" => "project_id"})]}
        ] do
      user
      |> then(pat)
      |> get(list.(project_id))
      |> assert_problem(status, code, entries)
    end

    for user <- [c.owner, c.admin, c.editor, c.viewer] do
      assert %{"data" => []} =
               user
               |> then(pat)
               |> get(list.(c.project.id))
               |> json_response(200)
    end
  end

  test "a request is read by a member of its project, and anyone else gets the same 403 whether it exists, is missing or isn't a UUID",
       %{conn: conn} do
    c = callers()
    pat = &with_pat(conn, &1)
    in_project = recorded_in(c.project)
    in_mfa_project = recorded_in(c.mfa_project)
    in_scheduled = recorded_in(c.scheduled)

    for {user, request_id} <-
          [
            {c.stranger, in_project.id},
            {c.superuser, in_project.id},
            {c.short_of_mfa, in_mfa_project.id},
            {c.stranger, in_scheduled.id}
          ] ++
            for(
              user <- [c.owner, c.superuser, c.stranger],
              id <- [Ecto.UUID.generate(), "not-a-uuid"],
              do: {user, id}
            ) do
      user
      |> then(pat)
      |> get("/api/channel_requests/#{request_id}")
      |> assert_problem(403, :forbidden, [])
    end

    for user <- [c.owner, c.admin, c.editor, c.viewer] do
      assert %{"data" => %{"id" => id}} =
               user
               |> then(pat)
               |> get("/api/channel_requests/#{in_project.id}")
               |> json_response(200)

      assert id == in_project.id
    end
  end

  test "an owner of a project scheduled for deletion gets 409 listing or reading its requests",
       %{conn: conn} do
    user = insert(:user)

    project =
      insert(:project,
        project_users: [%{user: user, role: :owner}],
        scheduled_deletion: now()
      )

    request = recorded_in(project)
    conn = with_pat(conn, user)

    for path <- [
          "/api/projects/#{project.id}/channel_requests",
          "/api/channel_requests/#{request.id}"
        ] do
      conn |> get(path) |> assert_problem(409, :scheduled_for_deletion, [])
    end
  end
end

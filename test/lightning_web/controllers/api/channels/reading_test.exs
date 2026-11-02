defmodule LightningWeb.API.Channels.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.SessionHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  defp base, do: LightningWeb.Endpoint.url()

  defp resource(channel, attributes) do
    %{
      "type" => "channels",
      "id" => channel.id,
      "attributes" =>
        Map.merge(
          %{
            "name" => channel.name,
            "destination_url" => channel.destination_url,
            "enabled" => channel.enabled,
            "lock_version" => channel.lock_version,
            "url" => "#{base()}/channels/#{channel.id}",
            "client_auth_method_ids" => [],
            "destination_credential_id" => nil,
            "request_count" => 0,
            "last_activity" => nil,
            "inserted_at" => DateTime.to_iso8601(channel.inserted_at),
            "updated_at" => DateTime.to_iso8601(channel.updated_at)
          },
          attributes
        ),
      "relationships" => %{},
      "links" => %{
        "self" =>
          "#{base()}/api/projects/#{channel.project_id}/channels/#{channel.id}"
      }
    }
  end

  defp request(channel, started_at) do
    snapshot =
      insert(:channel_snapshot,
        channel: channel,
        lock_version: System.unique_integer([:positive])
      )

    insert(:channel_request,
      channel: channel,
      channel_snapshot: snapshot,
      started_at: started_at
    )
  end

  defp with_auth(project) do
    channel = insert(:channel, project: project, name: "with-auth")
    auth_method = insert(:webhook_auth_method, project: project)
    project_credential = insert(:project_credential, project: project)

    insert(:channel_auth_method,
      channel: channel,
      webhook_auth_method: auth_method
    )

    insert(:channel_auth_method,
      channel: channel,
      role: :destination,
      webhook_auth_method: nil,
      project_credential: project_credential
    )

    {channel, auth_method, project_credential}
  end

  test "a viewer on a session token lists the project's channels by name, with their stats and the project's totals",
       %{conn: conn} do
    viewer = insert(:user)
    project = insert(:project, project_users: [%{user: viewer, role: :viewer}])
    {with_auth, auth_method, project_credential} = with_auth(project)
    busy = insert(:channel, project: project, name: "busy")
    earlier = ~U[2026-01-01 00:00:00.000000Z]
    latest = ~U[2026-01-02 00:00:00.000000Z]
    request(busy, earlier)
    request(busy, latest)
    insert(:channel, name: "elsewhere")

    conn =
      conn
      |> session_conn(viewer)
      |> get(~p"/api/projects/#{project.id}/channels")

    page =
      "#{base()}/api/projects/#{project.id}/channels?page=1&page_size=10"

    assert json_response(conn, 200) == %{
             "data" => [
               resource(busy, %{
                 "request_count" => 2,
                 "last_activity" => DateTime.to_iso8601(latest)
               }),
               resource(with_auth, %{
                 "client_auth_method_ids" => [auth_method.id],
                 "destination_credential_id" => project_credential.credential_id
               })
             ],
             "links" => %{
               "self" => page,
               "first" => page,
               "last" => page,
               "next" => nil,
               "prev" => nil
             },
             "meta" => %{"total_channels" => 2, "total_requests" => 2}
           }
  end

  test "pages the list, with the whole project's totals on every page", %{
    conn: conn
  } do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user}])

    [first, second] =
      for name <- ~w(a b), do: insert(:channel, project: project, name: name)

    request(first, DateTime.utc_now())

    conn =
      conn
      |> with_pat(user)
      |> get(~p"/api/projects/#{project.id}/channels?page=2&page_size=1")

    body = json_response(conn, 200)
    url = &"#{base()}/api/projects/#{project.id}/channels?page=#{&1}&page_size=1"

    assert Enum.map(body["data"], & &1["id"]) == [second.id]

    assert body["links"] == %{
             "self" => url.(2),
             "first" => url.(1),
             "last" => url.(2),
             "next" => nil,
             "prev" => url.(1)
           }

    assert body["meta"] == %{"total_channels" => 2, "total_requests" => 1}
  end

  test "a member reads a channel, with its auth methods and stats", %{
    conn: conn
  } do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :viewer}])
    {channel, auth_method, project_credential} = with_auth(project)
    started_at = ~U[2026-01-01 00:00:00.000000Z]
    request(channel, started_at)

    for conn <- [with_pat(conn, user), session_conn(build_conn(), user)] do
      read = get(conn, ~p"/api/projects/#{project.id}/channels/#{channel.id}")

      assert json_response(read, 200) == %{
               "data" =>
                 resource(channel, %{
                   "client_auth_method_ids" => [auth_method.id],
                   "destination_credential_id" =>
                     project_credential.credential_id,
                   "request_count" => 1,
                   "last_activity" => DateTime.to_iso8601(started_at)
                 })
             }
    end
  end
end

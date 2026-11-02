defmodule LightningWeb.API.ChannelRequests.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :viewer}])
    channel = insert(:channel, project: project)
    snapshot = insert(:channel_snapshot, channel: channel, name: "at-the-time")
    %{user: user, project: project, channel: channel, snapshot: snapshot}
  end

  defp base, do: LightningWeb.Endpoint.url()

  defp record(channel, snapshot, attrs \\ []) do
    insert(
      :channel_request,
      Keyword.merge([channel: channel, channel_snapshot: snapshot], attrs)
    )
  end

  defp entry(request, attributes) do
    %{
      "type" => "channel_requests",
      "id" => request.id,
      "attributes" =>
        Map.merge(
          %{
            "channel_id" => request.channel_id,
            "request_id" => request.request_id,
            "state" => to_string(request.state),
            "path" => nil,
            "error_message" => nil,
            "started_at" => DateTime.to_iso8601(request.started_at),
            "completed_at" => nil
          },
          attributes
        ),
      "relationships" => %{},
      "links" => %{"self" => "#{base()}/api/channel_requests/#{request.id}"}
    }
  end

  describe "listing" do
    test "a member on a session token lists the project's requests newest first, with each one's path or error",
         %{user: user, project: project, channel: channel, snapshot: snapshot} do
      older =
        record(channel, snapshot,
          state: :success,
          started_at: ~U[2026-01-01 00:00:00.000000Z],
          completed_at: ~U[2026-01-01 00:00:01.000000Z]
        )

      insert(:channel_event, channel_request: older, request_path: "/ok")

      newer =
        record(channel, snapshot,
          state: :error,
          started_at: ~U[2026-01-02 00:00:00.000000Z]
        )

      insert(:channel_error_event,
        channel_request: newer,
        request_path: "/down",
        error_message: "econnrefused"
      )

      other = insert(:channel)
      record(other, insert(:channel_snapshot, channel: other))

      conn =
        build_conn()
        |> session_conn(user)
        |> get(~p"/api/projects/#{project.id}/channel_requests")

      page =
        "#{base()}/api/projects/#{project.id}/channel_requests?page=1&page_size=10"

      assert json_response(conn, 200) == %{
               "data" => [
                 entry(newer, %{
                   "path" => "/down",
                   "error_message" => "econnrefused"
                 }),
                 entry(older, %{
                   "path" => "/ok",
                   "completed_at" => "2026-01-01T00:00:01.000000Z"
                 })
               ],
               "links" => %{
                 "self" => page,
                 "first" => page,
                 "last" => page,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "narrows the list to one channel, paging it", %{
      conn: conn,
      user: user,
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      second = insert(:channel, project: project)
      record(second, insert(:channel_snapshot, channel: second))

      [_newest, middle, _oldest] =
        for day <- [3, 2, 1],
            do:
              record(channel, snapshot,
                started_at: DateTime.new!(Date.new!(2026, 1, day), ~T[00:00:00])
              )

      conn =
        conn
        |> with_pat(user)
        |> get(
          ~p"/api/projects/#{project.id}/channel_requests?channel_id=#{channel.id}&page=2&page_size=1"
        )

      body = json_response(conn, 200)

      url =
        &"#{base()}/api/projects/#{project.id}/channel_requests?channel_id=#{channel.id}&page=#{&1}&page_size=1"

      assert Enum.map(body["data"], & &1["id"]) == [middle.id]

      assert body["links"] == %{
               "self" => url.(2),
               "first" => url.(1),
               "last" => url.(3),
               "next" => url.(3),
               "prev" => url.(1)
             }
    end

    test "answers 400 invalid_parameter for a channel_id that isn't a UUID", %{
      conn: conn,
      user: user,
      project: project
    } do
      conn
      |> with_pat(user)
      |> get(~p"/api/projects/#{project.id}/channel_requests?channel_id=nope")
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"parameter" => "channel_id"})
      ])
    end
  end

  describe "reading one" do
    test "a member reads a request with what the channel did with it", %{
      conn: conn,
      user: user,
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      auth_method = insert(:webhook_auth_method, project: project, name: "key")

      project_credential =
        insert(:project_credential,
          project: project,
          credential: build(:credential, name: "dhis2")
        )

      request =
        record(channel, snapshot,
          state: :success,
          client_identity: "10.0.0.1",
          client_auth_type: "api",
          client_webhook_auth_method: auth_method,
          destination_credential: project_credential
        )

      event =
        insert(:channel_event,
          channel_request: request,
          request_query_string: "a=1",
          queue_us: 10,
          connect_us: 20
        )

      for conn <- [with_pat(conn, user), session_conn(build_conn(), user)] do
        read = get(conn, ~p"/api/channel_requests/#{request.id}")

        assert json_response(read, 200) == %{
                 "data" =>
                   entry(request, %{
                     "path" => "/api/v1/data",
                     "client_identity" => "10.0.0.1",
                     "client_auth" => %{
                       "type" => "api",
                       "method_id" => auth_method.id,
                       "method_name" => "key"
                     },
                     "destination_credential" => %{
                       "id" => project_credential.id,
                       "name" => "dhis2"
                     },
                     "channel_snapshot" => %{
                       "name" => "at-the-time",
                       "destination_url" => snapshot.destination_url,
                       "lock_version" => snapshot.lock_version
                     },
                     "request" => %{
                       "method" => "POST",
                       "path" => "/api/v1/data",
                       "query_string" => "a=1",
                       "headers" => [
                         ["content-type", "application/json"],
                         ["authorization", "[REDACTED]"]
                       ],
                       "body" => event.request_body_preview,
                       "body_size" => 15
                     },
                     "response" => %{
                       "status" => 200,
                       "headers" => [["content-type", "application/json"]],
                       "body" => event.response_body_preview,
                       "body_size" => 15
                     },
                     "error_category" => nil,
                     "timing" => %{
                       "latency_us" => 350_000,
                       "queue_us" => 10,
                       "connect_us" => 20,
                       "request_send_us" => 5000,
                       "ttfb_us" => 280_000,
                       "response_duration_us" => 65_000
                     },
                     "wiped" => false
                   })
               }
      end
    end

    test "names nothing for an open channel, a deleted method or credential, and nothing it didn't send",
         %{
           conn: conn,
           user: user,
           project: project,
           channel: channel,
           snapshot: snapshot
         } do
      open = record(channel, snapshot, is_wiped: true, client_identity: nil)
      auth_method = insert(:webhook_auth_method, project: project)
      project_credential = insert(:project_credential, project: project)

      gone =
        record(channel, snapshot,
          client_auth_type: "basic",
          client_webhook_auth_method: auth_method,
          destination_credential: project_credential
        )

      # Deleting either clears the request's reference to it.
      Lightning.Repo.delete!(auth_method)
      Lightning.Repo.delete!(project_credential)

      insert(:channel_error_event,
        channel_request: gone,
        request_headers: nil,
        error_message: "credential_environment_not_found"
      )

      conn = with_pat(conn, user)

      for {request, expected} <- [
            {open,
             %{
               "client_identity" => nil,
               "client_auth" => %{
                 "type" => nil,
                 "method_id" => nil,
                 "method_name" => nil
               },
               "destination_credential" => nil,
               "request" => nil,
               "response" => nil,
               "error_category" => nil,
               "timing" => nil,
               "wiped" => true
             }},
            {gone,
             %{
               "client_auth" => %{
                 "type" => "basic",
                 "method_id" => nil,
                 "method_name" => nil
               },
               "destination_credential" => nil,
               "error_category" => "credential",
               "wiped" => false
             }}
          ] do
        attributes =
          conn
          |> get(~p"/api/channel_requests/#{request.id}")
          |> json_response(200)
          |> get_in(["data", "attributes"])

        assert Map.take(attributes, Map.keys(expected)) == expected
      end
    end
  end
end

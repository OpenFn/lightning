defmodule LightningWeb.ChannelRequestLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Channels
  alias LightningWeb.ChannelRequestLive.Helpers

  setup :stub_rate_limiter_ok

  # The page is drawn by React from data-props. What it renders from them
  # (the summary, the humanised errors, the timing phases and TTFB marker,
  # the body states, the config-changed pill, the wiped notice for each
  # role) is tested in the design system's ChannelRequestShowPage.test.tsx,
  # and the error wording in channelHelpers.test.ts. These tests cover the
  # gates and what the server sends.
  @page "#channel-request-show-page"

  defp enable_experimental_features(%{user: user}) do
    Lightning.Accounts.update_user_preferences(user, %{
      "experimental_features" => true
    })

    :ok
  end

  defp create_channel_request(project, attrs \\ %{}) do
    attrs = Map.new(attrs)

    channel =
      Map.get_lazy(attrs, :channel, fn ->
        insert(:channel, project: project)
      end)

    {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

    request =
      insert(:channel_request,
        channel: channel,
        channel_snapshot: snapshot,
        state: Map.get(attrs, :state, :success),
        client_identity: Map.get(attrs, :client_identity, "192.168.1.1"),
        client_auth_type: Map.get(attrs, :client_auth_type, "api"),
        is_wiped: Map.get(attrs, :is_wiped, false),
        started_at: Map.get(attrs, :started_at, ~U[2026-04-10 10:00:00.000000Z]),
        completed_at:
          Map.get(attrs, :completed_at, ~U[2026-04-10 10:00:00.350000Z])
      )

    {request, channel, snapshot}
  end

  defp detail_path(project, request) do
    ~p"/projects/#{project.id}/history/channels/#{request.id}"
  end

  defp props(conn, project, request) do
    {:ok, view, _html} = live(conn, detail_path(project, request))
    page_props(view, @page)
  end

  defp event(props), do: List.first(props["request"]["events"])

  describe "feature gate" do
    setup [:register_and_log_in_user, :create_project_for_current_user]

    test "redirects when experimental features are disabled", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} = create_channel_request(project)

      assert {:error, {:redirect, _}} =
               live(conn, detail_path(project, request))
    end
  end

  describe "detail page — success state" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "sends the summary, the headers as stored and the body previews", %{
      conn: conn,
      project: project
    } do
      {request, channel, snapshot} = create_channel_request(project)

      insert(:channel_event,
        channel_request: request,
        request_query_string: "format=json"
      )

      props = props(conn, project, request)

      assert props["project"] == %{
               "id" => project.id,
               "parentId" => nil,
               "color" => nil
             }

      assert props["projectLabel"] == project.name

      assert %{
               "id" => id,
               "state" => "success",
               "startedAt" => "2026-04-10T10:00:00.000000Z",
               "completedAt" => "2026-04-10T10:00:00.350000Z",
               "clientIdentity" => "192.168.1.1",
               "clientAuth" => "API key",
               "destinationAuth" => "None",
               "isWiped" => false,
               "snapshot" => %{
                 "name" => snapshot_name,
                 "destinationUrl" => snapshot_url,
                 "lockVersion" => lock_version
               }
             } = props["request"]

      assert id == request.id
      assert snapshot_name == snapshot.name
      assert snapshot_url == snapshot.destination_url
      assert lock_version == snapshot.lock_version

      # The old page never showed the proxy's request id or the raw ids.
      refute Map.has_key?(props["request"], "requestId")
      refute Map.has_key?(props["request"], "channelId")

      assert props["channel"] == %{
               "id" => channel.id,
               "projectId" => project.id,
               "name" => channel.name,
               "destinationUrl" => channel.destination_url,
               "lockVersion" => channel.lock_version
             }

      assert %{
               "type" => "destination_response",
               "requestMethod" => "POST",
               "requestPath" => "/api/v1/data",
               "requestQueryString" => "format=json",
               "requestHeaders" => headers,
               "responseStatus" => 200,
               "latencyUs" => 350_000,
               "reusedConnection" => false
             } = event(props)

      assert ["authorization", "[REDACTED]"] in headers
      assert Enum.any?(headers, &match?(["content-type", _], &1))
      assert event(props)["requestBodyPreview"] =~ "key"
      assert event(props)["responseBodyPreview"] =~ "ok"
    end

    test "sends only the primary event", %{conn: conn, project: project} do
      {request, _channel, _snapshot} = create_channel_request(project)

      insert(:channel_error_event,
        channel_request: request,
        error_message: "econnreset"
      )

      insert(:channel_event, channel_request: request)

      assert [%{"type" => "destination_response"}] =
               props(conn, project, request)["request"]["events"]
    end
  end

  describe "detail page — error state" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "sends the error code for a transport error", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} =
        create_channel_request(project, state: :error)

      insert(:channel_error_event,
        channel_request: request,
        error_message: "econnrefused",
        latency_us: 100_000
      )

      props = props(conn, project, request)

      assert props["request"]["state"] == "error"

      assert %{
               "type" => "error",
               "errorMessage" => "econnrefused",
               "latencyUs" => 100_000,
               "responseStatus" => nil
             } = event(props)
    end

    test "sends the error code for a credential error", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} =
        create_channel_request(project, state: :error)

      insert(:channel_error_event,
        channel_request: request,
        error_message: "credential_missing_auth_fields"
      )

      assert %{"errorMessage" => "credential_missing_auth_fields"} =
               props(conn, project, request) |> event()
    end
  end

  describe "detail page — timing" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "sends every phase as stored, with a null reused flag as false",
         %{conn: conn, project: project} do
      {request, _channel, _snapshot} = create_channel_request(project)

      insert(:channel_event,
        channel_request: request,
        reused_connection: nil,
        queue_us: 2_000,
        connect_us: 15_000,
        request_send_us: 5_000,
        ttfb_us: 180_000,
        response_duration_us: 65_000,
        latency_us: 260_000
      )

      assert %{
               "queueUs" => 2_000,
               "connectUs" => 15_000,
               "requestSendUs" => 5_000,
               "ttfbUs" => 180_000,
               "responseDurationUs" => 65_000,
               "latencyUs" => 260_000,
               "reusedConnection" => false
             } = props(conn, project, request) |> event()
    end

    test "sends a reused connection and missing phases as null",
         %{conn: conn, project: project} do
      {request, _channel, _snapshot} = create_channel_request(project)

      insert(:channel_event,
        channel_request: request,
        reused_connection: true,
        queue_us: nil,
        connect_us: nil,
        request_send_us: nil,
        response_duration_us: nil,
        ttfb_us: nil,
        latency_us: 420_000
      )

      assert %{
               "reusedConnection" => true,
               "queueUs" => nil,
               "connectUs" => nil,
               "requestSendUs" => nil,
               "responseDurationUs" => nil,
               "ttfbUs" => nil,
               "latencyUs" => 420_000
             } = props(conn, project, request) |> event()
    end
  end

  describe "detail page — context section" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "sends the snapshot and the channel's current version, which differ after a change",
         %{conn: conn, project: project, user: user} do
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          state: :success,
          started_at: DateTime.utc_now()
        )

      insert(:channel_event, channel_request: request)

      props = props(conn, project, request)

      assert props["request"]["snapshot"]["destinationUrl"] ==
               snapshot.destination_url

      assert props["request"]["snapshot"]["lockVersion"] == snapshot.lock_version
      assert props["channel"]["lockVersion"] == snapshot.lock_version

      {:ok, _updated} =
        Channels.update_channel(channel, %{name: "updated-name"}, actor: user)

      props = props(conn, project, request)
      assert props["request"]["snapshot"]["lockVersion"] == snapshot.lock_version
      assert props["channel"]["lockVersion"] == snapshot.lock_version + 1
      assert props["channel"]["name"] == "updated-name"
      assert props["request"]["snapshot"]["name"] == snapshot.name
    end
  end

  describe "detail page — bodies" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "sends a size without a preview when the body was not captured", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} = create_channel_request(project)

      insert(:channel_event,
        channel_request: request,
        request_body_preview: nil,
        request_body_hash: nil,
        request_body_size: 2048
      )

      assert %{
               "requestBodyPreview" => nil,
               "requestBodyHash" => nil,
               "requestBodySize" => 2048
             } = props(conn, project, request) |> event()
    end

    test "sends neither preview nor size when there was no body",
         %{conn: conn, project: project} do
      {request, _channel, _snapshot} =
        create_channel_request(project, state: :error)

      insert(:channel_error_event,
        channel_request: request,
        error_message: "credential_missing_auth_fields",
        request_body_preview: nil,
        request_body_hash: nil,
        request_body_size: nil
      )

      assert %{"requestBodyPreview" => nil, "requestBodySize" => nil} =
               props(conn, project, request) |> event()
    end

    test "sends the content type, size and hash of a binary body", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} = create_channel_request(project)

      insert(:channel_event,
        channel_request: request,
        response_headers: [["content-type", "application/octet-stream"]],
        response_body_preview: nil,
        response_body_size: 4096,
        response_body_hash: "binaryhash123"
      )

      assert %{
               "responseHeaders" => [
                 ["content-type", "application/octet-stream"]
               ],
               "responseBodyPreview" => nil,
               "responseBodySize" => 4096,
               "responseBodyHash" => "binaryhash123"
             } = props(conn, project, request) |> event()
    end
  end

  describe "detail page — wiped (zero-persistence) event" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    defp wiped_request(project) do
      {request, _channel, _snapshot} =
        create_channel_request(project, is_wiped: true, client_identity: nil)

      insert(:channel_event,
        channel_request: request,
        request_path: nil,
        request_query_string: nil,
        request_headers: nil,
        request_body_preview: nil,
        request_body_hash: nil,
        response_headers: nil,
        response_body_preview: nil,
        response_body_hash: nil
      )

      request
    end

    @tag role: :admin
    test "an admin may change the policy and gets no contacts",
         %{conn: conn, project: project} do
      insert(:project_user,
        project: project,
        user: insert(:user, email: "admin@example.com"),
        role: :admin
      )

      props = props(conn, project, wiped_request(project))

      assert props["request"]["isWiped"] == true
      assert props["request"]["clientIdentity"] == nil
      assert props["canEditDataRetention"] == true
      assert props["adminContacts"] == []

      assert %{
               "requestPath" => nil,
               "requestHeaders" => nil,
               "requestBodyPreview" => nil,
               "responseHeaders" => nil,
               "responseBodyPreview" => nil
             } = event(props)
    end

    @tag role: :editor
    test "an editor gets the admins to contact instead",
         %{conn: conn, project: project} do
      admin = insert(:user, email: "admin@example.com")
      insert(:project_user, project: project, user: admin, role: :admin)

      props = props(conn, project, wiped_request(project))

      assert props["canEditDataRetention"] == false
      assert props["adminContacts"] == ["admin@example.com"]
    end

    @tag role: :editor
    test "sends no contacts when the request was not wiped",
         %{conn: conn, project: project} do
      insert(:project_user,
        project: project,
        user: insert(:user, email: "admin@example.com"),
        role: :admin
      )

      {request, _channel, _snapshot} =
        create_channel_request(project, is_wiped: false)

      insert(:channel_event, channel_request: request)

      props = props(conn, project, request)

      assert props["request"]["isWiped"] == false
      assert props["adminContacts"] == []
      assert event(props)["requestHeaders"] != nil
      assert event(props)["responseHeaders"] != nil
    end
  end

  describe "security" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "cross-project isolation and invalid UUID both redirect", %{
      conn: conn,
      project: project
    } do
      other_project = insert(:project)
      {request, _channel, _snapshot} = create_channel_request(other_project)
      insert(:channel_event, channel_request: request)

      assert {:error, {:redirect, %{to: to}}} =
               live(conn, detail_path(project, request))

      assert to == "/projects/#{project.id}/history"

      assert {:error, {:redirect, _}} =
               live(
                 conn,
                 ~p"/projects/#{project.id}/history/channels/not-a-uuid"
               )
    end
  end

  describe "detail page — auth attribution" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "names the client auth method and the destination credential when both are set",
         %{conn: conn, project: project, user: user} do
      webhook_auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :api,
          name: "Prod API key"
        )

      credential =
        insert(:credential, user: user, name: "Destination API", schema: "http")

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      channel = insert(:channel, project: project)

      {request, _channel, _snap} =
        create_channel_request(project,
          channel: channel,
          client_auth_type: "api"
        )

      request
      |> Ecto.Changeset.change(%{
        client_webhook_auth_method_id: webhook_auth_method.id,
        destination_credential_id: project_credential.id
      })
      |> Lightning.Repo.update!()

      insert(:channel_event, channel_request: request)

      assert %{
               "clientAuth" => "Prod API key (API key)",
               "destinationAuth" => "Destination API"
             } = props(conn, project, request)["request"]
    end

    test "sends 'None' when no client auth was configured and the credential name when the destination is set",
         %{conn: conn, project: project, user: user} do
      credential =
        insert(:credential, user: user, name: "Only Destination", schema: "http")

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      {request, _channel, _snap} =
        create_channel_request(project, client_auth_type: nil)

      request
      |> Ecto.Changeset.change(%{
        client_webhook_auth_method_id: nil,
        destination_credential_id: project_credential.id
      })
      |> Lightning.Repo.update!()

      insert(:channel_event, channel_request: request)

      assert %{
               "clientAuth" => "None",
               "destinationAuth" => "Only Destination"
             } = props(conn, project, request)["request"]
    end

    test "sends 'None' without crashing after the destination credential is deleted",
         %{conn: conn, project: project, user: user} do
      credential =
        insert(:credential, user: user, name: "Will Be Gone", schema: "http")

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      {request, _channel, _snap} = create_channel_request(project)

      request
      |> Ecto.Changeset.change(%{
        destination_credential_id: project_credential.id
      })
      |> Lightning.Repo.update!()

      insert(:channel_event, channel_request: request)

      # The FK nilifies the id, so the helper answers "None"; the page still loads.
      Lightning.Repo.delete!(project_credential)

      assert props(conn, project, request)["request"]["destinationAuth"] in [
               "None",
               "(deleted)"
             ]

      reloaded =
        Lightning.Channels.get_channel_request_for_project(
          project.id,
          request.id
        )

      assert reloaded.destination_credential_id == nil
    end

    test "helper renders '(deleted)' for stale in-memory record with id but nil association" do
      # Directly test the helper to cover the belt-and-suspenders path
      # (id present, association nil) that the schema's on_delete: :nilify_all
      # prevents us from producing through the DB.
      stale = %Lightning.Channels.ChannelRequest{
        client_webhook_auth_method_id: Ecto.UUID.generate(),
        client_auth_type: "api",
        client_webhook_auth_method: nil,
        destination_credential_id: Ecto.UUID.generate(),
        destination_credential: nil
      }

      assert Helpers.format_client_auth(stale) =~ "(deleted)"
      assert Helpers.format_destination_auth(stale) == "(deleted)"
    end
  end

  describe "navigation" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "the page is titled and the breadcrumb has the project's label", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} = create_channel_request(project)
      insert(:channel_event, channel_request: request)

      {:ok, view, html} = live(conn, detail_path(project, request))

      assert html =~ "Channel Request"
      assert page_props(view, @page)["projectLabel"] == project.name
    end

    test "channel logs table rows link to the detail page", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project, name: "link-test")
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          state: :success,
          started_at: DateTime.utc_now()
        )

      insert(:channel_event, channel_request: request)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      html = render(view)

      assert html =~
               ~r/href="[^"]*\/projects\/#{project.id}\/history\/channels\/#{request.id}"/
    end
  end
end

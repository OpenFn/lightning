defmodule LightningWeb.ChannelRequestLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Channels

  setup :stub_rate_limiter_ok

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
        started_at: Map.get(attrs, :started_at, ~U[2026-04-10 10:00:00.000000Z]),
        completed_at:
          Map.get(attrs, :completed_at, ~U[2026-04-10 10:00:00.350000Z])
      )

    {request, channel, snapshot}
  end

  defp detail_path(project, request) do
    ~p"/projects/#{project.id}/history/channels/#{request.id}"
  end

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

    test "renders summary card, metadata, headers, and body previews", %{
      conn: conn,
      project: project
    } do
      {request, channel, _snapshot} = create_channel_request(project)

      insert(:channel_event,
        channel_request: request,
        request_query_string: "format=json"
      )

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      # Summary card
      assert html =~ "POST"
      assert html =~ "/api/v1/data"
      assert html =~ "format=json"
      assert html =~ "200"
      assert html =~ "Success"
      assert html =~ channel.name

      # Metadata
      assert html =~ "192.168.1.1"
      assert html =~ "api"
      assert html =~ String.slice(request.id, 0..7)
      assert html =~ "350"
      # Destination URL from channel
      assert html =~ channel.destination_url
      # Timestamps
      assert html =~ "2026"
      assert html =~ "10:00"

      # Request headers
      assert html =~ "content-type"
      assert html =~ "authorization"
      assert html =~ "[REDACTED]"

      # Body previews (quotes are HTML-entity-encoded by LiveView's test DOM serializer)
      assert html =~ "key"
      assert html =~ "value"
      assert html =~ "status"
      assert html =~ "ok"
    end
  end

  describe "detail page — error state" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "renders humanized error and raw string for transport error", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} =
        create_channel_request(project, state: :error)

      insert(:channel_error_event,
        channel_request: request,
        error_message: "econnrefused",
        latency_ms: 100
      )

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      assert html =~ "Connection refused"
      assert html =~ "econnrefused"
    end

    test "renders credential error with appropriate messaging", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} =
        create_channel_request(project, state: :error)

      insert(:channel_error_event,
        channel_request: request,
        error_message: "credential_missing_auth_fields"
      )

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      assert html =~ "missing required authentication fields"
      assert html =~ "credential_missing_auth_fields"
    end
  end

  describe "detail page — timing section" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "renders three-segment bar when all timing fields present", %{
      conn: conn,
      project: project
    } do
      {request, _channel, _snapshot} = create_channel_request(project)

      insert(:channel_event,
        channel_request: request,
        request_send_us: 5000,
        ttfb_ms: 280,
        response_duration_us: 65000,
        latency_ms: 350
      )

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      assert html =~ "timing-section"
      assert html =~ "350"
      assert html =~ "280"
    end

    test "falls back gracefully when timing fields are partially nil", %{
      conn: conn,
      project: project
    } do
      # Two-segment fallback: per-direction durations nil, TTFB + latency present
      {req1, _ch1, _snap1} = create_channel_request(project)

      insert(:channel_event,
        channel_request: req1,
        request_send_us: nil,
        response_duration_us: nil,
        ttfb_ms: 280,
        latency_ms: 350
      )

      {:ok, view1, _html} = live(conn, detail_path(project, req1))
      html1 = render(view1)
      assert html1 =~ "350"
      assert html1 =~ "280"

      # Single bar fallback: only latency_ms
      {req2, _ch2, _snap2} = create_channel_request(project)

      insert(:channel_event,
        channel_request: req2,
        request_send_us: nil,
        response_duration_us: nil,
        ttfb_ms: nil,
        latency_ms: 420
      )

      {:ok, view2, _html} = live(conn, detail_path(project, req2))
      html2 = render(view2)
      assert html2 =~ "420"
    end

    test "shows single bar for transport errors, hidden for credential errors",
         %{conn: conn, project: project} do
      # Transport error: timing section visible with single bar
      {req_transport, _ch1, _snap1} =
        create_channel_request(project, state: :timeout)

      insert(:channel_error_event,
        channel_request: req_transport,
        error_message: "response_timeout",
        latency_ms: 30000
      )

      {:ok, view1, _html} = live(conn, detail_path(project, req_transport))
      html1 = render(view1)
      assert html1 =~ "30000" or html1 =~ "30,000"

      # Credential error: timing section hidden entirely
      {req_cred, _ch2, _snap2} =
        create_channel_request(project, state: :error)

      insert(:channel_error_event,
        channel_request: req_cred,
        error_message: "credential_missing_auth_fields"
      )

      {:ok, view2, _html} = live(conn, detail_path(project, req_cred))
      html2 = render(view2)
      refute html2 =~ "timing-section"
    end
  end

  describe "detail page — context section" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "renders snapshot data and config changed indicator when versions differ",
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

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      # Snapshot data renders
      assert html =~ snapshot.destination_url
      assert html =~ to_string(snapshot.lock_version)

      # Bump channel version to create mismatch
      {:ok, _updated} =
        Channels.update_channel(channel, %{name: "updated-name"}, actor: user)

      {:ok, view2, _html} = live(conn, detail_path(project, request))
      html2 = render(view2)

      assert html2 =~ "changed" or html2 =~ "Config"
    end
  end

  describe "detail page — nil body" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "shows 'Body not captured' when body_preview is nil", %{
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

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      assert html =~ "Body not captured"
    end

    test "hides body sub-section entirely when both preview and size are nil",
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

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      refute html =~ "Body not captured"
      refute html =~ "request-body"
    end

    test "shows metadata only for binary (non-text) content-type", %{
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

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      # Should show size and hash metadata
      assert html =~ "4096" or html =~ "4.0 KB" or html =~ "4 KB"
      assert html =~ "binaryhash123"
      # Should NOT render a body preview <pre> block
      refute html =~ ~s({"status":"ok"})
    end
  end

  describe "security" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "cross-project isolation and invalid UUID both return 404", %{
      conn: conn,
      project: project
    } do
      other_project = insert(:project)
      {request, _channel, _snapshot} = create_channel_request(other_project)
      insert(:channel_event, channel_request: request)

      assert {:error, {:redirect, _}} =
               live(conn, detail_path(project, request))

      assert {:error, {:redirect, _}} =
               live(
                 conn,
                 ~p"/projects/#{project.id}/history/channels/not-a-uuid"
               )
    end
  end

  describe "navigation" do
    setup [:register_and_log_in_user, :create_project_for_current_user]
    setup :enable_experimental_features

    test "breadcrumbs render correctly", %{conn: conn, project: project} do
      {request, _channel, _snapshot} = create_channel_request(project)
      insert(:channel_event, channel_request: request)

      {:ok, view, _html} = live(conn, detail_path(project, request))
      html = render(view)

      assert html =~ "History"
      assert html =~ "Channel"
      assert html =~ String.slice(request.id, 0..7)
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

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
        latency_us: 100_000
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

    test "renders full nested timeline with all Finch phases, overhead, and reused connection",
         %{conn: conn, project: project} do
      # --- Full phases with overhead ---
      {req1, _ch1, _snap1} = create_channel_request(project)

      # inner_sum = 2+15+5+158+65 = 245ms, latency = 260ms => 15ms overhead
      insert(:channel_event,
        channel_request: req1,
        queue_us: 2_000,
        connect_us: 15_000,
        request_send_us: 5_000,
        ttfb_us: 180_000,
        response_duration_us: 65_000,
        latency_us: 260_000
      )

      {:ok, view1, _html} = live(conn, detail_path(project, req1))
      html1 = render(view1)

      # Timing section present with bookend labels
      assert html1 =~ ~s(id="timing-section")
      assert html1 =~ "0 ms"
      assert html1 =~ "260 ms"

      # Phase segment title attributes (tooltip text)
      assert html1 =~ ~s(title="Queue: 2 ms")
      assert html1 =~ ~s(title="Connect: 15 ms")
      assert html1 =~ ~s(title="Send: 5 ms")
      assert html1 =~ ~s(title="Processing: 158 ms")
      assert html1 =~ ~s(title="Recv: 65 ms")

      # TTFB marker and legend with overhead swatch
      assert html1 =~ "TTFB: 180 ms"
      assert html1 =~ "Proxy overhead"

      # --- Reused connection ---
      {req2, _ch2, _snap2} = create_channel_request(project)

      insert(:channel_event,
        channel_request: req2,
        reused_connection: true,
        queue_us: 1_000,
        connect_us: 0,
        request_send_us: 4_000,
        ttfb_us: 120_000,
        response_duration_us: 30_000,
        latency_us: 155_000
      )

      {:ok, view2, _html} = live(conn, detail_path(project, req2))
      html2 = render(view2)

      assert html2 =~ ~s(id="timing-section")
      assert html2 =~ "(reused)"

      # --- Processing segment from nil queue/connect ---
      {req3, _ch3, _snap3} = create_channel_request(project)

      # wait = ttfb - 0 - 0 - send = 200k - 10k = 190k
      insert(:channel_event,
        channel_request: req3,
        queue_us: nil,
        connect_us: nil,
        request_send_us: 10_000,
        ttfb_us: 200_000,
        response_duration_us: 50_000,
        latency_us: 260_000
      )

      {:ok, view3, _html} = live(conn, detail_path(project, req3))
      html3 = render(view3)

      assert html3 =~ ~s(title="Processing: 190 ms")
    end

    test "degrades gracefully through partial and minimal tiers",
         %{conn: conn, project: project} do
      # Partial tier: TTFB + latency only => TTFB/Download segments
      {req1, _ch1, _snap1} = create_channel_request(project)

      insert(:channel_event,
        channel_request: req1,
        request_send_us: nil,
        response_duration_us: nil,
        ttfb_us: 280_000,
        latency_us: 350_000
      )

      {:ok, view1, _html} = live(conn, detail_path(project, req1))
      html1 = render(view1)

      assert html1 =~ ~s(title="TTFB: 280 ms")
      assert html1 =~ ~s(title="Download: 70 ms")
      assert html1 =~ "350 ms"
      refute html1 =~ "Proxy overhead"

      # Minimal tier: only latency_us => single Total bar
      {req2, _ch2, _snap2} = create_channel_request(project)

      insert(:channel_event,
        channel_request: req2,
        request_send_us: nil,
        response_duration_us: nil,
        ttfb_us: nil,
        latency_us: 420_000
      )

      {:ok, view2, _html} = live(conn, detail_path(project, req2))
      html2 = render(view2)

      assert html2 =~ ~s(title="Total: 420 ms")
      assert html2 =~ "420 ms"
    end

    test "shows single bar for transport errors, hidden for credential errors",
         %{conn: conn, project: project} do
      {req_transport, _ch1, _snap1} =
        create_channel_request(project, state: :timeout)

      insert(:channel_error_event,
        channel_request: req_transport,
        error_message: "response_timeout",
        latency_us: 30_000_000
      )

      {:ok, view1, _html} = live(conn, detail_path(project, req_transport))
      html1 = render(view1)
      assert html1 =~ ~s(id="timing-section")
      assert html1 =~ ~s(title="Total: 30000 ms")

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

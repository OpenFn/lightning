defmodule LightningWeb.ChannelRequestLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Channels

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  # Helper: creates a channel request with a snapshot for a given channel.
  defp insert_channel_request(channel, opts \\ []) do
    {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)
    state = Keyword.get(opts, :state, :success)
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())

    insert(:channel_request,
      channel: channel,
      channel_snapshot: snapshot,
      state: state,
      started_at: started_at
    )
  end

  describe "access control" do
    test "redirects unauthenticated users to login", %{project: project} do
      conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/projects/#{project.id}/channels/requests")
    end

    test "renders the channel requests page for a project member", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ "Channel Requests"
    end
  end

  describe "table rendering" do
    test "shows empty state when project has no channel requests", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ "No channel requests found."
    end

    test "renders a row for each channel request in the project", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project, name: "my-channel")
      cr1 = insert_channel_request(channel, state: :success)
      cr2 = insert_channel_request(channel, state: :failed)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      html = render(view)

      assert html =~ cr1.request_id
      assert html =~ cr2.request_id
      assert html =~ "my-channel"
    end

    test "does not show requests from other projects", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project, name: "mine")
      cr = insert_channel_request(channel)

      other_project = insert(:project)
      other_channel = insert(:channel, project: other_project, name: "theirs")
      other_cr = insert_channel_request(other_channel)

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ cr.request_id
      refute html =~ other_cr.request_id
      refute html =~ "theirs"
    end

    test "shows request_path from :source_received event", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project)
      cr = insert_channel_request(channel)

      insert(:channel_event,
        channel_request: cr,
        type: :source_received,
        request_path: "/api/data/incoming"
      )

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ "/api/data/incoming"
    end

    test "shows error_message from :error event", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project)
      cr = insert_channel_request(channel, state: :error)

      insert(:channel_event,
        channel_request: cr,
        type: :error,
        error_message: "Connection timed out"
      )

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ "Connection timed out"
    end

    test "shows dash placeholders when no source or error events exist", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project)
      _cr = insert_channel_request(channel)

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      # Expect em-dashes for missing request path and error message
      assert html =~ "—"
    end

    test "renders state badges for each request state", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project)
      insert_channel_request(channel, state: :success)
      insert_channel_request(channel, state: :failed)
      insert_channel_request(channel, state: :pending)

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ "success"
      assert html =~ "failed"
      assert html =~ "pending"
    end
  end

  describe "channel filter" do
    test "shows all channels in the dropdown", %{
      conn: conn,
      project: project
    } do
      insert(:channel, project: project, name: "alpha-channel")
      insert(:channel, project: project, name: "beta-channel")

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ "alpha-channel"
      assert html =~ "beta-channel"
      assert html =~ "All Channels"
    end

    test "filters requests by channel_id query param", %{
      conn: conn,
      project: project
    } do
      ch1 = insert(:channel, project: project, name: "channel-one")
      ch2 = insert(:channel, project: project, name: "channel-two")
      cr1 = insert_channel_request(ch1)
      cr2 = insert_channel_request(ch2)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/channels/requests?filters[channel_id]=#{ch1.id}"
        )

      assert html =~ cr1.request_id
      refute html =~ cr2.request_id
    end

    test "changing the dropdown sends push_patch with new channel_id", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project, name: "filter-me")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      view
      |> element("#channel-request-filter-form")
      |> render_change(%{"filters" => %{"channel_id" => channel.id}})

      assert_patch(
        view,
        ~p"/projects/#{project.id}/channels/requests?filters[channel_id]=#{channel.id}"
      )
    end

    test "selecting All Channels clears the filter", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/channels/requests?filters[channel_id]=#{channel.id}"
        )

      view
      |> element("#channel-request-filter-form")
      |> render_change(%{"filters" => %{"channel_id" => ""}})

      assert_patch(view, ~p"/projects/#{project.id}/channels/requests")
    end
  end

  describe "pagination" do
    test "pagination bar renders when total entries exceed page size", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project)

      # Insert 11 requests to exceed the default page size of 10
      for i <- 1..11 do
        started_at =
          DateTime.add(~U[2025-01-01 00:00:00Z], i * 60, :second)

        insert_channel_request(channel, started_at: started_at)
      end

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      # Pagination bar should be present
      assert html =~ "Next"
    end

    test "pagination is absent when total entries fit on one page", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project)

      for _ <- 1..5 do
        insert_channel_request(channel)
      end

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      refute html =~ "Next"
    end
  end

  describe "breadcrumbs" do
    test "renders breadcrumb link back to the channels list", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/requests")

      assert html =~ "Channels"
      assert html =~ ~p"/projects/#{project.id}/channels"
    end
  end
end
